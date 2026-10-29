"""Authentication, profile and driver-application APIs (prefix: /api/auth/).

Everything that decides "what happens next" is calculated here on the server:
  * which registration step is incomplete,
  * whether an application may move to admin review,
  * and what the driver may do next.
"""

import hashlib
import secrets
from datetime import date, timedelta

from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.hashers import make_password
from django.db import transaction
from django.core.mail import send_mail
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.throttling import ScopedRateThrottle
from .email_codes import ensure_email_ready, deliver, code_matches
from rest_framework_simplejwt.tokens import RefreshToken

from .models import (
    CustomerProfile,
    DriverDocument,
    DriverEmergencyContact,
    DriverProfile,
    DriverTraining,
    EmailOTP,
    User,
)
from .progress import (
    MIN_DRIVER_AGE,
    is_valid_pincode,
    REQUIRED_DOCUMENTS,
    REQUIRED_TRAINING,
    TRAINING_CONTENT,
    application_steps,
    calculate_age,
    consents_complete,
    documents_complete,
    driver_progress,
    ensure_training_rows,
    personal_profile_complete,
    driving_details_complete,
    sync_driver_status,
)
from .serializers import (
    ConsentsSerializer,
    EmergencyContactSerializer,
    LoginSerializer,
    RegisterSerializer,
)

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

DRIVER_TEXT_FIELDS = (
    'address',
    'state',
    'city',
    'pincode',
    'service_area',
    'emergency_contact_name',
    'emergency_contact_phone',
    'languages',
    'introduction',
    'licence_number',
)

DRIVER_CAPABILITY_FIELDS = (
    'manual_transmission',
    'automatic_transmission',
    'sedan',
    'suv',
    'luxury',
    'highway',
    'night_driving',
    'outstation',
)

CUSTOMER_TEXT_FIELDS = ('address', 'state', 'city', 'pincode', 'emergency_contact_name', 'emergency_contact_phone')


def user_payload(user: User) -> dict:
    return {
        'id': user.id,
        'name': user.full_name,
        'email': user.email,
        'phone': user.phone,
        'role': user.role,
        'email_verified': user.email_verified,
        'has_profile_photo': bool(user.profile_photo_key),
    }


def token_data(user: User) -> dict:
    """Login/OTP response. Includes the server-calculated next step for drivers."""
    refresh = RefreshToken.for_user(user)
    payload = {
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'user': user_payload(user),
    }
    if user.role == User.Role.DRIVER:
        profile, _ = DriverProfile.objects.get_or_create(user=user)
        ensure_training_rows(profile)
        progress = driver_progress(profile)
        payload['driver'] = progress
        payload['user']['profile_complete'] = progress['profile_complete']
        payload['user']['driver_documents_complete'] = progress['documents_complete']
        payload['user']['next_step'] = progress['next_step']
    elif user.role == User.Role.CUSTOMER:
        profile, _ = CustomerProfile.objects.get_or_create(user=user)
        payload['user']['profile_complete'] = profile.profile_complete
        payload['user']['next_step'] = 'DASHBOARD' if profile.profile_complete else 'PROFILE'
    else:
        payload['user']['profile_complete'] = True
        payload['user']['next_step'] = 'ADMIN_DASHBOARD'
    return payload


def issue_otp(user: User, purpose: str = 'VERIFY_EMAIL') -> None:
    ensure_email_ready()
    code = f'{secrets.randbelow(1000000):06d}'
    # A slow salted hash, not plaintext; purposes cannot be cross-used.
    deliver('Your DriveMate verification code',
            f'Your DriveMate {purpose.lower().replace("_", " ")} code is {code}. '
            f'It expires in {settings.OTP_EXPIRY_MINUTES} minutes. Never share account codes.', user.email)
    EmailOTP.objects.filter(user=user,purpose=purpose,consumed_at__isnull=True).update(consumed_at=timezone.now())
    EmailOTP.objects.create(user=user,purpose=purpose,code_hash=make_password(code),
                            expires_at=timezone.now()+timedelta(minutes=settings.OTP_EXPIRY_MINUTES))


def missing_step_fields(profile: DriverProfile, step: str) -> list[str]:
    """Human-readable list of what is still missing in a registration step."""
    missing: list[str] = []
    if step == 'PERSONAL':
        if not profile.user.profile_photo_key:
            missing.append('Profile photo')
        age = calculate_age(profile.date_of_birth)
        if age is None:
            missing.append('Date of birth')
        elif age < MIN_DRIVER_AGE:
            missing.append(f'You must be at least {MIN_DRIVER_AGE} years old')
        if not profile.address.strip():
            missing.append('Current address')
        if not profile.state.strip():
            missing.append('State')
        if not profile.city.strip():
            missing.append('City')
        if not is_valid_pincode(profile.pincode):
            missing.append('A valid 6-digit PIN code')
        if not profile.emergency_contact_name.strip():
            missing.append('Emergency contact name')
        if not profile.emergency_contact_phone.strip():
            missing.append('Emergency contact number')
        if not profile.languages.strip():
            missing.append('Languages known')
    elif step == 'DRIVING':
        if not profile.licence_number.strip():
            missing.append('Driving licence number')
        if not profile.licence_expiry:
            missing.append('Licence expiry date')
        elif profile.licence_expiry <= date.today():
            missing.append('A licence expiry date in the future')
        if profile.experience_years <= 0:
            missing.append('Driving experience in years')
        if not (profile.manual_transmission or profile.automatic_transmission):
            missing.append('Select at least one transmission type')
        if not (profile.sedan or profile.suv or profile.luxury):
            missing.append('Select at least one vehicle type you can drive')
    return missing


def driver_application_payload(profile: DriverProfile) -> dict:
    progress = driver_progress(profile)
    documents = [
        {
            'id': document.id,
            'document_type': document.document_type,
            'document_label': document.get_document_type_display(),
            'review_status': document.review_status,
            'rejection_reason': document.rejection_reason,
            'document_number': document.document_number,
            'expires_at': document.expires_at,
            'uploaded_at': document.uploaded_at,
            'is_required': document.document_type in REQUIRED_DOCUMENTS,
        }
        for document in profile.documents.order_by('document_type')
    ]
    training = [
        {
            'id': row.id,
            'module': row.module,
            'label': row.get_module_display(),
            'status': row.status,
            'is_required': row.module in REQUIRED_TRAINING,
            'completed_at': row.completed_at,
            'content': TRAINING_CONTENT.get(row.module, []),
        }
        for row in profile.training.order_by('id')
    ]
    return {
        'progress': progress,
        'steps': application_steps(profile),
        'documents': documents,
        'training': training,
        'consents': {
            'consent_background_check': profile.consent_background_check,
            'consent_terms': profile.consent_terms,
            'consent_data_accuracy': profile.consent_data_accuracy,
            'accepted_at': profile.consents_accepted_at,
        },
        'emergency_contacts': [
            {
                'id': contact.id,
                'name': contact.name,
                'relationship': contact.relationship,
                'phone': contact.phone,
                'is_primary': contact.is_primary,
            }
            for contact in profile.emergency_contacts.order_by('-is_primary', 'id')
        ],
        'review': {
            'submitted_at': profile.submitted_at,
            'reviewed_at': profile.reviewed_at,
            'approved_at': profile.approved_at,
            'rejection_reason': profile.rejection_reason,
        },
        'requirements': {
            'required_documents': list(REQUIRED_DOCUMENTS),
            'required_training': list(REQUIRED_TRAINING),
        },
    }


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

class RegisterView(APIView):
    """Step 1 of registration: create the account (role is CUSTOMER or DRIVER)."""

    permission_classes = [AllowAny]
    throttle_scope = 'anon'

    @transaction.atomic
    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        ensure_email_ready()
        user = User(
            email=data['email'],
            full_name=data['full_name'],
            phone=data['phone'],
            role=data['role'],
        )
        user.set_password(data['password'])
        user.save()

        if user.role == User.Role.DRIVER:
            profile = DriverProfile.objects.create(user=user)
            ensure_training_rows(profile)
        else:
            CustomerProfile.objects.create(user=user)

        referral = str(request.data.get('referral_code','')).strip().upper()
        if referral:
            from hub.models import Preferences
            inviter = Preferences.objects.filter(invite_code=referral,user__is_active=True,user__email_verified=True).first()
            if not inviter:
                from rest_framework.exceptions import ValidationError
                raise ValidationError({'referral_code':'Invitation code is invalid.'})
            Preferences.objects.create(user=user,referred_by=inviter.user)
        issue_otp(user)
        return Response(
            {
                'message': 'Account created. Check your email inbox for the 6-digit verification code.',
                'email': user.email,
                'role': user.role,
                'next_step': 'VERIFY_OTP',
            },
            status=status.HTTP_201_CREATED,
        )


class VerifyOTPView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    @transaction.atomic
    def post(self, request):
        email = str(request.data.get('email','')).lower().strip()
        code = str(request.data.get('otp','')).strip()
        user = User.objects.filter(email=email,is_active=True).first()
        if not user:
            return Response({'detail':'Account/code not found.'},status=400)
        otp = EmailOTP.objects.select_for_update().filter(user=user,consumed_at__isnull=True,
                    purpose__in=['VERIFY_EMAIL','LOGIN']).order_by('-created_at').first()
        # Never mint a token merely because an email is already verified.
        if not otp or otp.expires_at <= timezone.now():
            return Response({'detail':'Code expired or already used. Request a new code.'},status=400)
        if otp.attempts >= settings.OTP_MAX_ATTEMPTS:
            return Response({'detail':'Too many attempts. Request a new code.'},status=429)
        otp.attempts += 1
        otp.save(update_fields=['attempts'])
        if not code_matches(otp.code_hash,code):
            return Response({'detail':'Incorrect verification code.'},status=400)
        otp.consumed_at = timezone.now()
        otp.save(update_fields=['consumed_at'])
        user.email_verified = True
        user.last_seen_at = timezone.now()
        user.save(update_fields=['email_verified','last_seen_at'])
        return Response(token_data(user))


class LoginOTPRequestView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self,request):
        from rest_framework import serializers
        email = serializers.EmailField().run_validation(request.data.get('email','')).lower()
        ensure_email_ready()
        user = User.objects.filter(email__iexact=email,is_active=True).first()
        if user:
            issue_otp(user,purpose='LOGIN' if user.email_verified else 'VERIFY_EMAIL')
        return Response({'message':'If this account exists, a code has been sent to its email.','email':email})


class ResendOTPView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = 'otp'

    def post(self, request):
        try:
            user = User.objects.get(email=str(request.data.get('email', '')).lower().strip())
        except User.DoesNotExist:
            return Response({'detail': 'Account not found.'}, status=status.HTTP_404_NOT_FOUND)
        if user.email_verified:
            return Response({'detail': 'Email is already verified.'}, status=status.HTTP_400_BAD_REQUEST)
        issue_otp(user)
        return Response({'message': 'A new verification code has been sent.'})


class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        identifier = serializer.validated_data['identifier']
        requested_role = serializer.validated_data['role']

        if '@' in identifier:
            candidate = User.objects.filter(email__iexact=identifier).first()
        else:
            phone = ''.join(character for character in identifier if character.isdigit() or character == '+')
            candidate = User.objects.filter(phone=phone).first()

        user = (
            authenticate(request, email=candidate.email, password=serializer.validated_data['password'])
            if candidate
            else None
        )
        if not user:
            return Response({'detail': 'Email/phone or password is incorrect.'}, status=status.HTTP_401_UNAUTHORIZED)
        if user.role != requested_role:
            return Response({'detail': 'This account is registered as a different role.'}, status=status.HTTP_403_FORBIDDEN)
        if not user.email_verified:
            issue_otp(user)
            return Response(
                {'detail': 'Verify your email first. A new code has been sent.', 'email': user.email, 'needs_verification': True},
                status=status.HTTP_403_FORBIDDEN,
            )
        if user.role == User.Role.ADMIN and not user.is_staff:
            return Response({'detail': 'Admin access is not enabled for this account.'}, status=status.HTTP_403_FORBIDDEN)
        if not user.is_active:
            return Response({'detail': 'This account is disabled. Contact support.'}, status=status.HTTP_403_FORBIDDEN)

        user.last_seen_at = timezone.now()
        user.save(update_fields=['last_seen_at'])
        return Response(token_data(user))


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        payload = {'user': user_payload(request.user)}
        if request.user.role == User.Role.DRIVER:
            profile, _ = DriverProfile.objects.get_or_create(user=request.user)
            ensure_training_rows(profile)
            payload['driver'] = driver_progress(profile)
        return Response(payload)


# ---------------------------------------------------------------------------
# Profile
# ---------------------------------------------------------------------------

class ProfileView(APIView):
    """GET the profile, PUT to save one registration step.

    Send `step: PERSONAL` or `step: DRIVING` to have the server verify that the
    whole step is complete before the app is allowed to move on. The app cannot
    skip a step by simply not calling the API - the status stays INCOMPLETE and
    `next_step` keeps pointing at the unfinished step.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        if user.role == User.Role.DRIVER:
            profile, _ = DriverProfile.objects.get_or_create(user=user)
            data = {
                'date_of_birth': profile.date_of_birth,
                'address': profile.address,
                'state': profile.state,
                'city': profile.city,
                'pincode': profile.pincode,
                'service_area': profile.service_area,
                'emergency_contact_name': profile.emergency_contact_name,
                'emergency_contact_phone': profile.emergency_contact_phone,
                'languages': profile.languages,
                'introduction': profile.introduction,
                'licence_number': profile.licence_number,
                'licence_expiry': profile.licence_expiry,
                'experience_years': profile.experience_years,
                **{field: getattr(profile, field) for field in DRIVER_CAPABILITY_FIELDS},
            }
            return Response(
                {
                    'name': user.full_name,
                    'email': user.email,
                    'phone': user.phone,
                    'role': user.role,
                    'has_profile_photo': bool(user.profile_photo_key),
                    'profile': data,
                    'progress': driver_progress(profile),
                }
            )
        if user.role == User.Role.CUSTOMER:
            # No request data to validate on a GET - the customer's own profile
            # is simply returned (pincode rules live in `put`).
            profile, _ = CustomerProfile.objects.get_or_create(user=user)
            return Response(
                {
                    'name': user.full_name,
                    'email': user.email,
                    'phone': user.phone,
                    'role': user.role,
                    'has_profile_photo': bool(user.profile_photo_key),
                    'profile': {
                        'address': profile.address,
                        'state': profile.state,
                        'city': profile.city,
                        'pincode': profile.pincode,
                        'emergency_contact_name': profile.emergency_contact_name,
                        'emergency_contact_phone': profile.emergency_contact_phone,
                        'profile_complete': profile.profile_complete,
                    },
                }
            )
        return Response({'detail': 'Profile editing is not available for this role.'}, status=status.HTTP_403_FORBIDDEN)

    def put(self, request):
        user = request.user
        data = request.data
        step = str(data.get('step', '')).upper()

        if 'full_name' in data and str(data['full_name']).strip():
            user.full_name = ' '.join(str(data['full_name']).split())
            user.save(update_fields=['full_name'])

        if user.role == User.Role.DRIVER:
            profile, _ = DriverProfile.objects.get_or_create(user=user)

            for field in DRIVER_TEXT_FIELDS:
                if field in data:
                    setattr(profile, field, str(data[field]).strip())
            for field in DRIVER_CAPABILITY_FIELDS:
                if field in data:
                    setattr(profile, field, bool(data[field]))

            if 'experience_years' in data:
                try:
                    profile.experience_years = max(0, min(60, int(data['experience_years'])))
                except (TypeError, ValueError):
                    return Response({'detail': 'Driving experience must be a number of years.'}, status=status.HTTP_400_BAD_REQUEST)

            for field in ('date_of_birth', 'licence_expiry'):
                if field in data and data[field]:
                    try:
                        setattr(profile, field, date.fromisoformat(str(data[field])[:10]))
                    except ValueError:
                        return Response(
                            {'detail': 'Enter dates in YYYY-MM-DD format.'}, status=status.HTTP_400_BAD_REQUEST
                        )

            if 'pincode' in data and str(data['pincode']).strip() and not is_valid_pincode(str(data['pincode'])):
                return Response(
                    {'detail': 'Enter a valid 6-digit PIN code (it cannot start with 0).'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

            if step == 'PERSONAL':
                missing = missing_step_fields(profile, 'PERSONAL')
                if missing:
                    return Response(
                        {'detail': 'Complete every field before continuing.', 'missing_fields': missing},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
            if step == 'DRIVING':
                if not personal_profile_complete(profile):
                    return Response(
                        {
                            'detail': 'Complete step 2 (personal profile) before saving driving details.',
                            'missing_fields': missing_step_fields(profile, 'PERSONAL'),
                        },
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                missing = missing_step_fields(profile, 'DRIVING')
                if missing:
                    return Response(
                        {'detail': 'Complete every field before continuing.', 'missing_fields': missing},
                        status=status.HTTP_400_BAD_REQUEST,
                    )

            sync_driver_status(profile)
            return Response(
                {
                    'message': 'Driver details saved.',
                    'profile_complete': profile.profile_complete,
                    'verification_status': profile.verification_status,
                    'next_step': driver_progress(profile)['next_step'],
                }
            )

        if user.role == User.Role.CUSTOMER:
            profile, _ = CustomerProfile.objects.get_or_create(user=user)
            for field in CUSTOMER_TEXT_FIELDS:
                if field in data:
                    setattr(profile, field, str(data[field]).strip())
            profile.profile_complete = bool(
                profile.address.strip()
                and profile.state.strip()
                and profile.city.strip()
                and is_valid_pincode(profile.pincode)
                and profile.emergency_contact_name.strip()
                and profile.emergency_contact_phone.strip()
                and user.profile_photo_key
            )
            profile.save()
            missing = []
            if not user.profile_photo_key:
                missing.append('Profile photo')
            if not profile.address.strip():
                missing.append('Current address')
            if not profile.state.strip():
                missing.append('State')
            if not profile.city.strip():
                missing.append('City')
            if not is_valid_pincode(profile.pincode):
                missing.append('A valid 6-digit PIN code')
            if not profile.emergency_contact_name.strip():
                missing.append('Emergency contact name')
            if not profile.emergency_contact_phone.strip():
                missing.append('Emergency contact number')
            if step == 'PROFILE' and missing:
                return Response(
                    {'detail': 'Complete every field before continuing.', 'missing_fields': missing},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response({'message': 'Profile saved.', 'profile_complete': profile.profile_complete})

        return Response({'detail': 'Profile editing is not available for this role.'}, status=status.HTTP_403_FORBIDDEN)


# ---------------------------------------------------------------------------
# Driver application (steps 4 and 5)
# ---------------------------------------------------------------------------

class DriverApplicationView(APIView):
    """Everything the driver app needs to render the application + status screens."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Only drivers have a verification application.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        ensure_training_rows(profile)
        sync_driver_status(profile)
        return Response(driver_application_payload(profile))


class DriverConsentsView(APIView):
    """Step 4: background-check consent, terms and data-accuracy declaration."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Only drivers can submit these consents.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = ConsentsSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        profile.consent_background_check = True
        profile.consent_terms = True
        profile.consent_data_accuracy = True
        profile.consents_accepted_at = timezone.now()
        profile.save(update_fields=[
            'consent_background_check', 'consent_terms', 'consent_data_accuracy', 'consents_accepted_at', 'updated_at'
        ])
        sync_driver_status(profile)
        return Response({'message': 'Consents recorded.', 'progress': driver_progress(profile)})


class DriverTrainingView(APIView):
    """Training checklist. Module content is a placeholder until real training is added."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Training is available to drivers only.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        rows = ensure_training_rows(profile)
        return Response(
            {
                'modules': [
                    {
                        'id': row.id,
                        'module': row.module,
                        'label': row.get_module_display(),
                        'status': row.status,
                        'is_required': row.module in REQUIRED_TRAINING,
                        'completed_at': row.completed_at,
                        'content': TRAINING_CONTENT.get(row.module, []),
                    }
                    for row in rows
                ],
                'missing_required': driver_progress(profile)['missing_training'],
                'note': 'Prototype note: these modules are short acknowledgement summaries, not the final training content.',
            }
        )


class DriverTrainingCompleteView(APIView):
    """Mark a training module complete (development shortcut for testing the flow)."""

    permission_classes = [IsAuthenticated]

    def post(self, request, module):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Training is available to drivers only.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        ensure_training_rows(profile)
        row = profile.training.filter(module=str(module).upper()).first()
        if not row:
            return Response({'detail': 'Unknown training module.'}, status=status.HTTP_404_NOT_FOUND)
        row.status = DriverTraining.Status.COMPLETED
        row.completed_at = timezone.now()
        row.save(update_fields=['status', 'completed_at', 'updated_at'])
        sync_driver_status(profile)
        return Response(
            {
                'message': f'{row.get_module_display()} marked as completed.',
                'status': row.status,
                'progress': driver_progress(profile),
            }
        )


class EmergencyContactListCreateView(APIView):
    """Extra emergency contacts for a driver."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Only drivers have driver emergency contacts.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        return Response(
            {
                'primary': {
                    'name': profile.emergency_contact_name,
                    'phone': profile.emergency_contact_phone,
                },
                'contacts': [
                    {
                        'id': contact.id,
                        'name': contact.name,
                        'relationship': contact.relationship,
                        'phone': contact.phone,
                        'is_primary': contact.is_primary,
                    }
                    for contact in profile.emergency_contacts.order_by('id')
                ],
            }
        )

    def post(self, request):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Only drivers can add driver emergency contacts.'}, status=status.HTTP_403_FORBIDDEN)
        serializer = EmergencyContactSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        contact = DriverEmergencyContact.objects.create(driver=profile, **serializer.validated_data)
        return Response(
            {'id': contact.id, 'name': contact.name, 'phone': contact.phone, 'message': 'Emergency contact saved.'},
            status=status.HTTP_201_CREATED,
        )


class EmergencyContactDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, contact_id):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Only drivers can remove driver emergency contacts.'}, status=status.HTTP_403_FORBIDDEN)
        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        deleted, _ = profile.emergency_contacts.filter(pk=contact_id).delete()
        if not deleted:
            return Response({'detail': 'Contact not found.'}, status=status.HTTP_404_NOT_FOUND)
        return Response({'message': 'Emergency contact removed.'})


class SessionRefreshView(APIView):
    """Pinned-client session refresh. Disabled/password-changed users stay out."""
    permission_classes = [AllowAny]

    def post(self,request):
        from rest_framework_simplejwt.exceptions import TokenError
        from rest_framework_simplejwt.settings import api_settings
        from rest_framework_simplejwt.utils import get_md5_hash_password
        try:
            token=RefreshToken(str(request.data.get('refresh','')))
            user=User.objects.filter(pk=token[api_settings.USER_ID_CLAIM],is_active=True).first()
            if not user or token.get(api_settings.REVOKE_TOKEN_CLAIM)!=get_md5_hash_password(user.password):
                return Response({'detail':'Session expired or revoked. Sign in again.'},status=401)
            return Response({'access':str(token.access_token)})
        except (TokenError,KeyError,ValueError):
            return Response({'detail':'Invalid refresh token. Sign in again.'},status=401)
