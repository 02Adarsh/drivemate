from datetime import timedelta
from decimal import Decimal
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient
from accounts.models import User, DriverProfile
from .models import Booking, ServiceRate, Vehicle

class FeatureTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.customer = User.objects.create_user(email='customer-CORPORATE@example.com', full_name='Test', password='test-password', email_verified=True)
        self.car = Vehicle.objects.create(owner=self.customer, make='Test', model='Car', registration='UP14AB1234')
        self.client.force_authenticate(self.customer)
        self.payload = {'vehicle_id': self.car.pk, 'service': 'CORPORATE', 'duration_hours': 4,
            'pickup': 'Pickup address', 'pickup_latitude': '28.7000000', 'pickup_longitude': '77.7000000',
            'scheduled_at': (timezone.now() + timedelta(days=3)).isoformat(),
            'drop_address': 'Destination address', 'drop_latitude': '29.0000000', 'drop_longitude': '78.0000000'}

    def book(self, **changes):
        return self.client.post(reverse('ride-bookings'), {**self.payload, **changes}, format='json')

    def enable(self):
        rate = ServiceRate.objects.get(service='CORPORATE')
        rate.base, rate.per_hour, rate.enabled = 200, 100, True
        rate.save()
        return rate

    def test_disabled_by_default_and_direct_booking_rejected(self):
        self.assertFalse(ServiceRate.objects.get(service='CORPORATE').enabled)
        self.assertNotIn('CORPORATE', [r['key'] for r in self.client.get(reverse('ride-pricing')).data['services']])
        self.assertEqual(self.book().status_code, 400)
        self.assertFalse(Booking.objects.exists())

    def test_admin_configures_rate_and_server_ignores_client_price(self):
        admin = User.objects.create_superuser(email='admin-CORPORATE@example.com', full_name='Admin', password='test-password')
        rate = ServiceRate.objects.get(service='CORPORATE')
        self.client.force_login(admin)
        url = reverse('admin:rides_servicerate_change', args=[rate.pk])
        self.assertEqual(self.client.post(url, {'base': 0, 'per_hour': 0, 'enabled': 'on', '_save': 'Save'}).status_code, 200)
        rate.refresh_from_db()
        self.assertFalse(rate.enabled)
        self.assertEqual(self.client.post(url, {'base': 200, 'per_hour': 100, 'enabled': 'on', '_save': 'Save'}).status_code, 302)
        self.client.force_authenticate(self.customer)
        row = next(r for r in self.client.get(reverse('ride-pricing')).data['services'] if r['key'] == 'CORPORATE')
        self.assertEqual((row['base'], row['per_hour']), (200, 100))
        response = self.book(estimated_fare=1)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Decimal(str(response.data['estimated_fare'])), Decimal('600'))
        rate.refresh_from_db(); rate.base = 999; rate.save()
        self.assertEqual(Booking.objects.get(pk=response.data['id']).estimated_fare, Decimal('600'))

    def test_time_and_hours_are_validated(self):
        self.enable()
        self.assertEqual(self.book(duration_hours=15).status_code, 400)
        self.assertEqual(self.book(scheduled_at=(timezone.now() - timedelta(hours=1)).isoformat()).status_code, 400)
        self.assertEqual(self.book(return_at=(timezone.now() + timedelta(days=4)).isoformat()).status_code, 400)
        self.assertEqual(self.book(scheduled_at=None).status_code, 400)

    def test_eligible_driver_can_see_offer(self):
        self.enable()
        driver = User.objects.create_user(email='driver-CORPORATE@example.com', full_name='Driver', password='test-password', role=User.Role.DRIVER, email_verified=True)
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
        self.assertEqual(offer['service'], 'CORPORATE')
        self.assertIsNotNone(offer['scheduled_at'])

