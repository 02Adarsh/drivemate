"""V9 participant-only trip OTP, map location, cash records and receipts."""
import io
from decimal import Decimal
from pathlib import Path

from django.conf import settings
from django.db import transaction, OperationalError
from django.db.models import Avg
from django.http import FileResponse
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from hub.views import send_real_email
from .models import Booking, TripStartCode, TripRating, notify
from .trip_security import issue_start_code, reveal_code, email_start_code
from .views import RidesView, owned_booking, booking_payload, require_role


class StartCodeView(RidesView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'trip_start'

    def customer_booking(self, request, booking_id):
        booking = Booking.objects.filter(pk=booking_id, customer=request.user).first()
        if not booking: raise NotFound('Booking not found.')
        if booking.status != 'ACCEPTED':
            raise ValidationError({'detail':'Start code is available only after a driver accepts, and before trip start.'})
        return booking

    def get(self, request, booking_id):
        booking = self.customer_booking(request, booking_id)
        with transaction.atomic():
            booking=Booking.objects.select_for_update().get(pk=booking.pk)
            if booking.status!='ACCEPTED':raise ValidationError({'detail':'Trip is no longer awaiting a start code.'})
            row = TripStartCode.objects.filter(booking=booking).first()
            if not row:
                row = issue_start_code(booking)
            code = reveal_code(row)
        return Response({'otp':code, 'expires_at':row.expires_at, 'expired':row.expires_at<=timezone.now(),
                         'email_sent':row.email_sent, 'message':'Share only with your assigned driver when you meet.'})

    def post(self, request, booking_id):
        booking = self.customer_booking(request, booking_id)
        with transaction.atomic():
            booking=Booking.objects.select_for_update().get(pk=booking.pk)
            if booking.status!='ACCEPTED':raise ValidationError({'detail':'Trip is no longer awaiting a start code.'})
            row = issue_start_code(booking)
            transaction.on_commit(lambda:email_start_code(booking.pk))
        return Response({'otp':reveal_code(row),'expires_at':row.expires_at,'expired':False})


class LocationView(RidesView):
    def post(self, request, booking_id):
        require_role(request.user, 'DRIVER')
        booking = Booking.objects.filter(pk=booking_id, driver=request.user, status__in=['ACCEPTED','ONGOING']).first()
        if not booking: raise NotFound('Active assigned trip not found.')
        lat = serializers.DecimalField(max_digits=10,decimal_places=7,min_value=-90,max_value=90).run_validation(request.data.get('latitude'))
        lon = serializers.DecimalField(max_digits=10,decimal_places=7,min_value=-180,max_value=180).run_validation(request.data.get('longitude'))
        now = timezone.now()
        Booking.objects.filter(pk=booking.pk, driver=request.user, status__in=['ACCEPTED','ONGOING']).update(
            driver_latitude=lat,driver_longitude=lon,location_updated_at=now)
        return Response({'updated_at':now})

    def get(self, request, booking_id):
        booking = owned_booking(request.user, booking_id)
        active = booking.status in ['ACCEPTED','ONGOING']
        return Response({'latitude':float(booking.driver_latitude) if active and booking.driver_latitude is not None else None,
                         'longitude':float(booking.driver_longitude) if active and booking.driver_longitude is not None else None,
                         'updated_at':booking.location_updated_at if active else None})


class CashReceivedView(RidesView):
    def post(self, request, booking_id):
        try:
            require_role(request.user,'DRIVER')
            with transaction.atomic():
                booking = Booking.objects.select_for_update().filter(pk=booking_id,driver=request.user).first()
                if not booking: raise NotFound('Booking not found.')
                if booking.status != 'COMPLETED': raise ValidationError({'detail':'Complete the trip before recording cash.'})
                if booking.cash_received_at:
                    return Response(booking_payload(booking,viewer=request.user))
                from payments.models import DirectUPIPayment
                if DirectUPIPayment.objects.filter(booking=booking).exclude(status='CANCELLED').exists():
                    raise ValidationError({'detail':'A direct-UPI request is open/reported/confirmed. Resolve or close it after checking your bank before recording cash; do not collect twice.'})
                if booking.final_fare is not None and booking.final_fare <= 0:
                    raise ValidationError({'detail':'No positive payment is due.'})
                booking.cash_received_at = timezone.now()
                booking.save(update_fields=['cash_received_at','updated_at'])
                booking.add_event('NOTE',f'Assigned driver confirmed cash received: INR {booking.final_fare}.',request.user)
                notify(booking.customer,'Cash payment recorded',f'Your driver confirmed INR {booking.final_fare} received for #{booking.pk}.','CASH',booking)
            from hub.models import Preferences
            preference = Preferences.objects.filter(user=booking.customer).first()
            if not preference or preference.email_receipts:
                transaction.on_commit(lambda: email_cash_receipt(booking.pk))
            return Response(booking_payload(booking,viewer=request.user))
        except OperationalError as error:
            if 'locked' not in str(error).lower():raise
            return Response({'detail':'Payment is being updated. Refresh and retry.'},status=409)


class RatingView(RidesView):
    def post(self, request, booking_id):
        booking = owned_booking(request.user,booking_id)
        if booking.status!='COMPLETED' or request.user.pk not in [booking.customer_id,booking.driver_id]:
            raise PermissionDenied('Only completed-trip participants can rate.')
        score=serializers.IntegerField(min_value=1,max_value=5).run_validation(request.data.get('score'))
        comment=serializers.CharField(max_length=500,allow_blank=True).run_validation(request.data.get('comment',''))
        row,_=TripRating.objects.update_or_create(booking=booking,author=request.user,defaults={'score':score,'comment':comment})
        return Response({'score':row.score,'comment':row.comment,'detail':'Rating saved.'})


def receipt_bytes(booking):
    from reportlab.pdfgen import canvas
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.lib.utils import simpleSplit
    font=Path(settings.BASE_DIR)/'assets/fonts/Poppins-Regular.ttf'
    if 'DriveMate' not in pdfmetrics.getRegisteredFontNames():
        pdfmetrics.registerFont(TTFont('DriveMate',str(font)))
    result=io.BytesIO(); c=canvas.Canvas(result,pagesize=(595,842))
    c.setFont('DriveMate',24);c.drawString(44,785,'DriveMate')
    c.setFont('DriveMate',12);c.drawString(44,755,f'Trip receipt #{booking.pk} - manual payment record')
    from payments.state import payment_state
    pay=payment_state(booking)
    y=712
    rows=[('Service',booking.get_service_display()),('Status',booking.get_status_display()),
          ('Customer',booking.customer.full_name),('Driver',booking.driver.full_name if booking.driver else 'Not assigned'),
          ('Pickup',booking.pickup),('Destination',booking.drop_address or 'As requested'),
          ('Car',str(booking.vehicle_snapshot.get('display_name','Customer car'))),
          ('Scheduled',str(booking.scheduled_at or 'As soon as available')),
          ('Duration',f'{booking.duration_hours} hours'),('Business profile',booking.business_label or 'Personal'),
          ('Discount',f'INR {booking.discount_amount}'),
          ('Final fare',f'INR {booking.final_fare if booking.final_fare is not None else booking.estimated_fare}'),
          ('Payment',pay['payment_label']),
          ('Verification','Manual driver assertion; not independently bank/gateway verified'),
          ('Receiving UPI',(pay.get('upi_payment') or {}).get('receiver_upi_id','Not applicable')),
          ('Bank reference',(pay.get('upi_payment') or {}).get('bank_reference','Not recorded')),
          ('Platform commission',f'{booking.platform_fee_percent}% - not a bank settlement'),
          ('Trip start verified','Yes' if booking.otp_verified_at else 'Legacy trip / not started')]
    for label,value in rows:
        c.setFont('DriveMate',9);c.drawString(44,y,label.upper());y-=17
        c.setFont('DriveMate',11)
        for line in simpleSplit(str(value),'DriveMate',11,500):
            c.drawString(44,y,line);y-=17
        y-=9
        if y<100:c.showPage();y=780
    c.setFont('DriveMate',8)
    for line in simpleSplit('This is a trip/manual payment record, not a GST tax invoice or independent bank/gateway proof. A personal UPI QR only prefills the fare; the payer authorizes in their UPI app and the driver checks actual credit. No automatic debit, payout or refund is performed by DriveMate.','DriveMate',8,500):
        c.drawString(44,y,line);y-=13
    c.save();return result.getvalue()


class ReceiptView(RidesView):
    throttle_classes=[ScopedRateThrottle]
    throttle_scope='otp'
    def get(self,request,booking_id):
        booking=owned_booking(request.user,booking_id)
        if booking.status!='COMPLETED':raise ValidationError({'detail':'Receipts are available for completed trips.'})
        data=receipt_bytes(booking)
        return FileResponse(io.BytesIO(data),content_type='application/pdf',as_attachment=True,filename=f'DriveMate-trip-{booking.pk}.pdf')

    def post(self,request,booking_id):
        booking=owned_booking(request.user,booking_id)
        if booking.status!='COMPLETED':raise ValidationError({'detail':'Complete the trip first.'})
        # Email only to the authenticated participant's verified email; never to
        # an arbitrary address supplied by a client (anti-spam/PII protection).
        send_real_email(f'DriveMate trip #{booking.pk} receipt','Your trip receipt is attached. Payment status is manually confirmed by the assigned driver; it is not independent bank verification.',
                        [request.user.email],(f'DriveMate-trip-{booking.pk}.pdf',receipt_bytes(booking),'application/pdf'))
        return Response({'detail':'Receipt emailed to your verified address.'})


def email_cash_receipt(booking_id):
    booking=Booking.objects.select_related('customer','driver').filter(pk=booking_id,status='COMPLETED').first()
    if not booking:return
    try:
        send_real_email(f'DriveMate trip #{booking.pk} receipt','Your assigned driver manually recorded payment received. Your trip receipt is attached. This is not independent bank/gateway verification.',
          [booking.customer.email],(f'DriveMate-trip-{booking.pk}.pdf',receipt_bytes(booking),'application/pdf'))
    except Exception:
        # The receipt remains in the app; failure never rolls back a real cash record.
        import logging
        logging.getLogger(__name__).warning('Receipt email failed for booking %s; retry is available in app.',booking.pk)


class ParticipantPhotoView(RidesView):
    def get(self,request,booking_id):
        from django.core.files.storage import default_storage
        from django.http import Http404
        import mimetypes
        booking=owned_booking(request.user,booking_id)
        person=booking.driver if request.query_params.get('person','driver')=='driver' else booking.customer
        if not person or not person.profile_photo_key or not default_storage.exists(person.profile_photo_key):raise Http404
        return FileResponse(default_storage.open(person.profile_photo_key,'rb'),content_type=mimetypes.guess_type(person.profile_photo_key)[0] or 'image/jpeg')
