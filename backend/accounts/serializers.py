"""Input validation for the authentication endpoints.

All validation lives on the server. The Flutter app validates for a fast
experience, but the backend never trusts those values.
"""

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers

from .models import User

# Public signup may only create these two roles. ADMIN accounts are created by
# staff (Django createsuperuser / admin panel), never through this endpoint.
PUBLIC_ROLES = [User.Role.CUSTOMER, User.Role.DRIVER]


def normalise_phone(value: str) -> str:
    return ''.join(character for character in value if character.isdigit() or character == '+')


class RegisterSerializer(serializers.Serializer):
    full_name = serializers.CharField(max_length=120)
    email = serializers.EmailField()
    phone = serializers.CharField(max_length=20)
    password = serializers.CharField(write_only=True, min_length=8, max_length=128)
    confirm_password = serializers.CharField(write_only=True, required=False, allow_blank=True)
    role = serializers.ChoiceField(choices=PUBLIC_ROLES, default=User.Role.CUSTOMER)

    def validate_full_name(self, value):
        name = ' '.join(value.split())
        if len(name) < 2:
            raise serializers.ValidationError('Enter your full name.')
        if not any(character.isalpha() for character in name):
            raise serializers.ValidationError('Enter a valid name.')
        return name

    def validate_email(self, value):
        email = value.strip().lower()
        if User.objects.filter(email__iexact=email).exists():
            raise serializers.ValidationError('An account already exists with this email address.')
        return email

    def validate_phone(self, value):
        phone = normalise_phone(value.strip())
        digits = phone.lstrip('+')
        if not digits.isdigit() or not (8 <= len(digits) <= 15):
            raise serializers.ValidationError('Enter a valid mobile number (8 to 15 digits).')
        if User.objects.filter(phone=phone).exists():
            raise serializers.ValidationError('This mobile number is already registered.')
        return phone

    def validate(self, attrs):
        password = attrs.get('password', '')
        confirm = attrs.get('confirm_password')
        if confirm and password != confirm:
            raise serializers.ValidationError({'confirm_password': 'Passwords do not match.'})
        user = User(email=attrs.get('email', ''), full_name=attrs.get('full_name', ''))
        try:
            validate_password(password, user=user)
        except DjangoValidationError as error:
            raise serializers.ValidationError({'password': list(error.messages)})
        return attrs


class LoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(max_length=254)
    password = serializers.CharField(write_only=True)
    role = serializers.ChoiceField(choices=User.Role.choices, default=User.Role.CUSTOMER)

    def validate_identifier(self, value):
        return value.strip()


class OTPRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate_email(self, value):
        return value.strip().lower()


class OTPVerifySerializer(OTPRequestSerializer):
    otp = serializers.CharField(min_length=4, max_length=8)


class PasswordResetConfirmSerializer(OTPRequestSerializer):
    otp = serializers.CharField(min_length=4, max_length=8)
    new_password = serializers.CharField(min_length=8, max_length=128)


class ConsentsSerializer(serializers.Serializer):
    consent_background_check = serializers.BooleanField()
    consent_terms = serializers.BooleanField()
    consent_data_accuracy = serializers.BooleanField()

    def validate(self, attrs):
        if not all([attrs['consent_background_check'], attrs['consent_terms'], attrs['consent_data_accuracy']]):
            raise serializers.ValidationError('All three consents are required to submit the application.')
        return attrs


class EmergencyContactSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=120)
    relationship = serializers.CharField(max_length=60, required=False, allow_blank=True)
    phone = serializers.CharField(max_length=20)
    is_primary = serializers.BooleanField(required=False, default=False)

    def validate_name(self, value):
        if len(value.strip()) < 2:
            raise serializers.ValidationError('Enter a contact name.')
        return value.strip()

    def validate_phone(self, value):
        phone = normalise_phone(value.strip())
        digits = phone.lstrip('+')
        if not digits.isdigit() or not (8 <= len(digits) <= 15):
            raise serializers.ValidationError('Enter a valid phone number.')
        return phone


class ReviewDecisionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(
        choices=['approve', 'reject', 'suspend', 'reactivate', 'inactive', 'under_review', 'pending_review']
    )
    reason = serializers.CharField(max_length=500, required=False, allow_blank=True)

    def validate(self, attrs):
        if attrs['action'] in ('reject', 'suspend') and not attrs.get('reason', '').strip():
            raise serializers.ValidationError({'reason': 'A reason is required when rejecting or suspending.'})
        return attrs
