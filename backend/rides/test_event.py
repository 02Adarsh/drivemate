from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User, DriverProfile
from .models import Booking, ServiceRate, Vehicle


class EventDriverTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.customer = User.objects.create_user(
            email='eventcustomer@example.com', full_name='Customer', password='test-pass', email_verified=True)
        self.vehicle = Vehicle.objects.create(owner=self.customer, make='Test', model='Car', registration='UP14AB1234')
        self.client.force_authenticate(self.customer)
        self.payload = {
            'vehicle_id': self.vehicle.pk, 'service': 'EVENT', 'duration_hours': 8,
            'pickup': 'Customer pickup', 'pickup_latitude': '28.7000000', 'pickup_longitude': '77.7000000',
            'scheduled_at': (timezone.now() + timedelta(days=3)).isoformat(),
        }

    def book(self, **overrides):
        return self.client.post(reverse('ride-bookings'), {**self.payload, **overrides}, format='json')

    def enable_rate(self, base=200, per_hour=100):
        rate = ServiceRate.objects.get(service='EVENT')
        rate.base, rate.per_hour, rate.enabled = base, per_hour, True
        rate.save()
        return rate

    def test_initially_disabled_and_backend_rejects_booking(self):
        self.assertFalse(ServiceRate.objects.get(service='EVENT').enabled)
        self.assertNotIn('EVENT', [r['key'] for r in self.client.get(reverse('ride-pricing')).data['services']])
        response = self.book()
        self.assertEqual(response.status_code, 400)
        self.assertFalse(Booking.objects.exists())

    def test_admin_sets_rate_and_server_prices_it(self):
        admin = User.objects.create_superuser(email='eventadmin@example.com', full_name='Admin', password='test-pass')
        rate = ServiceRate.objects.get(service='EVENT')
        self.client.force_login(admin)
        url = reverse('admin:rides_servicerate_change', args=[rate.pk])
        bad = self.client.post(url, {'base': 0, 'per_hour': 0, 'enabled': 'on', '_save': 'Save'})
        self.assertEqual(bad.status_code, 200)
        rate.refresh_from_db()
        self.assertFalse(rate.enabled)
        good = self.client.post(url, {'base': 200, 'per_hour': 100, 'enabled': 'on', '_save': 'Save'})
        self.assertEqual(good.status_code, 302)
        self.client.force_authenticate(self.customer)
        row = next(r for r in self.client.get(reverse('ride-pricing')).data['services'] if r['key'] == 'EVENT')
        self.assertEqual((row['base'], row['per_hour']), (200, 100))
        response = self.book(estimated_fare=1)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Decimal(str(response.data['estimated_fare'])), Decimal('1000'))
        rate.refresh_from_db()
        rate.base = 999
        rate.save()
        self.assertEqual(Booking.objects.get(pk=response.data['id']).estimated_fare, Decimal('1000'))

    def test_requires_future_schedule_and_valid_hours(self):
        self.enable_rate()
        for changes in [
            {'scheduled_at': None},
            {'scheduled_at': (timezone.now() - timedelta(hours=1)).isoformat()},
            {'duration_hours': 15},
            {'duration_hours': 0},
            {'return_at': (timezone.now() + timedelta(days=4)).isoformat()},
        ]:
            with self.subTest(changes=changes):
                self.assertEqual(self.book(**changes).status_code, 400)
        self.assertFalse(Booking.objects.exists())

    def test_offer_visible_to_eligible_driver_and_contains_start(self):
        self.enable_rate()
        driver = User.objects.create_user(email='eventdriver@example.com', full_name='Driver', password='test-pass', role=User.Role.DRIVER, email_verified=True)
        profile, _ = DriverProfile.objects.get_or_create(user=driver)
        profile.verification_status = DriverProfile.Status.APPROVED
        profile.is_available = True
        profile.manual_transmission = True
        profile.outstation = False
        profile.save()
        response = self.book()
        self.assertEqual(response.status_code, 201, response.data)
        self.client.force_authenticate(driver)
        results = self.client.get(reverse('ride-requests')).data['results']
        offer = next(r for r in results if r['id'] == response.data['id'])
        self.assertEqual(offer['service'], 'EVENT')
        self.assertIsNotNone(offer['scheduled_at'])
