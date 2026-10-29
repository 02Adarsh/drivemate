"""Create DEVELOPMENT ONLY demo accounts so the mobile app can be tested.

    python manage.py seed_demo_data          # create demo accounts (idempotent)
    python manage.py seed_demo_data --reset  # delete them first, then re-create

These accounts are clearly labelled sample data: the "documents" are placeholder
images, not real licences. Never run this against a production database.
"""

import base64
from datetime import date, timedelta

from django.conf import settings
from django.core.files.base import ContentFile
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from accounts.models import (
    CustomerProfile,
    DriverDocument,
    DriverProfile,
    DriverTraining,
    EmailOTP,
    User,
)
from accounts.progress import apply_review_decision, ensure_training_rows, sync_driver_status

PASSWORD = 'Demo@12345'

# 1x1 transparent PNG used as a clearly-fake placeholder file.
PLACEHOLDER_PNG = base64.b64decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
)

DEMO_USERS = {
    'customer': 'rider@demo.drivemate.local',
    'driver_approved': 'driver@demo.drivemate.local',
    'driver_pending': 'driver.pending@demo.drivemate.local',
    'driver_new': 'driver.new@demo.drivemate.local',
}


def fake_file(key: str, label: str) -> str:
    """Save a placeholder file and return its private storage key."""
    from django.core.files.storage import default_storage

    return default_storage.save(key, ContentFile(PLACEHOLDER_PNG, name=label))


class Command(BaseCommand):
    help = 'Create DEMO ONLY customer and driver accounts for testing the app.'

    def add_arguments(self, parser):
        parser.add_argument('--with-rides', action='store_true', help='Also create clearly labelled demo bookings and set the demo driver online.')
        parser.add_argument('--reset', action='store_true', help='Delete existing demo accounts before seeding.')

    @transaction.atomic
    def handle(self, *args, **options):
        if not settings.DEBUG:
            self.stderr.write(self.style.ERROR('Refusing to run: this command is for DEBUG/development only.'))
            return

        if options['reset']:
            deleted, _ = User.objects.filter(email__in=DEMO_USERS.values()).delete()
            self.stdout.write(self.style.WARNING(f'Deleted {deleted} existing demo rows.'))

        self._create_customer()
        self._create_driver_approved()
        self._create_driver_pending()
        self._create_driver_new()
        if options['with_rides']:
            self._create_demo_rides()

        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS('DEMO DATA created. All accounts use this password: ' + PASSWORD))
        self.stdout.write('---------------------------------------------------------------------')
        self.stdout.write(f"Customer (profile complete) : {DEMO_USERS['customer']}")
        self.stdout.write(f"Driver  (APPROVED)          : {DEMO_USERS['driver_approved']}")
        self.stdout.write(f"Driver  (PENDING_REVIEW)    : {DEMO_USERS['driver_pending']}")
        self.stdout.write(f"Driver  (INCOMPLETE, new)   : {DEMO_USERS['driver_new']}")
        self.stdout.write('---------------------------------------------------------------------')
        self.stdout.write('These are development accounts. The uploaded "documents" are placeholder images.')
        self.stdout.write('To review the pending driver open: http://127.0.0.1:8000/admin/accounts/driverprofile/')

    # ------------------------------------------------------------------ helpers

    def _base_user(self, email: str, name: str, phone: str) -> User:
        user = User.objects.filter(email=email).first()
        if user:
            return user
        user = User(email=email, full_name=name, phone=phone, role=User.Role.CUSTOMER, email_verified=True)
        user.set_password(PASSWORD)
        user.save()
        return user

    def _attach_photo(self, user: User) -> None:
        if not user.profile_photo_key:
            user.profile_photo_key = fake_file(
                f'private/profile/{user.id}/demo-placeholder.png', 'demo-photo.png'
            )
            user.save(update_fields=['profile_photo_key'])

    def _attach_documents(self, profile: DriverProfile) -> None:
        for document_type in ('LICENCE_FRONT', 'LICENCE_BACK', 'IDENTITY'):
            if profile.documents.filter(document_type=document_type).exists():
                continue
            key = fake_file(
                f'private/driver-documents/{profile.user_id}/{document_type.lower()}-demo.png',
                f'{document_type.lower()}-demo.png',
            )
            DriverDocument.objects.create(
                driver=profile,
                document_type=document_type,
                private_storage_key=key,
                document_number='DEMO-0000-0000' if document_type.startswith('LICENCE') else '',
                expires_at=date.today() + timedelta(days=365) if document_type.startswith('LICENCE') else None,
            )

    def _complete_profile(self, profile: DriverProfile) -> None:
        profile.date_of_birth = date(1995, 5, 12)
        profile.address = '12 Demo Street, Phase 2'
        profile.state = 'Uttar Pradesh'
        profile.city = 'Lucknow'
        profile.pincode = '226001'
        profile.service_area = 'Lucknow city'
        profile.emergency_contact_name = 'Demo Contact'
        profile.emergency_contact_phone = '+919000000001'
        profile.languages = 'Hindi, English'
        profile.introduction = 'Development sample driver profile. Not a real person.'
        profile.licence_number = 'DEMO-DL-0001234'
        profile.licence_expiry = date.today() + timedelta(days=900)
        profile.experience_years = 6
        profile.manual_transmission = True
        profile.automatic_transmission = True
        profile.sedan = True
        profile.suv = True
        profile.luxury = False
        profile.highway = True
        profile.night_driving = True
        profile.outstation = False
        profile.consent_background_check = True
        profile.consent_terms = True
        profile.consent_data_accuracy = True
        profile.consents_accepted_at = timezone.now()
        profile.save()

    def _complete_training(self, profile: DriverProfile) -> None:
        ensure_training_rows(profile)
        profile.training.filter(module__in=('SAFE_DRIVING', 'CUSTOMER_SERVICE', 'VEHICLE_INSPECTION')).update(
            status=DriverTraining.Status.COMPLETED, completed_at=timezone.now()
        )

    # ------------------------------------------------------------------ seeds

    def _create_customer(self) -> None:
        user = self._base_user(DEMO_USERS['customer'], 'Demo Rider', '+919000000010')
        self._attach_photo(user)
        profile, _ = CustomerProfile.objects.get_or_create(user=user)
        profile.address = '44 Demo Road'
        profile.state = 'Uttar Pradesh'
        profile.city = 'Lucknow'
        profile.pincode = '226001'
        profile.emergency_contact_name = 'Demo Family'
        profile.emergency_contact_phone = '+919000000011'
        profile.profile_complete = True
        profile.save()

    def _create_driver_approved(self) -> None:
        user = self._base_user(DEMO_USERS['driver_approved'], 'Demo Driver (Approved)', '+919000000020')
        user.role = User.Role.DRIVER
        user.save(update_fields=['role'])
        self._attach_photo(user)
        profile, _ = DriverProfile.objects.get_or_create(user=user)
        self._complete_profile(profile)
        self._attach_documents(profile)
        self._complete_training(profile)
        sync_driver_status(profile)
        if profile.verification_status != DriverProfile.Status.APPROVED:
            apply_review_decision(profile, action='approve', reason='Development demo data.')

    def _create_driver_pending(self) -> None:
        user = self._base_user(DEMO_USERS['driver_pending'], 'Demo Driver (Pending review)', '+919000000021')
        user.role = User.Role.DRIVER
        user.save(update_fields=['role'])
        self._attach_photo(user)
        profile, _ = DriverProfile.objects.get_or_create(user=user)
        self._complete_profile(profile)
        self._attach_documents(profile)
        self._complete_training(profile)
        sync_driver_status(profile)
        if profile.verification_status == DriverProfile.Status.APPROVED:
            # Keep one application inside the review queue for the admin demo.
            apply_review_decision(profile, action='pending_review', reason='')
            profile.approved_at = None
            profile.save(update_fields=['approved_at'])

    def _create_driver_new(self) -> None:
        user = self._base_user(DEMO_USERS['driver_new'], 'New Driver (Incomplete)', '+919000000022')
        user.role = User.Role.DRIVER
        user.save(update_fields=['role'])
        profile, _ = DriverProfile.objects.get_or_create(user=user)
        ensure_training_rows(profile)
        sync_driver_status(profile)

    # ------------------------------------------------------------ v7: rides

    def _create_demo_rides(self) -> None:
        """One car in the rider's garage, one open request and one finished trip.

        With this data the driver "Requests" feed, the customer "Activity" tab
        and the earnings summary all have something real to show straight after
        `seed_demo_data`.
        """
        from rides.models import Booking, Vehicle, notify_available_drivers
        from rides.pricing import driver_payout, estimate_fare

        rider = User.objects.filter(email=DEMO_USERS['customer']).first()
        approved = User.objects.filter(email=DEMO_USERS['driver_approved']).first()
        if rider is None or approved is None:
            return

        vehicle, _ = Vehicle.objects.get_or_create(
            owner=rider,
            registration='HR26AB1234',
            defaults={
                'make': 'Maruti Suzuki',
                'model': 'Dzire',
                'fuel': Vehicle.Fuel.PETROL,
                'transmission': Vehicle.Transmission.MANUAL,
                'seats': 5,
                'is_default': True,
            },
        )

        # The approved driver is online so the request feed has a candidate.
        driver_profile = DriverProfile.objects.filter(user=approved).first()
        if driver_profile is not None and not driver_profile.is_available:
            driver_profile.is_available = True
            driver_profile.available_since = timezone.now()
            driver_profile.save(update_fields=['is_available', 'available_since', 'updated_at'])

        if not Booking.objects.filter(customer=rider).exists():
            open_booking = Booking(
                customer=rider,
                vehicle=vehicle,
                service=Booking.Service.HOURLY,
                duration_hours=4,
                pickup = 'Sector 15, near the metro station gate',
                notes='DEMO request - no real journey or payment.',
            )
            from rides.views import vehicle_payload
            open_booking.vehicle_snapshot = vehicle_payload(vehicle)
            open_booking.set_estimate()
            open_booking.save()
            open_booking.add_event('CREATED', f'₹{open_booking.estimated_fare} estimate', rider)
            notify_available_drivers(open_booking)

            finished = Booking(
                customer=rider,
                vehicle=vehicle,
                driver=approved,
                service=Booking.Service.AIRPORT,
                duration_hours=2,
                pickup='IGI Airport Terminal 3',
                drop_address='Sector 45, Gurugram',
                status=Booking.Status.COMPLETED,
                estimated_fare=estimate_fare('AIRPORT', 2),
                final_fare=estimate_fare('AIRPORT', 2),
            )
            finished.vehicle_snapshot = vehicle_payload(vehicle)
            finished.save()
            finished.add_event('CREATED', 'Demo history', rider)
            finished.add_event('ACCEPTED', f'{approved.full_name} accepted', approved)
            finished.add_event('STARTED', 'Trip started', approved)
            finished.add_event('COMPLETED', f'₹{finished.final_fare} fare', approved)
            finished.completed_at = timezone.now() - timedelta(days=1)
            finished.accepted_at = finished.completed_at - timedelta(hours=3)
            finished.started_at = finished.completed_at - timedelta(hours=2)
            finished.save(update_fields=['completed_at', 'accepted_at', 'started_at'])
            Booking.objects.filter(pk=finished.pk).update(created_at=finished.accepted_at-timedelta(minutes=20))
            event_times = {
                'CREATED': finished.accepted_at-timedelta(minutes=20), 'ACCEPTED': finished.accepted_at,
                'STARTED': finished.started_at, 'COMPLETED': finished.completed_at,
            }
            for kind, at in event_times.items():
                finished.events.filter(kind=kind).update(created_at=at)
            self.stdout.write(
                f'  DEMO ride  : 1 open request (₹{open_booking.estimated_fare}) + 1 completed trip '
                f'(payout ₹{driver_payout(finished.final_fare)})'
            )
