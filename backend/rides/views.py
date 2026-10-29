"""Booking beta: authenticated, role-scoped endpoints and atomic transitions.

This is a request board, not GPS dispatch. Eligible online drivers explicitly
accept requests. Fares/earnings are a ledger only; this API never charges money.
"""
from datetime import timedelta
from decimal import Decimal

from django.db import IntegrityError, OperationalError, transaction
from django.db.models import Count, DecimalField, ExpressionWrapper, F, Sum, Value
from django.db.models.functions import Round, TruncDate
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.permissions import BasePermission, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.throttling import ScopedRateThrottle

from accounts.models import DriverProfile, User
from .models import Booking, BookingDecline, Notification, Vehicle, ServiceRate, notify, notify_available_drivers
from .models import TripStartCode, TripRating
from .trip_security import issue_start_code, check_start_code, email_start_code
from .pricing import PLATFORM_FEE_PERCENT, REQUIRES_EXPLICIT_RATE, SERVICE_PRICING, fare_breakdown, platform_fee
from .serializers import (
    AvailabilityInputSerializer, BookingInputSerializer, CancelInputSerializer, VehicleInputSerializer,
)

LIVE = [Booking.Status.REQUESTED, Booking.Status.ACCEPTED, Booking.Status.ONGOING]
ASSIGNED = [Booking.Status.ACCEPTED, Booking.Status.ONGOING]


class VerifiedAccount(BasePermission):
    message = 'Verify your email before using bookings.'

    def has_permission(self, request, view):
        return bool(request.user.is_authenticated and request.user.email_verified)


class RidesView(APIView):
    permission_classes = [IsAuthenticated, VerifiedAccount]


def require_role(user, role):
    if user.role != role:
        raise PermissionDenied(f'Only {role.lower()} accounts can do this.')
    if role == User.Role.ADMIN and not user.is_staff:
        raise PermissionDenied('Staff access is required.')


def approved_profile(user, *, lock=False):
    require_role(user, User.Role.DRIVER)
    qs = DriverProfile.objects.select_for_update() if lock else DriverProfile.objects
    profile = qs.filter(user=user).first()
    if profile is None or not profile.is_approved:
        raise PermissionDenied('Your driver application must be approved before taking requests.')
    if profile.licence_expiry and profile.licence_expiry < timezone.localdate():
        raise PermissionDenied('Your licence has expired. Update it before taking more work.')
    return profile


def eligible_requests(profile):
    """All beta requests the driver is skilled to drive; no distance filtering."""
    qs = Booking.objects.filter(status=Booking.Status.REQUESTED).exclude(customer_id=profile.user_id)
    qs = qs.exclude(declines__driver_id=profile.user_id)
    if not profile.manual_transmission:
        qs = qs.exclude(vehicle__transmission=Vehicle.Transmission.MANUAL)
    if not profile.automatic_transmission:
        qs = qs.exclude(vehicle__transmission=Vehicle.Transmission.AUTOMATIC)
    if not profile.night_driving:
        qs = qs.exclude(service=Booking.Service.NIGHT)
    if not profile.outstation:
        qs = qs.exclude(service__in=[Booking.Service.OUTSTATION, Booking.Service.GETAWAY, Booking.Service.PILGRIMAGE])
    return qs.select_related('customer', 'driver', 'vehicle').prefetch_related('events')


def vehicle_payload(vehicle):
    return {
        'id': vehicle.pk, 'make': vehicle.make, 'model': vehicle.model,
        'display_name': vehicle.display_name, 'registration': vehicle.registration,
        'fuel': vehicle.fuel, 'fuel_label': vehicle.get_fuel_display(),
        'transmission': vehicle.transmission, 'transmission_label': vehicle.get_transmission_display(),
        'seats': vehicle.seats, 'is_default': vehicle.is_default,
    }


def person_payload(user, *, contact=False):
    if user is None:
        return None
    return {'id': user.pk, 'name': user.full_name, 'phone': user.phone if contact else '', 'email': '', 'has_profile_photo': bool(user.profile_photo_key)}


def booking_payload(booking, *, viewer=None, offer=False):
    viewer = viewer or booking.customer
    staff = viewer.role == User.Role.ADMIN and viewer.is_staff
    customer_view = booking.customer_id == viewer.pk
    driver_view = booking.driver_id == viewer.pk and viewer.role == User.Role.DRIVER
    contact = staff or (booking.driver_id is not None and (customer_view or driver_view))
    vehicle = dict(booking.vehicle_snapshot or (vehicle_payload(booking.vehicle) if booking.vehicle else {}))
    if not customer_view and not driver_view and not staff:
        vehicle['registration'] = ''  # No number plates / contact details in the open request board.
    events = [e for e in booking.events.all() if e.kind != 'DECLINED']
    start_eligible = driver_view and DriverProfile.objects.filter(
        user_id=viewer.pk, verification_status=DriverProfile.Status.APPROVED,
    ).exclude(licence_expiry__lt=timezone.localdate()).exists() if booking.status == Booking.Status.ACCEPTED else False
    payout = booking.payout if booking.status != Booking.Status.CANCELLED else Decimal('0')
    own_rating = booking.ratings.filter(author=viewer).first()
    from payments.state import payment_state
    payment = payment_state(booking)
    upi_block = payment.get('upi_payment') and payment['upi_payment']['status'] != 'CANCELLED'
    return {
        'id': booking.pk, 'status': booking.status, 'status_label': booking.get_status_display(),
        'service': booking.service, 'service_label': booking.get_service_display(),
        'scheduled_at': booking.scheduled_at, 'return_at': booking.return_at, 'duration_hours': booking.duration_hours,
        'pickup': booking.pickup, 'drop_address': booking.drop_address, 'notes': booking.notes,
        'pickup_latitude':float(booking.pickup_latitude) if booking.pickup_latitude is not None else None,
        'pickup_longitude':float(booking.pickup_longitude) if booking.pickup_longitude is not None else None,
        'drop_latitude':float(booking.drop_latitude) if booking.drop_latitude is not None else None,
        'drop_longitude':float(booking.drop_longitude) if booking.drop_longitude is not None else None,
        'passenger_name':booking.passenger_name,
        'passenger_phone':booking.passenger_phone if contact else '',
        'business_label':booking.business_label, 'promo_code':booking.promo_code,
        'discount_amount':str(booking.discount_amount),
        'otp_required':booking.status=='ACCEPTED', 'otp_verified_at':booking.otp_verified_at,
        'payment_method':'CASH', 'cash_received_at':booking.cash_received_at,
        'payment_status':'RECEIVED' if booking.cash_received_at else 'DUE',
        'can_confirm_cash':driver_view and booking.status=='COMPLETED' and not payment['payment_received'] and not upi_block,
        'can_pay_upi':(customer_view or driver_view) and booking.status=='COMPLETED' and not payment['payment_received'] and not (payment.get('upi_payment') and payment['upi_payment']['status']=='CANCELLED'),
        'can_view_upi':customer_view or driver_view,
        'can_rate':(customer_view or driver_view) and booking.status=='COMPLETED',
        'my_rating':{'score':own_rating.score,'comment':own_rating.comment} if own_rating else None,
        'driver_location':{'latitude':float(booking.driver_latitude),'longitude':float(booking.driver_longitude),'updated_at':booking.location_updated_at}
            if (customer_view or driver_view or staff) and booking.status in ASSIGNED and booking.driver_latitude is not None and booking.driver_longitude is not None else None,

        'estimated_fare': str(booking.estimated_fare),
        'final_fare': str(booking.final_fare) if booking.final_fare is not None else None,
        'platform_fee_percent': booking.platform_fee_percent, 'driver_payout': str(payout),
        'vehicle': vehicle or None,
        'customer': person_payload(booking.customer, contact=contact),
        'driver': person_payload(booking.driver, contact=contact),
        'created_at': booking.created_at, 'accepted_at': booking.accepted_at,
        'started_at': booking.started_at, 'completed_at': booking.completed_at,
        'cancelled_at': booking.cancelled_at, 'cancel_reason': booking.cancel_reason,
        'is_open': booking.is_open, 'is_active': booking.is_active,
        'is_demo': booking.customer.email.endswith('@demo.drivemate.local'),
        'can_cancel': booking.status in [Booking.Status.REQUESTED, Booking.Status.ACCEPTED]
                      and (customer_view or driver_view or staff),
        'can_accept': offer,
        'can_start': bool(start_eligible),
        'can_complete': booking.status == Booking.Status.ONGOING and driver_view,
        **payment,
        'events': [{'kind': e.kind, 'label': e.get_kind_display(), 'note': e.note, 'at': e.created_at}
                   for e in events],
    }


def loaded_bookings():
    return Booking.objects.select_related('customer', 'driver', 'vehicle').prefetch_related('events')


def owned_booking(user, booking_id, *, lock=False):
    qs = loaded_bookings()
    if lock:
        qs = Booking.objects.select_for_update()
    booking = qs.filter(pk=booking_id).first()
    if booking is None:
        raise NotFound('Booking not found.')
    if booking.customer_id == user.pk or booking.driver_id == user.pk:
        return booking
    if user.role == User.Role.ADMIN and user.is_staff:
        return booking
    raise NotFound('Booking not found.')


def notification_payload(item):
    return {'id': item.pk, 'title': item.title, 'body': item.body, 'kind': item.kind,
            'booking_id': item.booking_id, 'is_read': item.is_read, 'created_at': item.created_at}


class PricingView(RidesView):
    def get(self, request):
        rates = {rate.service: rate.enabled for rate in ServiceRate.objects.all()}
        return Response({
            'services': [{**fare_breakdown(key, row['min_hours']), 'key': key}
                         for key, row in SERVICE_PRICING.items()
                         if rates.get(key, key not in REQUIRES_EXPLICIT_RATE)],
            'platform_fee_percent': PLATFORM_FEE_PERCENT,
            'currency': 'INR', 'payment_collection_live': False,
        })


class AvailabilityView(RidesView):
    def get(self, request):
        require_role(request.user, User.Role.DRIVER)
        profile = DriverProfile.objects.filter(user=request.user).first()
        approved = bool(profile and profile.is_approved)
        online = bool(approved and profile.is_available and (not profile.licence_expiry or profile.licence_expiry >= timezone.localdate()))
        return Response({'is_available': online, 'is_approved': approved,
                         'open_requests': eligible_requests(profile).count() if online else 0})

    def post(self, request):
        serializer = AvailabilityInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        wanted = serializer.validated_data['available']
        with transaction.atomic():
            require_role(request.user, User.Role.DRIVER)
            profile = DriverProfile.objects.select_for_update().filter(user=request.user).first()
            if profile is None:
                raise PermissionDenied('Driver profile not found.')
            # Going offline is always allowed. Going online requires approval.
            if wanted and not profile.is_approved:
                raise PermissionDenied('Approval is required to go online.')
            if wanted and profile.licence_expiry and profile.licence_expiry < timezone.localdate():
                raise PermissionDenied('Your licence has expired. Update it before going online.')
            profile.is_available = wanted
            profile.available_since = timezone.now() if wanted else None
            profile.save(update_fields=['is_available', 'available_since', 'updated_at'])
        return Response({'is_available': wanted,
                         'open_requests': eligible_requests(profile).count() if wanted else 0})


class VehicleListCreateView(RidesView):
    def get(self, request):
        require_role(request.user, User.Role.CUSTOMER)
        vehicles = Vehicle.objects.filter(owner=request.user)
        return Response({'count': vehicles.count(), 'results': [vehicle_payload(v) for v in vehicles]})

    def post(self, request):
        require_role(request.user, User.Role.CUSTOMER)
        serializer = VehicleInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            with transaction.atomic():
                User.objects.select_for_update().get(pk=request.user.pk)
                if Vehicle.objects.filter(owner=request.user, registration=data['registration']).exists():
                    raise ValidationError({'registration': 'That car is already in your garage.'})
                vehicle = Vehicle.objects.create(owner=request.user, **data)
        except IntegrityError:
            raise ValidationError({'registration': 'That car is already in your garage.'})
        return Response(vehicle_payload(vehicle), status=status.HTTP_201_CREATED)


class VehicleDetailView(RidesView):
    def _get(self, user, vehicle_id):
        require_role(user, User.Role.CUSTOMER)
        vehicle = Vehicle.objects.filter(pk=vehicle_id, owner=user).first()
        if vehicle is None:
            raise NotFound('Vehicle not found.')
        return vehicle

    def get(self, request, vehicle_id):
        return Response(vehicle_payload(self._get(request.user, vehicle_id)))

    def put(self, request, vehicle_id):
        vehicle = self._get(request.user, vehicle_id)
        serializer = VehicleInputSerializer(data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            with transaction.atomic():
                User.objects.select_for_update().get(pk=request.user.pk)
                if any(k != 'is_default' for k in data) and vehicle.bookings.filter(status__in=LIVE).exists():
                    raise ValidationError({'detail': 'This car is in a live booking. Only the default flag can change.'})
                if 'registration' in data and Vehicle.objects.filter(
                    owner=request.user, registration=data['registration'],
                ).exclude(pk=vehicle.pk).exists():
                    raise ValidationError({'registration': 'That car is already in your garage.'})
                for key, value in data.items():
                    setattr(vehicle, key, value)
                vehicle.save()
        except IntegrityError:
            raise ValidationError({'registration': 'That registration is already in your garage.'})
        return Response(vehicle_payload(vehicle))

    def delete(self, request, vehicle_id):
        with transaction.atomic():
            User.objects.select_for_update().get(pk=request.user.pk)
            vehicle = self._get(request.user, vehicle_id)
            if vehicle.bookings.filter(status__in=LIVE).exists():
                raise ValidationError({'detail': 'This car is in a live booking. Finish or cancel it first.'})
            was_default = vehicle.is_default
            vehicle.delete()
            if was_default:
                next_car = Vehicle.objects.filter(owner=request.user).first()
                if next_car:
                    Vehicle.objects.filter(pk=next_car.pk).update(is_default=True)
        return Response({'detail': 'Vehicle removed.'})


class BookingListCreateView(RidesView):
    def post(self, request):
        require_role(request.user, User.Role.CUSTOMER)
        if not isinstance(request.data, dict):
            raise ValidationError({'detail': 'Send a JSON object.'})
        key = request.data.get('request_key', '')
        if isinstance(key, str) and key:
            existing = loaded_bookings().filter(customer=request.user, request_key=key).first()
            if existing:
                return Response(booking_payload(existing, viewer=request.user))
        if not Vehicle.objects.filter(owner=request.user).exists():
            return Response({'detail': 'Add your car before booking.', 'missing_fields': ['vehicle']}, status=400)
        serializer = BookingInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        vehicle_id = data.pop('vehicle_id')
        business_id = data.pop('business_id', None)
        try:
            with transaction.atomic():
                User.objects.select_for_update().get(pk=request.user.pk)
                vehicle = Vehicle.objects.filter(pk=vehicle_id, owner=request.user).first()
                if vehicle is None:
                    raise ValidationError({'vehicle_id': 'Choose a car from your own garage.'})
                existing = Booking.objects.filter(customer=request.user, request_key=key).first() if key else None
                if existing:
                    return Response(booking_payload(existing, viewer=request.user))
                if Booking.objects.filter(customer=request.user, status__in=LIVE).exists():
                    raise ValidationError({'detail': 'You already have a booking in progress. Finish or cancel it first.'})
                business_label = ''
                if business_id:
                    from hub.models import BusinessProfile
                    business = BusinessProfile.objects.filter(owner=request.user, pk=business_id).first()
                    if not business: raise ValidationError({'business_id':'Choose your own business profile.'})
                    business_label = business.company
                booking = Booking(customer=request.user, vehicle=vehicle, business_label=business_label,
                                  vehicle_snapshot=vehicle_payload(vehicle), **data)
                rate = ServiceRate.objects.select_for_update().filter(service=booking.service).first()
                if (booking.service in REQUIRES_EXPLICIT_RATE and rate is None) or (rate and not rate.enabled):
                    raise ValidationError({'service': 'This service is not available. Please contact support.'})
                booking.set_estimate()
                if booking.estimated_fare > Decimal('9999999.99'):
                    raise ValidationError({'duration_hours': 'The estimated fare exceeds the supported maximum.'})
                claimed = None
                if booking.promo_code:
                    from hub.models import PromoCode, ClaimedPromo
                    code = booking.promo_code.upper()
                    promo = PromoCode.objects.select_for_update().filter(code=code,active=True).first()
                    if not promo or (promo.expires_at and promo.expires_at <= timezone.now()):
                        raise ValidationError({'promo_code':'Promotion is invalid or expired.'})
                    claimed = ClaimedPromo.objects.filter(user=request.user,promo=promo,used_booking__isnull=True).first()
                    if not claimed or ClaimedPromo.objects.filter(promo=promo,used_booking__isnull=False).count() >= promo.max_redemptions:
                        raise ValidationError({'promo_code':'Claim an unused code from Promotions, or remove it.'})
                    booking.promo_code = code
                    booking.discount_amount = max(Decimal('0'),min(promo.amount,booking.estimated_fare))
                    booking.estimated_fare -= booking.discount_amount
                booking.save()
                if claimed:
                    claimed.used_booking=booking
                    claimed.save(update_fields=['used_booking'])
                booking.add_event('CREATED', f'₹{booking.estimated_fare} estimate', request.user)
                notify(request.user, 'Booking request sent',
                       f'Booking #{booking.pk}: waiting for an eligible online driver.', 'BOOKING_CREATED', booking)
                notify_available_drivers(booking)
        except IntegrityError:
            # Unique partial indexes also protect concurrent requests on SQLite.
            return Response({'detail': 'A request is already in progress. Refresh Activity.'}, status=409)
        return Response(booking_payload(booking, viewer=request.user), status=201)

    def get(self, request):
        user = request.user
        if user.role == User.Role.CUSTOMER:
            qs = loaded_bookings().filter(customer=user)
        elif user.role == User.Role.DRIVER:
            qs = loaded_bookings().filter(driver=user)
        else:
            require_role(user, User.Role.ADMIN)
            qs = loaded_bookings()
        return Response({'count': qs.count(),
                         'active': [booking_payload(b, viewer=user) for b in qs.filter(status__in=LIVE)],
                         'past': [booking_payload(b, viewer=user) for b in qs.exclude(status__in=LIVE)[:60]]})


class BookingDetailView(RidesView):
    def get(self, request, booking_id):
        try:
            booking = owned_booking(request.user, booking_id)
            offer = False
        except NotFound:
            if request.user.role != User.Role.DRIVER:
                raise NotFound('Booking not found.')
            profile = approved_profile(request.user)
            if not profile.is_available or Booking.objects.filter(driver=request.user, status__in=ASSIGNED).exists():
                raise NotFound('This request is no longer available to you.')
            booking = eligible_requests(profile).filter(pk=booking_id).first()
            if booking is None:
                raise NotFound('This request is no longer available to you.')
            offer = True
        return Response(booking_payload(booking, viewer=request.user, offer=offer))


class BookingCancelView(RidesView):
    def post(self, request, booking_id):
        serializer = CancelInputSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data['reason']
        with transaction.atomic():
            booking = owned_booking(request.user, booking_id, lock=True)
            changed = Booking.objects.filter(pk=booking.pk, status__in=[Booking.Status.REQUESTED, Booking.Status.ACCEPTED]).update(
                status=Booking.Status.CANCELLED, cancelled_at=timezone.now(), cancel_reason=reason, updated_at=timezone.now(),
            )
            if not changed:
                raise ValidationError({'detail': 'Only a requested or accepted booking can be cancelled.'})
            booking.refresh_from_db()
            booking.add_event('CANCELLED', reason, request.user)
            from hub.models import ClaimedPromo
            ClaimedPromo.objects.filter(used_booking=booking).update(used_booking=None)
            for person in (booking.customer, booking.driver):
                if person:
                    notify(person, 'Booking cancelled', f'Booking #{booking.pk}: {reason}.', 'BOOKING_CANCELLED', booking)
        return Response(booking_payload(booking, viewer=request.user))


class DriverRequestFeedView(RidesView):
    def get(self, request):
        profile = approved_profile(request.user)
        busy = Booking.objects.filter(driver=request.user, status__in=ASSIGNED).exists()
        qs = eligible_requests(profile) if profile.is_available and not busy else Booking.objects.none()
        return Response({'count': qs.count(), 'is_available': profile.is_available, 'busy': busy,
                         'results': [booking_payload(b, viewer=request.user, offer=True) for b in qs[:40]]})


class DriverTripsView(BookingListCreateView):
    def get(self, request):
        require_role(request.user, User.Role.DRIVER)
        return super().get(request)

    def post(self, request):
        return Response({'detail': 'Use the requests feed to accept work.'}, status=405)


class BookingAcceptView(RidesView):
    def post(self, request, booking_id):
        try:
            with transaction.atomic():
                profile = approved_profile(request.user, lock=True)
                if not profile.is_available:
                    raise ValidationError({'detail': 'Go online before accepting requests.'})
                if Booking.objects.filter(driver=request.user, status__in=ASSIGNED).exists():
                    return Response({'detail': 'Finish your current trip before taking another.'}, status=409)
                booking = eligible_requests(profile).filter(pk=booking_id).first()
                if booking is None:
                    raise NotFound('This request was taken, cancelled or is not eligible for you.')
                now = timezone.now()
                changed = Booking.objects.filter(pk=booking.pk, status=Booking.Status.REQUESTED, driver__isnull=True).update(
                    driver=request.user, status=Booking.Status.ACCEPTED, accepted_at=now, updated_at=now,
                )
                if not changed:
                    return Response({'detail': 'Another driver already took this request.'}, status=409)
                booking.refresh_from_db()
                booking.add_event('ACCEPTED', f'{request.user.full_name} accepted the request.', request.user)
                issue_start_code(booking)
                transaction.on_commit(lambda: email_start_code(booking.pk))
                notify(booking.customer, 'Driver assigned', f'{request.user.full_name} accepted booking #{booking.pk}.',
                       'BOOKING_ACCEPTED', booking)
        except IntegrityError:
            return Response({'detail': 'You or this booking already have an active trip. Refresh Requests.'}, status=409)
        except OperationalError as error:
            if 'locked' not in str(error).lower():
                raise
            return Response({'detail': 'The request is being updated by another driver. Refresh and retry.'}, status=409)
        return Response(booking_payload(booking, viewer=request.user))


class BookingDeclineView(RidesView):
    def post(self, request, booking_id):
        profile = approved_profile(request.user)
        if not profile.is_available:
            raise ValidationError({'detail': 'Go online to manage requests.'})
        with transaction.atomic():
            booking = eligible_requests(profile).filter(pk=booking_id).first()
            if booking is None:
                raise NotFound('This request is no longer open.')
            _, created = BookingDecline.objects.get_or_create(booking=booking, driver=request.user)
            if created:
                booking.add_event('DECLINED', 'A driver passed on this request.', request.user)
        return Response({'detail': 'Request hidden from your feed. Other eligible drivers can still take it.'})


class BookingStartView(RidesView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'trip_start'

    def post(self, request, booking_id):
        try:
            with transaction.atomic():
                approved_profile(request.user,lock=True)
                booking=Booking.objects.select_for_update().filter(pk=booking_id,driver=request.user).first()
                if not booking: raise NotFound('Booking not found.')
                if booking.status!='ACCEPTED':
                    return Response({'detail':'Only your accepted trip can be started.'},status=400)
                row=TripStartCode.objects.select_for_update().filter(booking=booking).first()
                if not row:
                    return Response({'detail':'Ask the customer to open the trip-start code in their app.'},status=400)
                error=check_start_code(row,str(request.data.get('otp','')).strip())
                if error:
                    return Response({'detail':error},status=429 if row.locked_until and row.locked_until>timezone.now() else 400)
                now=timezone.now()
                booking.status='ONGOING';booking.started_at=now;booking.otp_verified_at=now
                booking.save(update_fields=['status','started_at','otp_verified_at','updated_at'])
                booking.add_event('STARTED','Customer trip-start code verified; trip started.',request.user)
                notify(booking.customer,'Your trip has started',f'Booking #{booking.pk}: your code was verified.','TRIP_STARTED',booking)
            return Response(booking_payload(booking,viewer=request.user))
        except OperationalError as error:
            if 'locked' not in str(error).lower():raise
            return Response({'detail':'Trip is being updated. Refresh and retry.'},status=409)


class BookingCompleteView(RidesView):
    def post(self, request, booking_id):
        require_role(request.user, User.Role.DRIVER)
        with transaction.atomic():
            booking = Booking.objects.filter(pk=booking_id, driver=request.user).first()
            if booking is None:
                raise NotFound('Booking not found.')
            now = timezone.now()
            # This beta freezes the quote. It does NOT measure driving time,
            # distance, tolls or waiting extras, and does NOT collect payment.
            changed = Booking.objects.filter(pk=booking.pk, driver=request.user, status=Booking.Status.ONGOING).update(
                status=Booking.Status.COMPLETED, completed_at=now,
                final_fare=F('estimated_fare'), updated_at=now,
            )
            if not changed:
                raise ValidationError({'detail': 'Only your running trip can be completed.'})
            booking.refresh_from_db()
            booking.add_event('COMPLETED', f'₹{booking.final_fare} fare recorded. No payment collected.', request.user)
            notify(booking.customer, 'Trip completed', f'Fare ₹{booking.final_fare} recorded. No money was charged.',
                   'TRIP_COMPLETED', booking)
            notify(request.user, 'Earnings recorded', f'₹{booking.payout} in the ledger for #{booking.pk}. No bank transfer.',
                   'PAYOUT', booking)
        return Response(booking_payload(booking, viewer=request.user))


def payout_expression():
    fee = Round(F('final_fare') * F('platform_fee_percent') * Value(Decimal('0.01')), precision=2)
    return ExpressionWrapper(F('final_fare') - fee, output_field=DecimalField(max_digits=12, decimal_places=2))


def total_payout(qs):
    return (qs.aggregate(total=Sum(payout_expression()))['total'] or Decimal('0')).quantize(Decimal('0.01'))


class DriverSummaryView(RidesView):
    def get(self, request):
        require_role(request.user, User.Role.DRIVER)
        profile = DriverProfile.objects.filter(user=request.user).first()
        now = timezone.localtime()
        day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        week_start = day_start - timedelta(days=now.weekday())
        completed = Booking.objects.filter(driver=request.user, status=Booking.Status.COMPLETED)
        chart = completed.filter(completed_at__gte=day_start-timedelta(days=6)).annotate(day=TruncDate('completed_at')).values('day').annotate(
            payout=Sum(payout_expression()), trips=Count('id'),
        )
        by_day = {row['day']: row for row in chart}
        daily = []
        for offset in range(6, -1, -1):
            day = (now - timedelta(days=offset)).date()
            row = by_day.get(day, {})
            daily.append({'date': day.isoformat(), 'label': day.strftime('%a')[:2],
                          'payout': str((row.get('payout') or Decimal('0')).quantize(Decimal('0.01'))),
                          'trips': row.get('trips', 0)})
        online = bool(profile and profile.is_approved and profile.is_available and
                      (not profile.licence_expiry or profile.licence_expiry >= timezone.localdate()))
        return Response({
            'available': online, 'approved': bool(profile and profile.is_approved),
            'today': str(total_payout(completed.filter(completed_at__gte=day_start))),
            'week': str(total_payout(completed.filter(completed_at__gte=week_start))),
            'lifetime': str(total_payout(completed)),
            'gross_lifetime': str(completed.aggregate(total=Sum('final_fare'))['total'] or Decimal('0')),
            'platform_fee_percent': PLATFORM_FEE_PERCENT, 'completed_trips': completed.count(),
            'active_trips': Booking.objects.filter(driver=request.user, status__in=ASSIGNED).count(),
            'open_requests': eligible_requests(profile).count() if online and not Booking.objects.filter(driver=request.user, status__in=ASSIGNED).exists() else 0, 'daily': daily,
            'settlement_live': False, 'is_demo': request.user.email.endswith('@demo.drivemate.local'),
        })


class NotificationListView(RidesView):
    def get(self, request):
        qs = Notification.objects.filter(user=request.user)
        return Response({'unread': qs.filter(read_at__isnull=True).count(), 'count': qs.count(),
                         'results': [notification_payload(n) for n in qs[:60]]})


class NotificationReadView(RidesView):
    def post(self, request, notification_id=None):
        qs = Notification.objects.filter(user=request.user)
        if notification_id is None:
            qs.filter(read_at__isnull=True).update(read_at=timezone.now())
            return Response({'unread': 0})
        notification = qs.filter(pk=notification_id).first()
        if notification is None:
            raise NotFound('Notification not found.')
        notification.mark_read()
        return Response({'unread': qs.filter(read_at__isnull=True).count(),
                         'notification': notification_payload(notification)})


class AdminRidesOverviewView(RidesView):
    def get(self, request):
        require_role(request.user, User.Role.ADMIN)
        completed = Booking.objects.filter(status=Booking.Status.COMPLETED)
        return Response({
            'bookings_total': Booking.objects.count(),
            'bookings_today': Booking.objects.filter(created_at__date=timezone.localdate()).count(),
            'open_requests': Booking.objects.filter(status=Booking.Status.REQUESTED).count(),
            'active_trips': Booking.objects.filter(status__in=ASSIGNED).count(),
            'completed_trips': completed.count(),
            'cancelled': Booking.objects.filter(status=Booking.Status.CANCELLED).count(),
            'ledger_commission_lifetime': str(sum((platform_fee(b.final_fare, b.platform_fee_percent) for b in completed), Decimal('0'))),
            'available_drivers': DriverProfile.objects.filter(verification_status=DriverProfile.Status.APPROVED, is_available=True).count(),
            'settlement_live': False,
        })
