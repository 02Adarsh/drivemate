"""End-to-end tests for the booking engine.

Run with:  python manage.py test rides -v 2

These cover the rules the app's booking screens depend on:
  * a customer can only book with a car from their own garage,
  * only an **approved and available** driver sees the request feed,
  * the first driver to accept wins; a second attempt gets a clear conflict,
  * the fare comes from the server, never from the client,
  * start/complete only work for the assigned driver, in the right order,
  * notifications are written for both sides at every step.
"""

from django.test import TransactionTestCase, override_settings
from django.urls import reverse
from rest_framework.test import APITestCase

from accounts.models import DriverProfile, User

from .models import Booking, Notification, Vehicle
from .pricing import estimate_fare

PASSWORD = 'Str0ngPass!23'


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class BookingFlowTests(APITestCase):
    def setUp(self):
        super().setUp()
        from django.core.cache import cache
        cache.clear()

    def start_trip(self, booking_id):
        booking = Booking.objects.get(pk=booking_id)
        if booking.status != 'ACCEPTED' or not booking.driver_id:
            return self.client.post(reverse('ride-trip-start', args=[booking_id]), {'otp':'000000'}, format='json')
        self.auth(booking.customer)
        code = self.client.get(reverse('ride-start-code', args=[booking_id])).data['otp']
        self.auth(booking.driver)
        return self.client.post(reverse('ride-trip-start', args=[booking_id]), {'otp':code}, format='json')

    # ------------------------------------------------------------- fixtures

    def make_user(self, email, role, name='Test Person', phone='+919000000123'):
        user = User.objects.create_user(email=email, full_name=name, password=PASSWORD, phone=phone)
        user.role = role
        user.email_verified = True
        user.save()
        return user

    def make_customer(self, email='rider@example.com'):
        return self.make_user(email, User.Role.CUSTOMER, 'Test Rider')

    def make_driver(self, email='driver@example.com', *, approved=True, available=True):
        user = self.make_user(email, User.Role.DRIVER, 'Test Driver')
        profile, _ = DriverProfile.objects.get_or_create(user=user)
        profile.verification_status = (
            DriverProfile.Status.APPROVED if approved else DriverProfile.Status.PENDING_REVIEW
        )
        profile.is_available = available and approved
        profile.city = 'Gurugram'
        profile.manual_transmission = True
        profile.automatic_transmission = True
        profile.night_driving = True
        profile.outstation = True
        profile.save()
        return user

    def auth(self, user):
        from rest_framework_simplejwt.tokens import RefreshToken

        token = RefreshToken.for_user(user).access_token
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')

    def add_vehicle(self, customer, registration='HR26AB1234'):
        self.auth(customer)
        response = self.client.post(
            reverse('ride-vehicles'),
            {'make': 'Maruti Suzuki', 'model': 'Dzire', 'registration': registration,
             'fuel': 'PETROL', 'transmission': 'MANUAL', 'seats': 5},
            format='json',
        )
        self.assertEqual(response.status_code, 201, response.data)
        return response.data

    def create_booking(self, customer, **overrides):
        payload = {
            'vehicle_id': Vehicle.objects.filter(owner=customer).values_list('id', flat=True).first(),
            'service': 'HOURLY',
            'duration_hours': 4,
            'pickup': 'Sector 15, near the metro gate',
            'pickup_latitude':'28.4595000','pickup_longitude':'77.0266000',
            'drop_address': '',
            'notes': '',
        }
        payload.update(overrides)
        self.auth(customer)
        return self.client.post(reverse('ride-bookings'), payload, format='json')

    # ------------------------------------------------------------ vehicles

    def test_vehicle_crud_and_default_handling(self):
        customer = self.make_customer()
        first = self.add_vehicle(customer, 'HR26AB1234')
        self.assertTrue(first['is_default'], 'The first car becomes the default automatically.')

        second = self.add_vehicle(customer, 'HR26CD5678')
        self.assertFalse(second['is_default'])

        duplicate = self.client.post(
            reverse('ride-vehicles'),
            {'make': 'Hyundai', 'model': 'i20', 'registration': 'hr26ab1234'},
            format='json',
        )
        self.assertEqual(duplicate.status_code, 400)

        response = self.client.put(
            reverse('ride-vehicle-detail', args=[second['id']]),
            {'is_default': True},
            format='json',
        )
        self.assertEqual(response.status_code, 200)
        listing = self.client.get(reverse('ride-vehicles')).data['results']
        defaults = [vehicle for vehicle in listing if vehicle['is_default']]
        self.assertEqual(len(defaults), 1)
        self.assertEqual(defaults[0]['id'], second['id'])

        driver = self.make_driver()
        self.auth(driver)
        self.assertEqual(self.client.get(reverse('ride-vehicles')).status_code, 403)

    # ------------------------------------------------------------ booking

    def test_customer_cannot_book_without_a_vehicle(self):
        customer = self.make_customer()
        response = self.create_booking(customer)
        self.assertEqual(response.status_code, 400)
        self.assertIn('vehicle', response.data.get('missing_fields', []))

    def test_fare_is_calculated_on_the_server(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        response = self.create_booking(customer, estimated_fare=1, final_fare=1)
        self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(float(response.data['estimated_fare']), float(estimate_fare('HOURLY', 4)))
        self.assertNotEqual(float(response.data['estimated_fare']), 1.0)

    def test_only_approved_and_available_drivers_see_the_feed(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        self.create_booking(customer)

        pending = self.make_driver('pending@example.com', approved=False)
        self.auth(pending)
        self.assertEqual(self.client.get(reverse('ride-requests')).status_code, 403)

        offline = self.make_driver('offline@example.com', available=False)
        self.auth(offline)
        feed = self.client.get(reverse('ride-requests'))
        self.assertEqual(feed.status_code, 200)
        self.assertFalse(feed.data['is_available'])
        self.assertEqual(feed.data['count'], 0)
        booking_id = Booking.objects.get(customer=customer).pk
        blocked = self.client.post(reverse('ride-request-accept', args=[booking_id]))
        self.assertEqual(blocked.status_code, 400)

        online = self.make_driver('online@example.com', available=True)
        self.auth(online)
        feed = self.client.get(reverse('ride-requests'))
        self.assertEqual(feed.status_code, 200)
        self.assertEqual(feed.data['count'], 1)
        accepted = self.client.post(reverse('ride-request-accept', args=[feed.data['results'][0]['id']]))
        self.assertEqual(accepted.status_code, 200, accepted.data)
        self.assertEqual(accepted.data['status'], Booking.Status.ACCEPTED)
        self.assertEqual(accepted.data['driver']['id'], online.pk)

        notifications = Notification.objects.filter(user=customer, kind='BOOKING_ACCEPTED')
        self.assertEqual(notifications.count(), 1)

    def test_second_driver_cannot_steal_an_accepted_request(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']

        first = self.make_driver('first@example.com')
        second = self.make_driver('second@example.com')

        self.auth(first)
        self.assertEqual(self.client.post(reverse('ride-request-accept', args=[booking_id])).status_code, 200)

        self.auth(second)
        conflict = self.client.post(reverse('ride-request-accept', args=[booking_id]))
        self.assertIn(conflict.status_code, (404, 409))

    def test_full_trip_lifecycle_updates_fares_earnings_and_timeline(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver('lifecycle@example.com')

        self.auth(driver)
        self.client.post(reverse('ride-request-accept', args=[booking_id]))
        started = self.start_trip(booking_id)
        self.assertEqual(started.status_code, 200, started.data)
        self.assertEqual(started.data['status'], Booking.Status.ONGOING)

        completed = self.client.post(reverse('ride-trip-complete', args=[booking_id]))
        self.assertEqual(completed.status_code, 200, completed.data)
        booking = Booking.objects.get(pk=booking_id)
        self.assertEqual(booking.status, Booking.Status.COMPLETED)
        self.assertEqual(booking.final_fare, booking.estimated_fare)
        self.assertLess(booking.payout, booking.final_fare, 'The platform fee must be deducted.')

        kinds = list(booking.events.values_list('kind', flat=True))
        self.assertEqual(kinds, ['CREATED', 'ACCEPTED', 'STARTED', 'COMPLETED'])

        summary = self.client.get(reverse('ride-summary'))
        self.assertEqual(summary.status_code, 200)
        self.assertEqual(summary.data['completed_trips'], 1)
        self.assertAlmostEqual(float(summary.data['lifetime']), float(booking.payout), places=2)
        self.assertEqual(len(summary.data['daily']), 7)

        self.auth(customer)
        self.assertEqual(self.client.post(reverse('ride-trip-complete', args=[booking_id])).status_code, 403)

    def test_steps_cannot_be_skipped(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver('skipper@example.com')

        self.auth(driver)
        self.assertEqual(self.client.post(reverse('ride-trip-complete', args=[booking_id])).status_code, 404)
        self.client.post(reverse('ride-request-accept', args=[booking_id]))
        self.assertEqual(self.start_trip(booking_id).status_code, 200)
        self.assertEqual(self.start_trip(booking_id).status_code, 400)

    def test_customer_cancel_notifies_the_driver(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver('cancelme@example.com')

        self.auth(driver)
        self.client.post(reverse('ride-request-accept', args=[booking_id]))
        Notification.objects.all().delete()

        self.auth(customer)
        cancelled = self.client.post(
            reverse('ride-booking-cancel', args=[booking_id]), {'reason': 'Plans changed'}, format='json'
        )
        self.assertEqual(cancelled.status_code, 200, cancelled.data)
        self.assertEqual(cancelled.data['status'], Booking.Status.CANCELLED)
        self.assertTrue(Notification.objects.filter(user=driver, kind='BOOKING_CANCELLED').exists())

        again = self.client.post(reverse('ride-booking-cancel', args=[booking_id]), {'reason': 'Plans changed'}, format='json')
        self.assertEqual(again.status_code, 400)

    def test_one_active_booking_per_customer(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        self.assertEqual(self.create_booking(customer).status_code, 201)
        second = self.create_booking(customer)
        self.assertEqual(second.status_code, 400)
        self.assertIn('already have a booking', second.data['detail'])

    def test_availability_toggle_requires_approval(self):
        pending = self.make_driver('nope@example.com', approved=False)
        self.auth(pending)
        response = self.client.post(reverse('ride-availability'), {'available': True}, format='json')
        self.assertEqual(response.status_code, 403)

        approved = self.make_driver('yes@example.com', approved=True, available=False)
        self.auth(approved)
        turned_on = self.client.post(reverse('ride-availability'), {'available': True}, format='json')
        self.assertEqual(turned_on.status_code, 200)
        self.assertTrue(turned_on.data['is_available'])
        self.assertTrue(DriverProfile.objects.get(user=approved).is_available)

    def test_declined_requests_leave_the_feed(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver('decliner@example.com')

        self.auth(driver)
        self.assertEqual(self.client.get(reverse('ride-requests')).data['count'], 1)
        self.client.post(reverse('ride-request-decline', args=[booking_id]))
        self.assertEqual(self.client.get(reverse('ride-requests')).data['count'], 0)

    def test_notifications_and_mark_read(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        self.create_booking(customer)

        listing = self.client.get(reverse('ride-notifications'))
        self.assertEqual(listing.status_code, 200)
        self.assertEqual(listing.data['unread'], 1)
        first_id = listing.data['results'][0]['id']
        marked = self.client.post(reverse('ride-notification-read', args=[first_id]))
        self.assertEqual(marked.status_code, 200)
        self.assertEqual(marked.data['unread'], 0)

    def test_request_retry_is_idempotent(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        first = self.create_booking(customer, request_key='same-phone-request-01')
        again = self.create_booking(customer, request_key='same-phone-request-01', estimated_fare=1)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(again.status_code, 200)
        self.assertEqual(first.data['id'], again.data['id'])
        self.assertEqual(Booking.objects.count(), 1)
        self.assertEqual(Booking.objects.first().events.count(), 1)
        self.assertEqual(Notification.objects.filter(user=customer).count(), 1)

    def test_cannot_use_another_customers_car(self):
        owner = self.make_customer('owner@example.com')
        thief = self.make_customer('other@example.com')
        owned = self.add_vehicle(owner)
        self.add_vehicle(thief, 'DL01AB4567')
        response = self.create_booking(thief, vehicle_id=owned['id'])
        self.assertEqual(response.status_code, 400)
        self.assertEqual(Booking.objects.count(), 0)

    def test_open_feed_redacts_contact_and_number_plate(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver()
        self.auth(driver)
        offer = self.client.get(reverse('ride-requests')).data['results'][0]
        self.assertEqual(offer['customer']['phone'], '')
        self.assertEqual(offer['customer']['email'], '')
        self.assertEqual(offer['vehicle']['registration'], '')
        self.assertFalse(offer['can_cancel'])
        accepted = self.client.post(reverse('ride-request-accept', args=[booking_id]))
        self.assertEqual(accepted.data['customer']['phone'], customer.phone)
        self.assertEqual(accepted.data['vehicle']['registration'], 'HR26AB1234')

    def test_one_live_trip_per_driver(self):
        first_customer = self.make_customer('one@example.com')
        self.add_vehicle(first_customer)
        first_id = self.create_booking(first_customer).data['id']
        second_customer = self.make_customer('two@example.com')
        self.add_vehicle(second_customer)
        second_id = self.create_booking(second_customer).data['id']
        driver = self.make_driver()
        self.auth(driver)
        self.assertEqual(self.client.post(reverse('ride-request-accept', args=[first_id])).status_code, 200)
        second = self.client.post(reverse('ride-request-accept', args=[second_id]))
        self.assertEqual(second.status_code, 409)
        self.assertEqual(self.client.get(reverse('ride-requests')).data['count'], 0)
        self.assertIsNone(Booking.objects.get(pk=second_id).driver_id)

    def test_invalid_values_are_400_not_server_errors(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        for invalid in ['abc', -1, 0, 99, 2.5]:
            with self.subTest(hours=invalid):
                self.assertEqual(self.create_booking(customer, duration_hours=invalid).status_code, 400)
        for schedule in ['not-a-date', '2000-01-01T10:00:00Z', '2099-01-01T10:00:00Z']:
            with self.subTest(schedule=schedule):
                self.assertEqual(self.create_booking(customer, scheduled_at=schedule).status_code, 400)
        self.assertEqual(self.create_booking(customer, pickup='x'*241).status_code, 400)
        self.assertEqual(self.create_booking(customer, service='OUTSTATION', duration_hours=8, drop_address='').status_code, 400)
        self.assertEqual(self.create_booking(customer, service='FULL_DAY', duration_hours=2).status_code, 400)
        for seats in ['bad', 0, 20]:
            response = self.client.post(reverse('ride-vehicles'), {
                'make': 'Hyundai', 'model': 'i20', 'registration': 'DL02AB5678', 'seats': seats,
            }, format='json')
            self.assertEqual(response.status_code, 400)

    def test_live_vehicle_cannot_be_removed_or_changed(self):
        customer = self.make_customer()
        car = self.add_vehicle(customer)
        self.create_booking(customer)
        url = reverse('ride-vehicle-detail', args=[car['id']])
        self.assertEqual(self.client.delete(url).status_code, 400)
        self.assertEqual(self.client.put(url, {'model': 'Different'}, format='json').status_code, 400)
        self.assertEqual(self.client.put(url, {'is_default': True}, format='json').status_code, 200)

    def test_vehicle_snapshot_survives_edit_and_delete(self):
        customer = self.make_customer()
        car = self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver()
        self.auth(driver)
        self.client.post(reverse('ride-request-accept', args=[booking_id]))
        self.start_trip(booking_id)
        self.client.post(reverse('ride-trip-complete', args=[booking_id]))
        self.auth(customer)
        self.client.put(reverse('ride-vehicle-detail', args=[car['id']]), {'model': 'New model'}, format='json')
        self.client.delete(reverse('ride-vehicle-detail', args=[car['id']]))
        history = self.client.get(reverse('ride-booking-detail', args=[booking_id]))
        self.assertEqual(history.status_code, 200)
        self.assertEqual(history.data['vehicle']['model'], 'Dzire')
        self.assertEqual(history.data['vehicle']['registration'], 'HR26AB1234')

    def test_default_is_reassigned_after_removal(self):
        customer = self.make_customer()
        first = self.add_vehicle(customer)
        second = self.add_vehicle(customer, 'DL01AB8765')
        self.client.delete(reverse('ride-vehicle-detail', args=[first['id']]))
        self.assertTrue(Vehicle.objects.get(pk=second['id']).is_default)

    def test_complete_is_not_double_counted_and_running_trip_cannot_cancel(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        driver = self.make_driver()
        self.auth(driver)
        self.client.post(reverse('ride-request-accept', args=[booking_id]))
        self.start_trip(booking_id)
        cancel = self.client.post(reverse('ride-booking-cancel', args=[booking_id]), {'reason': 'Changed plans'}, format='json')
        self.assertEqual(cancel.status_code, 400)
        self.assertEqual(self.client.post(reverse('ride-trip-complete', args=[booking_id])).status_code, 200)
        self.assertEqual(self.client.post(reverse('ride-trip-complete', args=[booking_id])).status_code, 400)
        self.assertEqual(Booking.objects.get(pk=booking_id).events.filter(kind='COMPLETED').count(), 1)
        self.assertEqual(Notification.objects.filter(user=driver, kind='PAYOUT').count(), 1)

    def test_other_accounts_cannot_see_private_bookings_or_notifications(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        booking_id = self.create_booking(customer).data['id']
        notification_id = Notification.objects.filter(user=customer).first().pk
        other = self.make_customer('stranger@example.com')
        self.auth(other)
        self.assertIn(self.client.get(reverse('ride-booking-detail', args=[booking_id])).status_code, [403, 404])
        self.assertEqual(self.client.get(reverse('ride-bookings')).data['count'], 0)
        self.assertEqual(self.client.post(reverse('ride-notification-read', args=[notification_id])).status_code, 404)
        self.assertEqual(self.client.get(reverse('ride-admin-overview')).status_code, 403)

    def test_suspension_forces_offline_and_false_is_not_truthy(self):
        from accounts.progress import apply_review_decision
        driver = self.make_driver()
        self.auth(driver)
        response = self.client.post(reverse('ride-availability'), {'available': 'false'}, format='json')
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.data['is_available'])
        self.assertEqual(self.client.post(reverse('ride-availability'), {'available': 'nonsense'}, format='json').status_code, 400)
        self.client.post(reverse('ride-availability'), {'available': True}, format='json')
        profile = DriverProfile.objects.get(user=driver)
        apply_review_decision(profile, action='suspend', reason='Test review')
        profile.refresh_from_db()
        self.assertFalse(profile.is_available)
        self.assertIsNone(profile.available_since)
        self.assertEqual(self.client.get(reverse('ride-requests')).status_code, 403)

    def test_anonymous_and_unverified_accounts_are_blocked(self):
        self.assertEqual(self.client.get(reverse('ride-bookings')).status_code, 401)
        customer = self.make_customer()
        customer.email_verified = False
        customer.save(update_fields=['email_verified'])
        self.auth(customer)
        self.assertEqual(self.client.get(reverse('ride-bookings')).status_code, 403)

    def test_transmission_and_service_capabilities_are_matched(self):
        customer = self.make_customer()
        self.add_vehicle(customer)
        self.create_booking(customer)
        driver = self.make_driver()
        profile = DriverProfile.objects.get(user=driver)
        profile.manual_transmission = False
        profile.save()
        self.auth(driver)
        self.assertEqual(self.client.get(reverse('ride-requests')).data['count'], 0)

    def test_scheduled_time_is_timezone_aware(self):
        from django.utils import timezone
        from datetime import timedelta
        customer = self.make_customer()
        self.add_vehicle(customer)
        later = timezone.now() + timedelta(hours=3)
        created = self.create_booking(customer, scheduled_at=later.isoformat())
        self.assertEqual(created.status_code, 201)
        self.assertTrue(timezone.is_aware(Booking.objects.get(pk=created.data['id']).scheduled_at))

    def test_database_also_guards_one_active_customer_booking(self):
        from django.db import IntegrityError, transaction
        customer = self.make_customer()
        self.add_vehicle(customer)
        self.create_booking(customer)
        with self.assertRaises(IntegrityError), transaction.atomic():
            Booking.objects.create(customer=customer, vehicle=Vehicle.objects.first(), pickup='Same street')

    def test_expired_licence_blocks_new_work_even_if_status_is_approved(self):
        from datetime import timedelta
        from django.utils import timezone
        driver = self.make_driver()
        profile = DriverProfile.objects.get(user=driver)
        profile.licence_expiry = timezone.localdate()-timedelta(days=1)
        profile.save()
        self.auth(driver)
        self.assertEqual(self.client.get(reverse('ride-requests')).status_code, 403)
        self.assertEqual(self.client.post(reverse('ride-availability'), {'available': True}, format='json').status_code, 403)
        self.assertFalse(self.client.get(reverse('ride-availability')).data['is_available'])
        self.assertFalse(self.client.get(reverse('ride-summary')).data['available'])


class ConcurrentAcceptTests(TransactionTestCase):
    """Two independent connections race for one request (including SQLite)."""
    def test_two_drivers_never_get_the_same_booking(self):
        from concurrent.futures import ThreadPoolExecutor
        from threading import Barrier
        from django.db import close_old_connections
        from rest_framework.test import APIClient

        customer = User.objects.create_user('race-rider@example.com', 'Race rider', PASSWORD,
                                            role=User.Role.CUSTOMER, email_verified=True)
        car = Vehicle.objects.create(owner=customer, make='Maruti', model='Dzire', registration='HR26AB1234')
        booking = Booking.objects.create(customer=customer, vehicle=car, pickup='Sector 15 metro gate')
        drivers = []
        for index in range(2):
            user = User.objects.create_user(f'race-driver{index}@example.com', f'Race driver {index}', PASSWORD,
                                           role=User.Role.DRIVER, email_verified=True)
            DriverProfile.objects.create(user=user, verification_status=DriverProfile.Status.APPROVED,
                                         is_available=True, manual_transmission=True)
            drivers.append(user)
        barrier = Barrier(2)

        def accept(user):
            close_old_connections()
            client = APIClient()
            client.force_authenticate(user=user)
            barrier.wait(timeout=10)
            try:
                return client.post(reverse('ride-request-accept', args=[booking.pk])).status_code
            finally:
                close_old_connections()

        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(accept, drivers))
        self.assertLessEqual(results.count(200), 1, results)
        self.assertTrue(all(code in [200, 404, 409] for code in results), results)
        # SQLite can reject both upgrades under contention; a retry must be safe.
        booking.refresh_from_db()
        if booking.status == Booking.Status.REQUESTED:
            client = APIClient()
            client.force_authenticate(user=drivers[0])
            self.assertEqual(client.post(reverse('ride-request-accept', args=[booking.pk])).status_code, 200)
            booking.refresh_from_db()
        self.assertIn(booking.driver_id, [d.pk for d in drivers])
        self.assertEqual(booking.events.filter(kind='ACCEPTED').count(), 1)
