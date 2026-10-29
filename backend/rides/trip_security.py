"""Trip-start OTP is mandatory, participant-scoped and never sent to the driver.

The hash checks guesses; authenticated encryption allows the owning customer to
read their current code again. Keep DJANGO_SECRET_KEY private and stable.
"""
import base64
import hashlib
import logging
import secrets
from datetime import timedelta

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.core.mail import send_mail
from django.utils import timezone

from .models import TripStartCode

logger = logging.getLogger(__name__)


def cipher():
    key = hashlib.sha256(('drivemate-trip-code-v9:' + settings.SECRET_KEY).encode()).digest()
    return Fernet(base64.urlsafe_b64encode(key))


def issue_start_code(booking):
    old = TripStartCode.objects.filter(booking=booking).first()
    previous = reveal_code(old) if old else None
    code = f'{secrets.randbelow(1000000):06d}'
    while code == previous:
        code = f'{secrets.randbelow(1000000):06d}'
    row, _ = TripStartCode.objects.update_or_create(booking=booking, defaults={
        'code_hash': make_password(code), 'code_ciphertext': cipher().encrypt(code.encode()).decode(),
        'expires_at': timezone.now() + timedelta(minutes=20), 'attempts': 0,
        'locked_until': None, 'consumed_at': None, 'email_sent': False,
    })
    return row


def reveal_code(row):
    try:
        return cipher().decrypt(row.code_ciphertext.encode()).decode()
    except InvalidToken:
        return None


def email_start_code(booking_id):
    """Best-effort email after assignment; code remains available in customer's app.

    Never log the code or expose SMTP errors/credentials to the driver. An email
    failure does not undo the booking assignment.
    """
    from .models import Booking
    booking = Booking.objects.select_related('customer').filter(pk=booking_id).first()
    if not booking:
        return
    row = TripStartCode.objects.filter(booking=booking, consumed_at__isnull=True).first()
    if not row:
        return
    code = reveal_code(row)
    backend = settings.EMAIL_BACKEND
    if not code or backend.endswith(('console.EmailBackend', 'dummy.EmailBackend')):
        return
    try:
        sent = send_mail(
            f'DriveMate trip #{booking.pk}: your start code',
            f'Your trip-start code is {code}. Share it with your assigned driver only when you meet. '
            'The app cannot start the trip until the correct code is verified. '
            'This code expires in 20 minutes; regenerate it in your trip screen if needed.',
            settings.DEFAULT_FROM_EMAIL, [booking.customer.email], fail_silently=False,
        )
        row.email_sent = sent == 1
        row.save(update_fields=['email_sent'])
    except Exception:
        logger.warning('Trip-start email delivery failed for booking %s; customer can use the protected app screen.', booking.pk)


def check_start_code(row, value):
    now = timezone.now()
    if row.consumed_at:
        return 'This code has already been used.'
    if row.locked_until and row.locked_until > now:
        return 'Too many guesses. Wait before trying again.'
    if row.expires_at <= now:
        return 'Code expired. Ask the customer to regenerate it in their trip screen.'
    row.attempts += 1
    if not check_password(str(value), row.code_hash):
        if row.attempts >= 5:
            row.locked_until = now + timedelta(minutes=5)
        row.save(update_fields=['attempts', 'locked_until'])
        return 'Incorrect trip-start code.'
    row.consumed_at = now
    row.save(update_fields=['attempts', 'consumed_at'])
    return None
