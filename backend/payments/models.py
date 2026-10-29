"""Personal direct-UPI records. No gateway/bank verification is implied."""
import uuid
from django.conf import settings
from django.db import models
from django.db.models import Q


class DriverUPIProfile(models.Model):
    driver=models.OneToOneField(settings.AUTH_USER_MODEL,on_delete=models.CASCADE,related_name='upi_profile')
    upi_id=models.CharField(max_length=256)
    payee_name=models.CharField(max_length=120)
    uploaded_payee_hint=models.CharField(max_length=120,blank=True)
    qr_storage_key=models.CharField(max_length=500)
    qr_sha256=models.CharField(max_length=64)
    active=models.BooleanField(default=True)
    version=models.PositiveIntegerField(default=1)
    ownership_attested_at=models.DateTimeField()
    updated_at=models.DateTimeField(auto_now=True)


class DirectUPIPayment(models.Model):
    class Status(models.TextChoices):
        CREATED='CREATED','Awaiting payment'
        REPORTED='REPORTED','Customer reported payment - not confirmed'
        REJECTED='REJECTED','Driver could not confirm'
        CONFIRMED='CONFIRMED','UPI received - manually confirmed by driver'
        CANCELLED='CANCELLED','Closed in app - not cancelled at bank'
    id=models.UUIDField(primary_key=True,default=uuid.uuid4,editable=False)
    booking=models.OneToOneField('rides.Booking',on_delete=models.PROTECT,related_name='direct_upi')
    driver=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT,related_name='upi_payment_records')
    receiver_upi_id=models.CharField(max_length=256)
    receiver_name=models.CharField(max_length=120)
    profile_version=models.PositiveIntegerField()
    amount=models.DecimalField(max_digits=9,decimal_places=2)
    currency=models.CharField(max_length=3,default='INR')
    qr_payload=models.TextField()
    reference=models.CharField(max_length=48,unique=True)
    status=models.CharField(max_length=12,choices=Status.choices,default=Status.CREATED)
    customer_reference=models.CharField(max_length=64,blank=True)
    reported_at=models.DateTimeField(null=True,blank=True)
    bank_reference=models.CharField(max_length=64,blank=True)
    received_amount=models.DecimalField(max_digits=9,decimal_places=2,null=True,blank=True)
    confirmed_at=models.DateTimeField(null=True,blank=True)
    reviewed_at=models.DateTimeField(null=True,blank=True)
    review_note=models.CharField(max_length=500,blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    updated_at=models.DateTimeField(auto_now=True)
    class Meta:
        constraints=[models.UniqueConstraint(fields=['bank_reference'],condition=Q(status='CONFIRMED') & ~Q(bank_reference=''),name='unique_confirmed_upi_bank_ref')]


class PaymentAudit(models.Model):
    payment=models.ForeignKey(DirectUPIPayment,on_delete=models.CASCADE,related_name='audit')
    actor=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.SET_NULL,null=True)
    action=models.CharField(max_length=32)
    note=models.CharField(max_length=500,blank=True)
    created_at=models.DateTimeField(auto_now_add=True)
    class Meta:
        ordering=['created_at','id']


class DriverUPIChange(models.Model):
    driver=models.ForeignKey(settings.AUTH_USER_MODEL,on_delete=models.PROTECT)
    previous_upi_id=models.CharField(max_length=256,blank=True)
    new_upi_id=models.CharField(max_length=256)
    profile_version=models.PositiveIntegerField()
    qr_sha256=models.CharField(max_length=64)
    created_at=models.DateTimeField(auto_now_add=True)
