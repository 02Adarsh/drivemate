"""Rides app — vehicles, bookings, the booking timeline and notifications.

Design rules:
* A customer owns the car; a driver drives it. So a `Booking` always points at a
  `Vehicle` that belongs to the customer.
* Money is stored as `Decimal` and calculated **on the server** in `pricing.py`.
  The app never sends a price, it only renders what the server returns.
* Every state change writes a `BookingEvent`, so the timeline the customer and
  the driver see is the real history, not a UI guess.
* Drivers have an explicit availability flag (`DriverProfile.is_available`)
  separate from approval (`verification_status`). Only an approved AND available
  driver can accept a request.
"""

from decimal import Decimal

from django.conf import settings
from django.db import models, transaction
from django.db.models import Q
from django.utils import timezone

from .pricing import PLATFORM_FEE_PERCENT, SERVICE_PRICING, driver_payout, estimate_fare


def normalise_registration(value: str) -> str:
    """`hr 26 ab 1234` -> `HR26AB1234` (the canonical form we compare with)."""
    return ''.join(str(value).split()).upper()


class ServiceRate(models.Model):
    """Staff-managed whole-rupee prices; existing booking estimates stay unchanged."""
    service = models.CharField(max_length=12, unique=True, choices=[
        (key, row['label']) for key, row in SERVICE_PRICING.items()
    ])
    base = models.PositiveIntegerField(help_text='Base fare in rupees')
    per_hour = models.PositiveIntegerField(help_text='Rate per billable hour in rupees')
    updated_at = models.DateTimeField(auto_now=True)
    enabled = models.BooleanField(default=True, help_text='Disable to prevent new bookings for this service.')

    class Meta:
        constraints = [
            models.CheckConstraint(condition=Q(base__lte=1000000), name='rate_base_max'),
            models.CheckConstraint(condition=Q(per_hour__lte=100000), name='rate_hour_max'),
        ]
        verbose_name = 'Ride rate'
        verbose_name_plural = 'Ride rates'

    def __str__(self):
        return self.get_service_display()


class Vehicle(models.Model):
    """A car a customer owns. One customer can keep several."""

    class Fuel(models.TextChoices):
        PETROL = 'PETROL', 'Petrol'
        DIESEL = 'DIESEL', 'Diesel'
        CNG = 'CNG', 'CNG'
        ELECTRIC = 'ELECTRIC', 'Electric'
        HYBRID = 'HYBRID', 'Hybrid'

    class Transmission(models.TextChoices):
        MANUAL = 'MANUAL', 'Manual'
        AUTOMATIC = 'AUTOMATIC', 'Automatic'

    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='vehicles')
    make = models.CharField(max_length=60)
    model = models.CharField(max_length=60)
    registration = models.CharField(max_length=16)
    fuel = models.CharField(max_length=10, choices=Fuel.choices, default=Fuel.PETROL)
    transmission = models.CharField(max_length=10, choices=Transmission.choices, default=Transmission.MANUAL)
    seats = models.PositiveSmallIntegerField(default=5)
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-is_default', '-created_at']
        constraints = [
            models.UniqueConstraint(fields=['owner', 'registration'], name='vehicle_unique_per_owner'),
            models.UniqueConstraint(fields=['owner'], condition=Q(is_default=True), name='vehicle_one_default'),
        ]

    def __str__(self):
        return f'{self.make} {self.model} ({self.registration})'

    @property
    def display_name(self) -> str:
        return f'{self.make} {self.model}'.strip()

    def save(self, *args, **kwargs):
        from accounts.models import User
        self.registration = normalise_registration(self.registration)
        with transaction.atomic():
            User.objects.select_for_update().get(pk=self.owner_id)
            others = Vehicle.objects.filter(owner_id=self.owner_id).exclude(pk=self.pk)
            if not others.exists():
                self.is_default = True
            if self.is_default:
                others.update(is_default=False)
            super().save(*args, **kwargs)
            if not self.is_default and not others.filter(is_default=True).exists():
                first = others.order_by('id').first()
                if first:
                    Vehicle.objects.filter(pk=first.pk).update(is_default=True)



class Booking(models.Model):
    """One driver request. The car always belongs to the customer."""

    class Status(models.TextChoices):
        REQUESTED = 'REQUESTED', 'Searching for a driver'
        ACCEPTED = 'ACCEPTED', 'Driver assigned'
        ONGOING = 'ONGOING', 'Trip in progress'
        COMPLETED = 'COMPLETED', 'Completed'
        CANCELLED = 'CANCELLED', 'Cancelled'
        EXPIRED = 'EXPIRED', 'No driver found'

    class Service(models.TextChoices):
        BOOK_NOW = 'BOOK_NOW', 'Book now'
        HOURLY = 'HOURLY', 'Hourly'
        FULL_DAY = 'FULL_DAY', 'Full day'
        AIRPORT = 'AIRPORT', 'Airport'
        OUTSTATION = 'OUTSTATION', 'Outstation'
        GETAWAY = 'GETAWAY', 'Outstation Getaways'
        EVENT = 'EVENT', 'Wedding / Event Driver'
        CORPORATE = 'CORPORATE', 'Corporate / Business Driver'
        NIGHT = 'NIGHT', 'Night drive'

    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='bookings'
    )
    driver = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='driver_bookings',
    )
    vehicle = models.ForeignKey(Vehicle, on_delete=models.SET_NULL, null=True, related_name='bookings')

    # Immutable car details for history even if the car is edited or removed.
    vehicle_snapshot = models.JSONField(default=dict, blank=True)
    # A retry must return the same request instead of creating it twice.
    request_key = models.CharField(max_length=64, blank=True)

    service = models.CharField(max_length=12, choices=Service.choices, default=Service.BOOK_NOW)
    scheduled_at = models.DateTimeField(null=True, blank=True, help_text='Empty = as soon as possible.')
    return_at = models.DateTimeField(null=True, blank=True, help_text='Planned return for a multi-day getaway.')
    duration_hours = models.PositiveSmallIntegerField(default=4)
    pickup = models.CharField(max_length=240)
    drop_address = models.CharField(max_length=240, blank=True)
    notes = models.CharField(max_length=500, blank=True)
    pickup_latitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    pickup_longitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    drop_latitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    drop_longitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    passenger_name = models.CharField(max_length=120, blank=True)
    passenger_phone = models.CharField(max_length=20, blank=True)
    business_label = models.CharField(max_length=120, blank=True)
    promo_code = models.CharField(max_length=32, blank=True)
    discount_amount = models.DecimalField(max_digits=9, decimal_places=2, default=Decimal('0'))
    driver_latitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    driver_longitude = models.DecimalField(max_digits=10, decimal_places=7, null=True, blank=True)
    location_updated_at = models.DateTimeField(null=True, blank=True)
    otp_verified_at = models.DateTimeField(null=True, blank=True)
    cash_received_at = models.DateTimeField(null=True, blank=True)


    estimated_fare = models.DecimalField(max_digits=9, decimal_places=2, default=Decimal('0'))
    final_fare = models.DecimalField(max_digits=9, decimal_places=2, null=True, blank=True)
    platform_fee_percent = models.PositiveSmallIntegerField(default=PLATFORM_FEE_PERCENT)

    status = models.CharField(max_length=12, choices=Status.choices, default=Status.REQUESTED)
    cancel_reason = models.CharField(max_length=240, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [
            models.UniqueConstraint(
                fields=['customer'], condition=Q(status__in=['REQUESTED', 'ACCEPTED', 'ONGOING']),
                name='booking_one_live_customer',
            ),
            models.UniqueConstraint(
                fields=['driver'], condition=Q(status__in=['ACCEPTED', 'ONGOING'], driver__isnull=False),
                name='booking_one_live_driver',
            ),
            models.UniqueConstraint(
                fields=['customer', 'request_key'], condition=~Q(request_key=''),
                name='booking_unique_request_key',
            ),
        ]
        indexes = [
            models.Index(fields=['status', '-created_at'], name='booking_status_idx'),
            models.Index(fields=['customer', '-created_at'], name='booking_customer_idx'),
            models.Index(fields=['driver', '-created_at'], name='booking_driver_idx'),
        ]

    def __str__(self):
        return f'#{self.pk} {self.get_service_display()} · {self.status}'

    # -------------------------------------------------------------- helpers

    @property
    def is_open(self) -> bool:
        return self.status == self.Status.REQUESTED

    @property
    def is_active(self) -> bool:
        return self.status in (self.Status.ACCEPTED, self.Status.ONGOING)

    @property
    def is_finished(self) -> bool:
        return self.status in (self.Status.COMPLETED, self.Status.CANCELLED, self.Status.EXPIRED)

    @property
    def payout(self) -> Decimal:
        """What the driver receives if the trip is completed."""
        amount = self.final_fare if self.final_fare is not None else self.estimated_fare
        return driver_payout(amount, self.platform_fee_percent)

    def set_estimate(self) -> Decimal:
        self.estimated_fare = estimate_fare(self.service, self.duration_hours)
        return self.estimated_fare

    def add_event(self, kind: str, note: str = '', user=None) -> 'BookingEvent':
        return BookingEvent.objects.create(booking=self, kind=kind, note=note, created_by=user)


class BookingEvent(models.Model):
    """Append-only timeline: the history both sides see."""

    class Kind(models.TextChoices):
        CREATED = 'CREATED', 'Request created'
        ACCEPTED = 'ACCEPTED', 'Driver accepted'
        DECLINED = 'DECLINED', 'Driver declined'
        STARTED = 'STARTED', 'Trip started'
        COMPLETED = 'COMPLETED', 'Trip completed'
        CANCELLED = 'CANCELLED', 'Cancelled'
        NOTE = 'NOTE', 'Note'

    booking = models.ForeignKey(Booking, on_delete=models.CASCADE, related_name='events')
    kind = models.CharField(max_length=12, choices=Kind.choices)
    note = models.CharField(max_length=240, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='booking_events'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f'#{self.booking_id} {self.kind}'


class BookingDecline(models.Model):
    """A driver passed on a request - the feed hides it from them afterwards."""

    booking = models.ForeignKey(Booking, on_delete=models.CASCADE, related_name='declines')
    driver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='booking_declines')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['booking', 'driver'], name='booking_decline_unique'),
        ]


class Notification(models.Model):
    """In-app notification. Email/SMS delivery is a later phase."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='notifications')
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=400, blank=True)
    kind = models.CharField(max_length=24, default='GENERAL')
    booking = models.ForeignKey(Booking, on_delete=models.CASCADE, null=True, blank=True, related_name='notifications')
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['user', '-created_at'], name='notification_user_idx')]

    @property
    def is_read(self) -> bool:
        return self.read_at is not None

    def mark_read(self):
        if self.read_at is None:
            self.read_at = timezone.now()
            self.save(update_fields=['read_at'])


def notify(user, title: str, body: str = '', kind: str = 'GENERAL', booking: Booking | None = None) -> Notification:
    """Small helper so views never forget to notify."""
    from hub.models import Preferences
    preference = Preferences.objects.filter(user=user).first()
    if kind not in ['SECURITY','SUPPORT'] and preference and not preference.trip_updates:
        return None
    return Notification.objects.create(user=user, title=title, body=body, kind=kind, booking=booking)


def notify_available_drivers(booking: Booking, limit: int = 50) -> int:
    """Beta dispatch: approved, online, non-busy drivers with the right skills.

    No GPS/radius matching is claimed. Request feed queries the same eligibility
    rules, and is the source of truth if this bounded notification fanout misses
    a driver. Contact details are only shared after assignment.
    """
    from accounts.models import DriverProfile, User
    busy = Booking.objects.filter(status__in=['ACCEPTED', 'ONGOING']).values_list('driver_id', flat=True)
    profiles = DriverProfile.objects.select_related('user').filter(
        verification_status=DriverProfile.Status.APPROVED, is_available=True,
        user__role=User.Role.DRIVER, user__is_active=True, user__email_verified=True,
    ).exclude(user__preferences__trip_updates=False).exclude(user_id__in=busy).exclude(user_id=booking.customer_id).exclude(licence_expiry__lt=timezone.localdate())
    if booking.vehicle:
        capability = 'automatic_transmission' if booking.vehicle.transmission == 'AUTOMATIC' else 'manual_transmission'
        profiles = profiles.filter(**{capability: True})
    if booking.service == Booking.Service.NIGHT:
        profiles = profiles.filter(night_driving=True)
    if booking.service in (Booking.Service.OUTSTATION, Booking.Service.GETAWAY):
        profiles = profiles.filter(outstation=True)
    rows = [Notification(
        user_id=profile.user_id, title='New booking request',
        body=f'{booking.get_service_display()} · {booking.duration_hours} hours · ₹{booking.estimated_fare}',
        kind='BOOKING_REQUEST', booking=booking,
    ) for profile in profiles.order_by('id')[:limit]]
    Notification.objects.bulk_create(rows)
    return len(rows)


class TripStartCode(models.Model):
    booking = models.OneToOneField(Booking, on_delete=models.CASCADE, related_name='start_code')
    code_hash = models.CharField(max_length=128)
    code_ciphertext = models.TextField()
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    locked_until = models.DateTimeField(null=True, blank=True)
    consumed_at = models.DateTimeField(null=True, blank=True)
    email_sent = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)


class TripRating(models.Model):
    booking = models.ForeignKey(Booking, on_delete=models.CASCADE, related_name='ratings')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    score = models.PositiveSmallIntegerField()
    comment = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['booking', 'author'], name='one_rating_per_trip_author')]
