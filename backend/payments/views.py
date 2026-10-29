import io
import re
import secrets
from decimal import Decimal
from uuid import uuid4

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import IntegrityError, OperationalError, transaction
from django.http import FileResponse, Http404
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle

from rides.models import Booking, notify
from rides.views import RidesView, require_role, owned_booking
from .models import DriverUPIProfile, DriverUPIChange, DirectUPIPayment, PaymentAudit
from .qr import normalize_upi, read_uploaded_qr, make_payload, png


class PaymentView(RidesView):
    throttle_classes=[ScopedRateThrottle]
    throttle_scope='payment'


def reference(value):
    text=str(value or '').strip().upper().replace(' ','')
    if not re.fullmatch(r'[A-Z0-9-]{6,64}',text):
        raise ValidationError({'reference':'Enter the UPI transaction reference/UTR from the payment app (6–64 letters/digits). This is not bank verification.'})
    return text


def profile_payload(row):
    return {'upi_id':row.upi_id,'payee_name':row.payee_name,'uploaded_payee_hint':row.uploaded_payee_hint,
            'qr_uploaded':bool(row.qr_storage_key),'qr_matches_upi':True,'bank_ownership_verified':False,
            'active':row.active,'version':row.version,'updated_at':row.updated_at,
            'mode':'DIRECT_UPI_MANUAL','message':'QR matches the entered ID; it does not verify bank ownership. Existing trip requests keep their original payee snapshot.'}


class DriverProfileView(PaymentView):
    def get(self,request):
        require_role(request.user,'DRIVER')
        row=DriverUPIProfile.objects.filter(driver=request.user).first()
        if not row:
            return Response({'configured':False,'mode':'DIRECT_UPI_MANUAL','bank_ownership_verified':False})
        return Response({'configured':True,**profile_payload(row)})

    def post(self,request):
        require_role(request.user,'DRIVER')
        if not request.user.check_password(str(request.data.get('password',''))):
            raise ValidationError({'detail':'Confirm your current password to save receiving payment details.'})
        if serializers.BooleanField().run_validation(request.data.get('ownership_attested',False)) is not True:
            raise ValidationError({'detail':'Confirm this is your own receiving UPI ID/QR.'})
        existing=DriverUPIProfile.objects.filter(driver=request.user).first()
        active=serializers.BooleanField().run_validation(request.data.get('active',True))
        upload=request.FILES.get('file') or request.FILES.get('qr')
        entered=str(request.data.get('upi_id','')).strip()
        content=None;hint='';digest=''
        if upload:
            decoded,content,digest=read_uploaded_qr(upload)
            vpa=normalize_upi(entered) if entered else decoded['upi_id']
            if vpa!=decoded['upi_id']:
                raise ValidationError({'upi_id':'Uploaded QR belongs to a different UPI ID. Use the matching receiving QR.'})
            hint=decoded['name_hint']
        else:
            if not existing:raise ValidationError({'file':'Upload your receiving UPI QR image first.'})
            vpa=normalize_upi(entered or existing.upi_id)
            if vpa!=existing.upi_id:raise ValidationError({'file':'Changing the receiving ID requires its matching QR image.'})
            hint=existing.uploaded_payee_hint;digest=existing.qr_sha256
        key=existing.qr_storage_key if existing else ''
        new_key=None
        if content:
            new_key=default_storage.save(f'private/driver-upi/{request.user.pk}/{uuid4().hex}.png',ContentFile(content))
            key=new_key
        try:
            with transaction.atomic():
                from accounts.models import User
                User.objects.select_for_update().get(pk=request.user.pk)
                row=DriverUPIProfile.objects.select_for_update().filter(driver=request.user).first()
                if content is None and row and row.upi_id!=vpa:raise ValidationError({'detail':'Receiving details changed in another session. Reload and upload a matching QR.'})
                old=row.upi_id if row else ''
                version=row.version+1 if row else 1
                row,_=DriverUPIProfile.objects.update_or_create(driver=request.user,defaults={
                    'upi_id':vpa,'payee_name':request.user.full_name,'uploaded_payee_hint':hint,
                    'qr_storage_key':key,'qr_sha256':digest,'active':active,'version':version,'ownership_attested_at':timezone.now()})
                DriverUPIChange.objects.create(driver=request.user,previous_upi_id=old,new_upi_id=vpa,profile_version=version,qr_sha256=digest)
        except Exception:
            if new_key:default_storage.delete(new_key)
            raise
        return Response({'configured':True,**profile_payload(row)})


class DriverQRImageView(PaymentView):
    def get(self,request):
        require_role(request.user,'DRIVER')
        row=DriverUPIProfile.objects.filter(driver=request.user).first()
        if not row or not default_storage.exists(row.qr_storage_key):raise Http404
        reply=FileResponse(default_storage.open(row.qr_storage_key,'rb'),content_type='image/png')
        reply['Cache-Control']='private, no-store'
        return reply


def participant(request,booking_id,lock=False):
    booking=owned_booking(request.user,booking_id,lock=lock)
    if request.user.pk not in [booking.customer_id,booking.driver_id]:
        raise PermissionDenied('Only the customer/assigned driver can use this direct-UPI request.')
    return booking


def payment_payload(row,viewer):
    driver_view=viewer.pk==row.driver_id
    return {'id':str(row.pk),'booking_id':row.booking_id,'amount':str(row.amount),'currency':row.currency,
            'receiver_upi_id':row.receiver_upi_id,'receiver_name':row.receiver_name,'reference':row.reference,
            'qr_payload':row.qr_payload if row.status in ['CREATED','REPORTED','REJECTED'] else None,'status':row.status,'status_label':row.get_status_display(),
            'customer_reference':row.customer_reference,'reported_at':row.reported_at,'bank_reference':row.bank_reference,
            'confirmed_at':row.confirmed_at,'review_note':row.review_note,'created_at':row.created_at,
            'amount_editable_in_drivemate':False,'external_upi_amount_lock_guaranteed':False,
            'bank_verified':False,'verification_mode':'MANUAL_DRIVER',
            'can_report':not driver_view and row.status in ['CREATED','REPORTED','REJECTED'],
            'can_confirm':driver_view and row.status in ['CREATED','REPORTED','REJECTED'],
            'can_reject':driver_view and row.status=='REPORTED',
            'can_cancel':row.status in ['CREATED','REJECTED'],
            'audit':[{'action':a.action,'note':a.note,'at':a.created_at} for a in row.audit.all()],
            'notice':'Personal direct UPI prefills the fare. Your UPI app may allow edits; pay the exact fare. Scanning/reporting is not payment proof. The driver must check actual bank credit. Old QR images remain payable at the bank even if closed in this app.'}


class TripUPIView(PaymentView):
    def get(self,request,booking_id):
        booking=participant(request,booking_id)
        row=DirectUPIPayment.objects.filter(booking=booking).first()
        if not row:raise NotFound('No UPI request yet. Open payment to generate the final-fare QR.')
        if booking.final_fare is not None and row.amount!=booking.final_fare:raise ValidationError({'detail':'Fare changed after QR creation. Contact support before paying.'})
        return Response(payment_payload(row,request.user))

    def post(self,request,booking_id):
        try:
            with transaction.atomic():
                booking=participant(request,booking_id,lock=True)
                if not booking.driver_id or not booking.driver.is_active:raise ValidationError({'detail':'The assigned receiving account is unavailable. Contact support before paying.'})
                if booking.status!='COMPLETED' or booking.final_fare is None:
                    raise ValidationError({'detail':'UPI QR is generated only after the final trip fare is available.'})
                if booking.cash_received_at:
                    raise ValidationError({'detail':'Cash was already recorded. Do not pay twice.'})
                if booking.final_fare<=0:raise ValidationError({'detail':'No positive fare is due; no QR payment is required.'})
                row=DirectUPIPayment.objects.filter(booking=booking).first()
                if row:
                    if row.amount!=booking.final_fare:raise ValidationError({'detail':'Fare changed after QR creation. Contact support before paying.'})
                    return Response(payment_payload(row,request.user))
                profile=DriverUPIProfile.objects.filter(driver=booking.driver,active=True).first()
                if not profile or not profile.qr_storage_key:
                    raise ValidationError({'detail':'The assigned driver has not configured an active UPI ID + matching QR. Cash remains available.'})
                ref='DM'+str(booking.pk)+'-'+secrets.token_hex(8).upper()
                payload=make_payload(profile.upi_id,profile.payee_name,booking.final_fare,ref,booking.pk)
                row=DirectUPIPayment.objects.create(booking=booking,driver=booking.driver,receiver_upi_id=profile.upi_id,
                    receiver_name=profile.payee_name,profile_version=profile.version,amount=booking.final_fare,
                    qr_payload=payload,reference=ref)
                PaymentAudit.objects.create(payment=row,actor=request.user,action='QR_CREATED',note='Final-fare UPI URI generated. No bank transaction performed.')
        except IntegrityError:
            return Response({'detail':'Payment request is being created. Refresh instead of paying twice.'},status=409)
        except OperationalError as error:
            if 'locked' not in str(error).lower():raise
            return Response({'detail':'Payment request is busy. Refresh and retry.'},status=409)
        return Response(payment_payload(row,request.user),status=201)


class TripQRImageView(PaymentView):
    def get(self,request,booking_id):
        booking=participant(request,booking_id)
        row=DirectUPIPayment.objects.filter(booking=booking).first()
        if not row:raise NotFound('Generate the final-fare request first.')
        if row.status in ['CONFIRMED','CANCELLED'] or booking.cash_received_at:
            raise ValidationError({'detail':'This request is already confirmed/closed in the app. Do not pay again.'})
        if booking.final_fare!=row.amount:raise ValidationError({'detail':'Fare mismatch. Contact support before using this QR.'})
        response=FileResponse(io.BytesIO(png(row.qr_payload)),content_type='image/png',as_attachment=False,filename=f'DriveMate-UPI-{booking.pk}.png')
        response['Cache-Control']='private, no-store'
        return response


class ReportPaymentView(PaymentView):
    def post(self,request,booking_id):
        with transaction.atomic():
            booking=participant(request,booking_id,lock=True)
            if request.user.pk!=booking.customer_id:raise PermissionDenied('Only the customer can report this payment.')
            row=DirectUPIPayment.objects.select_for_update().filter(booking=booking).first()
            if not row:raise NotFound('Generate the payment request first.')
            if row.status in ['CONFIRMED','CANCELLED'] or booking.cash_received_at:
                raise ValidationError({'detail':'This request is already confirmed/closed. Do not pay again.'})
            if row.amount!=booking.final_fare:raise ValidationError({'detail':'Fare mismatch. Contact support.'})
            ref=reference(request.data.get('reference'))
            if row.status=='REPORTED' and row.customer_reference==ref:
                return Response(payment_payload(row,request.user))
            row.customer_reference=ref;row.reported_at=timezone.now();row.status='REPORTED';row.review_note=''
            row.save(update_fields=['customer_reference','reported_at','status','review_note','updated_at'])
            PaymentAudit.objects.create(payment=row,actor=request.user,action='CUSTOMER_REPORTED',note=f'Reference reported by customer: {ref}. Not bank-verified.')
            notify(booking.driver,'UPI payment reported',f'Booking #{booking.pk}: check your own bank/UPI credit and exact INR {row.amount} before confirming.','UPI_REPORTED',booking)
        return Response(payment_payload(row,request.user))


class ReviewPaymentView(PaymentView):
    def post(self,request,booking_id):
        require_role(request.user,'DRIVER')
        try:
            with transaction.atomic():
                booking=participant(request,booking_id,lock=True)
                if booking.driver_id!=request.user.pk:raise PermissionDenied('Only the assigned driver can confirm receipt.')
                if booking.status!='COMPLETED':raise ValidationError({'detail':'Only a completed trip can record payment receipt.'})
                row=DirectUPIPayment.objects.select_for_update().filter(booking=booking).first()
                if not row:raise NotFound('No UPI request found.')
                action=str(request.data.get('action',''))
                if action not in ['confirm','reject']:raise ValidationError({'detail':'Choose confirm or reject.'})
                if row.status=='CONFIRMED':return Response(payment_payload(row,request.user))
                if row.status=='CANCELLED' or booking.cash_received_at:raise ValidationError({'detail':'This request is closed or already paid in cash.'})
                note=str(request.data.get('note','')).strip()[:500]
                if action=='reject':
                    if row.status!='REPORTED' or len(note)<3:raise ValidationError({'detail':'A reported payment and a rejection reason are required.'})
                    row.status='REJECTED';row.review_note=note;row.reviewed_at=timezone.now()
                    row.save(update_fields=['status','review_note','reviewed_at','updated_at'])
                    PaymentAudit.objects.create(payment=row,actor=request.user,action='DRIVER_REJECTED',note=note)
                    notify(booking.customer,'UPI not confirmed',f'Booking #{booking.pk}: {note}. Check your payment app; do not pay twice without checking.','UPI_REJECTED',booking)
                    return Response(payment_payload(row,request.user))
                checked=serializers.BooleanField().run_validation(request.data.get('checked_bank',False))
                if checked is not True:raise ValidationError({'detail':'Check the actual credit in your bank/UPI app first. A screenshot or typed UTR is not proof.'})
                amount=serializers.DecimalField(max_digits=9,decimal_places=2,min_value=Decimal('0.01')).run_validation(request.data.get('received_amount'))
                if amount!=row.amount or booking.final_fare!=row.amount:
                    raise ValidationError({'received_amount':'Amount does not match the final fare. The booking remains unpaid; contact support for partial/wrong payments.'})
                bank_ref=reference(request.data.get('bank_reference'))
                duplicate=DirectUPIPayment.objects.filter(status='CONFIRMED',bank_reference=bank_ref).exclude(pk=row.pk)
                if duplicate.exists():raise ValidationError({'bank_reference':'This confirmed bank reference is already recorded for another trip.'})
                now=timezone.now();row.status='CONFIRMED';row.bank_reference=bank_ref;row.received_amount=amount
                row.confirmed_at=now;row.reviewed_at=now;row.review_note=note
                row.save(update_fields=['status','bank_reference','received_amount','confirmed_at','reviewed_at','review_note','updated_at'])
                PaymentAudit.objects.create(payment=row,actor=request.user,action='DRIVER_CONFIRMED',note=f'Driver asserted actual INR {amount} received; reference {bank_ref}. No independent bank/gateway verification.')
                booking.add_event('NOTE',f'Driver manually confirmed direct UPI: INR {amount}. No gateway/bank verification.',request.user)
                notify(booking.customer,'UPI received - driver confirmed',f'Booking #{booking.pk}: driver manually recorded INR {amount} received. Receipt is available.','UPI_CONFIRMED',booking)
                from hub.models import Preferences
                pref=Preferences.objects.filter(user=booking.customer).first()
                if not pref or pref.email_receipts:
                    from rides.enhanced_views import email_cash_receipt
                    transaction.on_commit(lambda:email_cash_receipt(booking.pk))
        except IntegrityError:
            return Response({'detail':'Reference/payment was already confirmed. Refresh; do not pay again.'},status=409)
        except OperationalError as error:
            if 'locked' not in str(error).lower():raise
            return Response({'detail':'Payment is being updated. Refresh and retry.'},status=409)
        return Response(payment_payload(row,request.user))


class CancelRequestView(PaymentView):
    def post(self,request,booking_id):
        with transaction.atomic():
            booking=participant(request,booking_id,lock=True)
            row=DirectUPIPayment.objects.select_for_update().filter(booking=booking).first()
            if not row:raise NotFound('No UPI request.')
            if row.status=='CANCELLED':return Response(payment_payload(row,request.user))
            if row.status not in ['CREATED','REJECTED']:raise ValidationError({'detail':'Resolve the reported/confirmed payment first. Do not collect twice.'})
            if serializers.BooleanField().run_validation(request.data.get('checked_no_payment',False)) is not True:
                raise ValidationError({'detail':'Confirm no payment was made/received before switching to cash.'})
            row.status='CANCELLED';row.save(update_fields=['status','updated_at'])
            PaymentAudit.objects.create(payment=row,actor=request.user,action='CLOSED_IN_APP',note='Closed by participant after checking no payment. Old personal QR images remain payable at bank; not a bank cancellation/refund.')
        return Response(payment_payload(row,request.user))
