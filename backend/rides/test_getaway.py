from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User, DriverProfile
from .admin import ServiceRateForm
from .models import Booking, ServiceRate, Vehicle, Notification
from .pricing import estimate_fare


class GetawayTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.customer = User.objects.create_user(email='getaway@example.com', full_name='Customer', password='test-password', email_verified=True)
        self.vehicle = Vehicle.objects.create(owner=self.customer, make='Test', model='Car', registration='UP14AB1234')
        self.client.force_authenticate(self.customer)
        self.start = timezone.now() + timedelta(days=3)
        self.end = self.start + timedelta(days=2)
        self.payload = {
            'vehicle_id': self.vehicle.pk, 'service': 'GETAWAY', 'duration_hours': 20,
            'pickup': 'Customer pickup', 'pickup_latitude': '28.7000000', 'pickup_longitude': '77.7000000',
            'drop_address': 'Getaway destination', 'drop_latitude': '29.0000000', 'drop_longitude': '78.0000000',
            'scheduled_at': self.start.isoformat(), 'return_at': self.end.isoformat(),
        }

    def enable(self, base=250, per_hour=125):
        rate = ServiceRate.objects.get(service='GETAWAY')
        rate.base, rate.per_hour, rate.enabled = base, per_hour, True
        rate.save()
        return rate

    def book(self, **kwargs):
        return self.client.post(reverse('ride-bookings'), {**self.payload, **kwargs}, format='json')

    def test_disabled_by_default_and_no_bookings(self):
        rate = ServiceRate.objects.get(service='GETAWAY')
        self.assertFalse(rate.enabled)
        pricing = self.client.get(reverse('ride-pricing')).data['services']
        self.assertNotIn('GETAWAY', [row['key'] for row in pricing])
        self.assertEqual(self.book().status_code, 400)
        self.assertFalse(Booking.objects.exists())
        form = ServiceRateForm({'base': 0, 'per_hour': 0, 'enabled': True}, instance=rate)
        self.assertFalse(form.is_valid())

    def test_admin_can_enable_with_rates_but_not_enable_zero_rates(self):
        admin = User.objects.create_superuser(email='getawayadmin@example.com', full_name='Staff', password='test-password')
        rate = ServiceRate.objects.get(service='GETAWAY')
        self.client.force_login(admin)
        url = reverse('admin:rides_servicerate_change', args=[rate.pk])
        response = self.client.post(url, {'base': 0, 'per_hour': 0, 'enabled': 'on', '_save': 'Save'})
        self.assertEqual(response.status_code, 200)
        rate.refresh_from_db()
        self.assertFalse(rate.enabled)
        response = self.client.post(url, {'base': 250, 'per_hour': 125, 'enabled': 'on', '_save': 'Save'})
        self.assertEqual(response.status_code, 302)
        rate.refresh_from_db()
        self.assertTrue(rate.enabled)
        self.assertEqual((rate.base, rate.per_hour), (250, 125))
        self.client.force_authenticate(self.customer)

    def test_admin_rates_drive_server_price_and_return_time(self):
        rate = self.enable()
        self.assertEqual(estimate_fare('GETAWAY', 20), Decimal('2750'))
        pricing = self.client.get(reverse('ride-pricing')).data['services']
        row = next(row for row in pricing if row['key'] == 'GETAWAY')
        self.assertEqual((row['base'], row['per_hour']), (250, 125))
        resp = self.book(estimated_fare=1)
        self.assertEqual(resp.status_code, 201, resp.data)
        self.assertEqual(Decimal(str(resp.data['estimated_fare'])), Decimal('2750'))
        self.assertIsNotNone(resp.data['return_at'])
        saved = Booking.objects.get(pk=resp.data['id'])
        self.assertEqual(saved.return_at, self.end)
        rate.base = 999
        rate.save()
        saved.refresh_from_db()
        self.assertEqual(saved.estimated_fare, Decimal('2750'))

    def test_rejects_bad_times_hours_and_destination(self):
        self.enable()
        invalids = [
            {'return_at': None},
            {'scheduled_at': None},
            {'return_at': (self.start - timedelta(hours=1)).isoformat()},
            {'return_at': (self.start + timedelta(days=32)).isoformat()},
            {'duration_hours': 49},
            {'duration_hours': 745},
            {'drop_address': ''},
            {'drop_latitude': None},
        ]
        for data in invalids:
            with self.subTest(data=data):
                self.assertEqual(self.book(**data).status_code, 400)
        self.assertFalse(Booking.objects.exists())
        self.assertEqual(self.book(service='HOURLY', duration_hours=15, return_at=None).status_code, 400)
        self.assertEqual(self.book(service='HOURLY', duration_hours=2).status_code, 400)

    def test_driver_must_have_outstation_skill_and_can_see_return(self):
        self.enable()
        drivers = []
        for number, eligible in enumerate([False, True]):
            driver = User.objects.create_user(email=f'gd{number}@example.com', full_name='Driver', password='test-password', role=User.Role.DRIVER, email_verified=True)
            profile, _ = DriverProfile.objects.get_or_create(user=driver)
            profile.verification_status = DriverProfile.Status.APPROVED
            profile.is_available = True
            profile.manual_transmission = True
            profile.outstation = eligible
            profile.save()
            drivers.append(driver)
        response = self.book()
        self.assertEqual(response.status_code, 201, response.data)
        self.assertFalse(Notification.objects.filter(user=drivers[0], kind='BOOKING_REQUEST').exists())
        self.assertTrue(Notification.objects.filter(user=drivers[1], kind='BOOKING_REQUEST').exists())
        self.client.force_authenticate(drivers[0])
        not_eligible = self.client.get(reverse('ride-requests'))
        self.assertFalse(any(b['id'] == response.data['id'] for b in not_eligible.data['results']))
        self.client.force_authenticate(drivers[1])
        eligible = self.client.get(reverse('ride-requests'))
        offer = next(b for b in eligible.data['results'] if b['id'] == response.data['id'])
        self.assertIsNotNone(offer['return_at'])
