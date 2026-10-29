"""Account tools. Every row is owned; these are not fake wallet balances."""
import secrets
from decimal import Decimal
from django.conf import settings
from django.db import models


def invite_code():
    return secrets.token_hex(4).upper()


class Preferences(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='preferences')
    language = models.CharField(max_length=2, default='en')
    theme = models.CharField(max_length=8, default='light')
    trip_updates = models.BooleanField(default=True)
    email_receipts = models.BooleanField(default=True)
    marketing = models.BooleanField(default=False)
    large_text = models.BooleanField(default=False)
    invite_code = models.CharField(max_length=12, unique=True, default=invite_code)
    referred_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='referred_accounts')


class SavedPlace(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    label = models.CharField(max_length=60)
    address = models.CharField(max_length=240)
    latitude = models.DecimalField(max_digits=10, decimal_places=7)
    longitude = models.DecimalField(max_digits=10, decimal_places=7)
    kind = models.CharField(max_length=8, default='OTHER')
    created_at = models.DateTimeField(auto_now_add=True)


class Contact(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20)
    relationship = models.CharField(max_length=40, blank=True)
    emergency = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)


class BusinessProfile(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    company = models.CharField(max_length=120)
    department = models.CharField(max_length=80, blank=True)
    employee_id = models.CharField(max_length=60, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class SupportTicket(models.Model):
    owner = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    booking = models.ForeignKey('rides.Booking', on_delete=models.SET_NULL, null=True, blank=True)
    category = models.CharField(max_length=24, default='GENERAL')
    subject = models.CharField(max_length=120)
    description = models.CharField(max_length=2000)
    status = models.CharField(max_length=12, default='OPEN')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class SupportMessage(models.Model):
    ticket = models.ForeignKey(SupportTicket, on_delete=models.CASCADE, related_name='messages')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)
    text = models.CharField(max_length=2000)
    created_at = models.DateTimeField(auto_now_add=True)


class PromoCode(models.Model):
    code = models.CharField(max_length=32, unique=True)
    description = models.CharField(max_length=240)
    amount = models.DecimalField(max_digits=8, decimal_places=2, default=Decimal('0'))
    active = models.BooleanField(default=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    max_redemptions = models.PositiveIntegerField(default=100)


class ClaimedPromo(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    promo = models.ForeignKey(PromoCode, on_delete=models.CASCADE)
    used_booking = models.OneToOneField('rides.Booking', on_delete=models.SET_NULL, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['user', 'promo'], name='one_promo_per_customer')]


class EmailChange(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    email = models.EmailField()
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
