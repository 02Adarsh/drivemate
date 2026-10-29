import io
import json
import logging
import secrets
import urllib.parse
import urllib.request
from datetime import timedelta
from decimal import Decimal

from django.conf import settings
from django.contrib.auth.hashers import make_password, check_password
from django.core.cache import cache
from django.core.mail import EmailMessage, send_mail
from django.db import transaction
from django.db.models import Q, Avg, Count
from django.http import FileResponse, JsonResponse
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from accounts.models import User
from accounts.views import user_payload
from rides.models import Booking, notify
from rides.views import RidesView, owned_booking, booking_payload, require_role
from .models import (Preferences, SavedPlace, Contact, BusinessProfile, SupportTicket,
                     SupportMessage, PromoCode, ClaimedPromo, EmailChange)

logger = logging.getLogger(__name__)


def email_configured():
    return not settings.EMAIL_BACKEND.endswith(('console.EmailBackend', 'dummy.EmailBackend'))


def send_real_email(subject, body, recipients, attachment=None):
    if not email_configured():
        raise ValidationError({'detail': 'Email delivery is not configured. Set SMTP on the backend; no email was sent.'})
    try:
        message = EmailMessage(subject, body, settings.DEFAULT_FROM_EMAIL, recipients)
        if attachment:
            message.attach(*attachment)
        if message.send(fail_silently=False) != 1:
            raise RuntimeError('Email was not accepted')
    except Exception:
        logger.warning('Account email delivery failed; check server SMTP configuration (no secrets logged).')
        raise ValidationError({'detail': 'Email could not be sent. Check SMTP on the backend and retry.'})


class PlaceSerializer(serializers.ModelSerializer):
    latitude = serializers.DecimalField(max_digits=10, decimal_places=7, min_value=-90, max_value=90)
    longitude = serializers.DecimalField(max_digits=10, decimal_places=7, min_value=-180, max_value=180)
    kind = serializers.ChoiceField(choices=['HOME', 'WORK', 'OTHER'], default='OTHER')
    class Meta:
        model = SavedPlace
        fields = ['id', 'label', 'address', 'latitude', 'longitude', 'kind']


class ContactSerializer(serializers.ModelSerializer):
    def validate_phone(self, value):
        number = ''.join(c for c in value if c.isdigit() or c == '+')
        if not 10 <= len(number.lstrip('+')) <= 15:
            raise serializers.ValidationError('Enter a complete mobile number.')
        return number
    class Meta:
        model = Contact
        fields = ['id', 'name', 'phone', 'relationship', 'emergency']


class BusinessSerializer(serializers.ModelSerializer):
    class Meta:
        model = BusinessProfile
        fields = ['id', 'company', 'department', 'employee_id']


COLLECTIONS = {'places': (SavedPlace, PlaceSerializer), 'contacts': (Contact, ContactSerializer),
               'business': (BusinessProfile, BusinessSerializer)}


class CollectionView(RidesView):
    def config(self, collection):
        if collection not in COLLECTIONS:
            raise NotFound('Collection not found.')
        return COLLECTIONS[collection]

    def get(self, request, collection, item_id=None):
        model, serializer = self.config(collection)
        qs = model.objects.filter(owner=request.user).order_by('-id')
        if item_id is not None:
            item = qs.filter(pk=item_id).first()
            if not item: raise NotFound('Item not found.')
            return Response(serializer(item).data)
        return Response({'count': qs.count(), 'results': serializer(qs[:100], many=True).data})

    def post(self, request, collection, item_id=None):
        model, serializer = self.config(collection)
        if item_id is not None: raise NotFound('Use update on an existing item.')
        if model.objects.filter(owner=request.user).count() >= 100:
            raise ValidationError({'detail': 'Maximum 100 items per account.'})
        form = serializer(data=request.data)
        form.is_valid(raise_exception=True)
        form.save(owner=request.user)
        return Response(form.data, status=201)

    def put(self, request, collection, item_id):
        model, serializer = self.config(collection)
        item = model.objects.filter(owner=request.user, pk=item_id).first()
        if not item: raise NotFound('Item not found.')
        form = serializer(item, data=request.data)
        form.is_valid(raise_exception=True)
        form.save()
        return Response(form.data)

    def delete(self, request, collection, item_id):
        model, _ = self.config(collection)
        count, _ = model.objects.filter(owner=request.user, pk=item_id).delete()
        if not count: raise NotFound('Item not found.')
        return Response({'detail': 'Removed.'})


class PreferencesSerializer(serializers.ModelSerializer):
    theme = serializers.ChoiceField(choices=['light', 'dark'])
    language = serializers.ChoiceField(choices=['en', 'hi'])
    class Meta:
        model = Preferences
        fields = ['theme', 'language', 'trip_updates', 'email_receipts', 'marketing', 'large_text']


class AccountView(RidesView):
    def get(self, request):
        prefs, _ = Preferences.objects.get_or_create(user=request.user)
        bookings = Booking.objects.filter(Q(customer=request.user) | Q(driver=request.user))
        completed = bookings.filter(status='COMPLETED')
        from rides.models import TripRating
        ratings = TripRating.objects.filter(booking__driver=request.user) if request.user.role=='DRIVER' else TripRating.objects.filter(booking__customer=request.user)
        ratings = ratings.exclude(author=request.user).aggregate(average=Avg('score'),count=Count('id'))
        return Response({'user': user_payload(request.user), 'preferences': PreferencesSerializer(prefs).data,
                         'rating_average': ratings['average'], 'rating_count': ratings['count'], 'completed_trips': completed.count(), 'active_trips': bookings.filter(status__in=['REQUESTED', 'ACCEPTED', 'ONGOING']).count(),
                         'saved_places': SavedPlace.objects.filter(owner=request.user).count(),
                         'open_tickets': SupportTicket.objects.filter(owner=request.user).exclude(status='CLOSED').count(),
                         'email_delivery_configured': email_configured(), 'trip_pin_required': True,
                         'payment_method': 'CASH_OR_DIRECT_UPI_MANUAL', 'payment_methods':['CASH','UPI_DIRECT_MANUAL'], 'map_provider': 'OpenStreetMap',
                         'invite_code': prefs.invite_code,
                         'referral_count': Preferences.objects.filter(referred_by=request.user,user__email_verified=True).count()})

    def put(self, request):
        name = str(request.data.get('name', '')).strip()
        phone = ''.join(c for c in str(request.data.get('phone', '')) if c.isdigit() or c == '+')
        if not 2 <= len(name) <= 120 or not 10 <= len(phone.lstrip('+')) <= 15:
            raise ValidationError({'detail': 'Full name (2–120 characters) and a valid mobile number are required.'})
        if User.objects.filter(phone=phone).exclude(pk=request.user.pk).exists():
            raise ValidationError({'phone': 'This mobile number is already registered.'})
        request.user.full_name = name
        request.user.phone = phone
        request.user.save(update_fields=['full_name', 'phone'])
        return Response({'user': user_payload(request.user)})


class PreferencesView(RidesView):
    def put(self, request):
        prefs, _ = Preferences.objects.get_or_create(user=request.user)
        form = PreferencesSerializer(prefs, data=request.data, partial=True)
        form.is_valid(raise_exception=True)
        form.save()
        return Response(form.data)


class EmailChangeView(RidesView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self, request):
        if not request.user.check_password(str(request.data.get('password',''))):
            raise ValidationError({'detail':'Confirm your current password to change email.'})
        email = serializers.EmailField().run_validation(request.data.get('email', '')).lower()
        if User.objects.filter(email__iexact=email).exists():
            raise ValidationError({'email': 'Email is already registered.'})
        code = f'{secrets.randbelow(1000000):06d}'
        send_real_email('DriveMate: confirm your new email', f'Your email-change code is {code}. Valid for 10 minutes.', [email])
        EmailChange.objects.update_or_create(user=request.user, defaults={
            'email': email, 'code_hash': make_password(code), 'expires_at': timezone.now()+timedelta(minutes=10), 'attempts': 0})
        return Response({'detail': 'Code sent to the new email address.'})

    def put(self, request):
        with transaction.atomic():
            row = EmailChange.objects.select_for_update().filter(user=request.user).first()
            if not row or row.expires_at <= timezone.now():
                raise ValidationError({'detail': 'Code expired. Request a new code.'})
            if row.attempts >= 5: return Response({'detail': 'Too many attempts. Request a new code.'}, status=429)
            row.attempts += 1
            row.save(update_fields=['attempts'])
            if not check_password(str(request.data.get('otp', '')), row.code_hash):
                return Response({'detail': 'Incorrect code.'}, status=400)
            if User.objects.filter(email__iexact=row.email).exclude(pk=request.user.pk).exists():
                return Response({'detail': 'Email is already registered.'}, status=400)
            request.user.email = row.email
            request.user.email_verified = True
            request.user.save(update_fields=['email', 'email_verified'])
            row.delete()
        return Response({'user': user_payload(request.user), 'detail': 'Email updated.'})


def ticket_payload(ticket):
    return {'id': ticket.pk, 'category': ticket.category, 'subject': ticket.subject,
            'description': ticket.description, 'status': ticket.status, 'booking_id': ticket.booking_id,
            'created_at': ticket.created_at, 'owner_name': ticket.owner.full_name,
            'messages': [{'id': m.pk, 'text': m.text, 'staff': bool(m.author and m.author.is_staff),
                          'at': m.created_at} for m in ticket.messages.select_related('author').all()]}


class TicketsView(RidesView):
    def get(self, request, ticket_id=None):
        qs = SupportTicket.objects.select_related('owner').prefetch_related('messages').order_by('-updated_at')
        if not (request.user.is_staff and request.user.role == 'ADMIN'):
            qs = qs.filter(owner=request.user)
        if ticket_id:
            ticket = qs.filter(pk=ticket_id).first()
            if not ticket: raise NotFound('Ticket not found.')
            return Response(ticket_payload(ticket))
        return Response({'results': [ticket_payload(t) for t in qs[:100]], 'count': qs.count()})

    def post(self, request, ticket_id=None):
        if ticket_id:
            qs = SupportTicket.objects.all()
            staff = request.user.is_staff and request.user.role == 'ADMIN'
            if not staff: qs = qs.filter(owner=request.user)
            ticket = qs.filter(pk=ticket_id).first()
            if not ticket: raise NotFound('Ticket not found.')
            text = str(request.data.get('text', '')).strip()
            if not 2 <= len(text) <= 2000: raise ValidationError({'detail': 'Reply must contain 2–2000 characters.'})
            SupportMessage.objects.create(ticket=ticket, author=request.user, text=text)
            state = str(request.data.get('status', '')).upper()
            if state in ['OPEN', 'CLOSED'] and (staff or state == 'CLOSED'): ticket.status = state
            ticket.save()
            if staff:
                notify(ticket.owner, 'Support replied', f'Ticket #{ticket.pk}: {ticket.subject}', 'SUPPORT')
            return Response(ticket_payload(ticket))
        subject = str(request.data.get('subject', '')).strip()
        description = str(request.data.get('description', '')).strip()
        category = str(request.data.get('category', 'GENERAL')).upper()
        if not 3 <= len(subject) <= 120 or not 10 <= len(description) <= 2000:
            raise ValidationError({'detail': 'Subject (3–120) and description (10–2000 characters) are required.'})
        if category not in ['GENERAL', 'TRIP', 'PAYMENT', 'SAFETY', 'ACCOUNT']: raise ValidationError({'category': 'Choose a valid category.'})
        booking = None
        if request.data.get('booking_id'): booking = owned_booking(request.user, request.data['booking_id'])
        ticket = SupportTicket.objects.create(owner=request.user, booking=booking, subject=subject,
                                              description=description, category=category)
        return Response(ticket_payload(ticket), status=201)


class PromotionsView(RidesView):
    def get(self, request):
        rows = ClaimedPromo.objects.filter(user=request.user).select_related('promo').order_by('-id')
        return Response({'results': [{'code': r.promo.code, 'description': r.promo.description,
                                      'amount': str(r.promo.amount), 'used': r.used_booking_id is not None,
                                      'expires_at': r.promo.expires_at,
                                      'active': r.promo.active and (not r.promo.expires_at or r.promo.expires_at > timezone.now())} for r in rows]})

    def post(self, request):
        code = str(request.data.get('code', '')).strip().upper()
        promo = PromoCode.objects.filter(code=code, active=True).first()
        if not promo or (promo.expires_at and promo.expires_at <= timezone.now()):
            raise ValidationError({'detail': 'This code is invalid or expired.'})
        row, _ = ClaimedPromo.objects.get_or_create(user=request.user, promo=promo)
        return Response({'code': promo.code, 'amount': str(promo.amount), 'used': row.used_booking_id is not None})


class PrivacyView(RidesView):
    def get(self, request):
        prefs, _ = Preferences.objects.get_or_create(user=request.user)
        return Response({'user': user_payload(request.user), 'preferences': PreferencesSerializer(prefs).data,
                         'places': PlaceSerializer(SavedPlace.objects.filter(owner=request.user), many=True).data,
                         'contacts': ContactSerializer(Contact.objects.filter(owner=request.user), many=True).data,
                         'trips': [booking_payload(b, viewer=request.user) for b in Booking.objects.filter(
                             Q(customer=request.user) | Q(driver=request.user)).order_by('-id')[:200]],
                         'notes': 'Private documents and authentication secrets are not included in this export.'})

    def post(self, request):
        return self.delete(request)

    def delete(self, request):
        if request.user.role == 'ADMIN': raise PermissionDenied('Admin accounts must be managed through staff administration.')
        if not request.user.check_password(str(request.data.get('password', ''))):
            raise ValidationError({'detail': 'Confirm your current password to deactivate your account.'})
        if Booking.objects.filter(Q(customer=request.user) | Q(driver=request.user), status__in=['REQUESTED','ACCEPTED','ONGOING']).exists():
            raise ValidationError({'detail': 'Finish or cancel active bookings before deactivating.'})
        request.user.is_active = False
        request.user.save(update_fields=['is_active'])
        from accounts.models import DriverProfile
        DriverProfile.objects.filter(user=request.user).update(is_available=False)
        return Response({'detail': 'Account deactivated. History is retained for support/legal records; contact the operator for erasure requests.'})


class MapLookupView(RidesView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'map'

    def get(self, request):
        query = str(request.query_params.get('q', '')).strip()
        lat = request.query_params.get('lat')
        lon = request.query_params.get('lon')
        reverse = lat is not None and lon is not None
        if reverse:
            latitude = serializers.FloatField(min_value=-90,max_value=90).run_validation(lat)
            longitude = serializers.FloatField(min_value=-180,max_value=180).run_validation(lon)
            params = {'format':'jsonv2','lat':latitude,'lon':longitude,'zoom':18}
            route = 'reverse'
        else:
            if not 3 <= len(query) <= 160: raise ValidationError({'detail':'Enter a place name of 3–160 characters.'})
            params = {'format':'jsonv2','q':query,'limit':5,'countrycodes':'in','addressdetails':1}
            route = 'search'
        encoded = urllib.parse.urlencode(params)
        key = 'geo:'+route+':'+encoded
        result = cache.get(key)
        if result is not None: return Response({'results':result,'provider':'OpenStreetMap / Nominatim'})
        if not cache.add('geo-global-request-slot', True, timeout=2):
            return Response({'detail':'Please wait two seconds before another address lookup.'},status=429)
        try:
            url = 'https://nominatim.openstreetmap.org/'+route+'?'+encoded
            req = urllib.request.Request(url, headers={'User-Agent':settings.GEOCODING_USER_AGENT,'Accept':'application/json'})
            with urllib.request.urlopen(req, timeout=8) as reply:
                data = json.loads(reply.read(1024*1024).decode())
            rows = [data] if reverse else data
            result = [{'address':str(r['display_name'])[:240], 'latitude':float(r['lat']), 'longitude':float(r['lon'])}
                      for r in rows if all(k in r for k in ['display_name','lat','lon'])]
            cache.set(key,result,3600)
            return Response({'results':result,'provider':'OpenStreetMap / Nominatim'})
        except Exception:
            return Response({'detail':'Address lookup is unavailable. You can still tap a map pin and enter its address manually.'},status=503)
