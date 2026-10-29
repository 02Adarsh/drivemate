import hashlib
import secrets
from django.conf import settings
from django.contrib.auth.hashers import check_password
from django.core.mail import send_mail
from rest_framework.exceptions import APIException


class EmailUnavailable(APIException):
    status_code = 503
    default_detail = 'Email delivery is not configured or temporarily unavailable. Check backend SMTP settings.'
    default_code = 'email_unavailable'


def ensure_email_ready():
    if settings.EMAIL_BACKEND.endswith(('console.EmailBackend','dummy.EmailBackend')):
        raise EmailUnavailable('Email delivery is not configured. Configure SMTP; no email was sent.')


def deliver(subject, body, email):
    ensure_email_ready()
    try:
        if send_mail(subject, body, settings.DEFAULT_FROM_EMAIL, [email], fail_silently=False) != 1:
            raise EmailUnavailable()
    except EmailUnavailable:
        raise
    except Exception:
        raise EmailUnavailable('Email could not be delivered. Check SMTP credentials/connectivity on the backend and retry.')


def code_matches(stored, value):
    # Existing unexpired v8 SHA-256 codes remain usable during the upgrade.
    if len(stored)==64 and '$' not in stored:
        return secrets.compare_digest(stored,hashlib.sha256(str(value).encode()).hexdigest())
    return check_password(str(value),stored)
