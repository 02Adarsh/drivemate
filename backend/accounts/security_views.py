"""Private file uploads, password reset and admin verification APIs.

Files are written through Django's storage layer (`default_storage`), so the
same code works with local disk in development and object storage in
production by only changing `STORAGES` in settings. Nothing here returns a
public URL for a driver document.
"""

import hashlib
import secrets
from pathlib import Path
from uuid import uuid4

from django.conf import settings
from django.core.files.storage import default_storage
from django.core.mail import send_mail
from django.http import FileResponse, Http404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAdminUser, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import DriverDocument, DriverProfile, EmailOTP, User
from .progress import apply_review_decision, driver_progress, ensure_training_rows, ready_for_review, sync_driver_status
from .serializers import ReviewDecisionSerializer
from .views import driver_application_payload, issue_otp
from .email_codes import code_matches

# ---------------------------------------------------------------------------
# Upload validation (server side - the app's checks are only for convenience)
# ---------------------------------------------------------------------------

IMAGE_TYPES = {'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp'}
DOCUMENT_TYPES = {**IMAGE_TYPES, 'application/pdf': '.pdf'}
MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # 5 MB


# Magic numbers: the first bytes of the file itself. Some mobile clients send
# "application/octet-stream" (or nothing at all) for a perfectly valid photo, so
# we check what the file really is instead of only trusting the header.
SIGNATURES = (
    (b'\xff\xd8\xff', 'image/jpeg'),
    (b'\x89PNG\r\n\x1a\n', 'image/png'),
    (b'RIFF', 'image/webp'),          # RIFF....WEBP
    (b'%PDF', 'application/pdf'),
    (b'GIF87a', 'image/gif'),
    (b'GIF89a', 'image/gif'),
)


def detect_content_type(upload) -> str | None:
    """Return the MIME type detected from the file's own bytes."""
    head = upload.read(32)
    upload.seek(0)
    for signature, mime in SIGNATURES:
        if head.startswith(signature):
            if mime == 'image/webp' and b'WEBP' not in head[8:16]:
                continue
            return mime
    # HEIC/HEIF (ISO base media file format) starts with a size field + 'ftyp'
    if len(head) > 12 and head[4:8] == b'ftyp':
        brand = head[8:12]
        if brand in (b'heic', b'heix', b'hevc', b'mif1', b'msf1'):
            return 'image/heic'
    return None


def validate_upload(upload, allowed):
    """Reject missing, oversized or genuinely unsupported files.

    The declared content type is used only as a hint: if the file's own bytes
    are a supported image/PDF we accept it even when the header was generic.
    """
    if not upload:
        return 'Select a file first.'
    if upload.size > MAX_UPLOAD_BYTES:
        return 'Maximum upload size is 5 MB.'

    detected = detect_content_type(upload)
    if detected is None:
        readable = ', '.join(sorted({value.lstrip('.') for value in allowed.values()}))
        return f'That file does not look like a supported format. Allowed: {readable}.'

    if detected in allowed:
        return None

    # HEIC/HEIF photos are accepted for images and treated as JPEG-compatible
    # uploads (the phone already converted them in most cases).
    if detected == 'image/heic' and 'image/jpeg' in allowed:
        return None

    readable = ', '.join(sorted({value.lstrip('.') for value in allowed.values()}))
    return f'Allowed file types: {readable}.'


class ProfilePhotoUploadView(APIView):
    """Required for both customers and drivers."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        key=request.user.profile_photo_key
        if not key or not default_storage.exists(key):raise Http404
        import mimetypes
        return FileResponse(default_storage.open(key,'rb'),content_type=mimetypes.guess_type(key)[0] or 'image/jpeg')

    def post(self, request):
        upload = request.FILES.get('file')
        error = validate_upload(upload, IMAGE_TYPES)
        if error:
            return Response({'detail': error}, status=status.HTTP_400_BAD_REQUEST)

        detected = detect_content_type(upload) or 'image/jpeg'
        extension = IMAGE_TYPES.get(detected, '.jpg')
        key = f'private/profile/{request.user.id}/{uuid4().hex}{extension}'
        saved = default_storage.save(key, upload)
        old_key = request.user.profile_photo_key
        request.user.profile_photo_key = saved
        request.user.save(update_fields=['profile_photo_key'])
        if old_key and default_storage.exists(old_key):
            default_storage.delete(old_key)

        if request.user.role == User.Role.DRIVER:
            profile, _ = DriverProfile.objects.get_or_create(user=request.user)
            ensure_training_rows(profile)
            sync_driver_status(profile)
            return Response(
                {
                    'message': 'Profile photo saved privately.',
                    'has_profile_photo': True,
                    'progress': driver_progress(profile),
                },
                status=status.HTTP_201_CREATED,
            )
        return Response({'message': 'Profile photo saved privately.', 'has_profile_photo': True}, status=status.HTTP_201_CREATED)


class DriverDocumentUploadView(APIView):
    """Step 4: licence front/back, identity proof (and optional address proof)."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        if request.user.role != User.Role.DRIVER:
            return Response({'detail': 'Only drivers can submit verification documents.'}, status=status.HTTP_403_FORBIDDEN)

        document_type = str(request.data.get('document_type', '')).upper()
        valid_types = dict(DriverDocument.Type.choices)
        if document_type not in valid_types:
            return Response(
                {'detail': f'document_type must be one of: {", ".join(valid_types)}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        upload = request.FILES.get('file')
        error = validate_upload(upload, DOCUMENT_TYPES)
        if error:
            return Response({'detail': error}, status=status.HTTP_400_BAD_REQUEST)

        profile, _ = DriverProfile.objects.get_or_create(user=request.user)
        # Documents are step 4: steps 2 and 3 must be finished first.
        from .progress import driving_details_complete, personal_profile_complete

        if not (personal_profile_complete(profile) and driving_details_complete(profile)):
            return Response(
                {'detail': 'Complete your personal profile and driving details before uploading documents.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        detected = detect_content_type(upload) or 'application/pdf'
        extension = DOCUMENT_TYPES.get(detected, '.pdf')
        key = f'private/driver-documents/{request.user.id}/{document_type.lower()}-{uuid4().hex}{extension}'
        saved = default_storage.save(key, upload)

        document, created = DriverDocument.objects.get_or_create(driver=profile, document_type=document_type)
        old_key = '' if created else document.private_storage_key
        document.private_storage_key = saved
        document.review_status = DriverDocument.Review.PENDING
        document.rejection_reason = ''
        document.reviewed_at = None
        document.reviewed_by = None
        if 'document_number' in request.data:
            document.document_number = str(request.data['document_number']).strip()[:80]
        if request.data.get('expires_at'):
            try:
                from datetime import date

                document.expires_at = date.fromisoformat(str(request.data['expires_at'])[:10])
            except ValueError:
                return Response({'detail': 'Enter the expiry date as YYYY-MM-DD.'}, status=status.HTTP_400_BAD_REQUEST)
        document.save()
        if old_key and default_storage.exists(old_key):
            default_storage.delete(old_key)

        sync_driver_status(profile)
        return Response(
            {
                'message': 'Document uploaded privately and queued for review.',
                'document': {
                    'id': document.id,
                    'document_type': document.document_type,
                    'document_label': document.get_document_type_display(),
                    'review_status': document.review_status,
                    'uploaded_at': document.uploaded_at,
                },
                'progress': driver_progress(profile),
            },
            status=status.HTTP_201_CREATED,
        )


class AdminDocumentDownloadView(APIView):
    """Staff-only download of a private driver document."""

    permission_classes = [IsAdminUser]

    def get(self, request, document_id):
        try:
            document = DriverDocument.objects.get(pk=document_id)
        except DriverDocument.DoesNotExist:
            raise Http404
        if not default_storage.exists(document.private_storage_key):
            raise Http404
        handle = default_storage.open(document.private_storage_key, 'rb')
        return FileResponse(handle, as_attachment=True, filename=Path(document.private_storage_key).name)


# ---------------------------------------------------------------------------
# Password reset
# ---------------------------------------------------------------------------

class PasswordResetRequestView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        email = str(request.data.get('email', '')).strip().lower()
        user = User.objects.filter(email=email).first()
        if user:
            issue_otp(user,purpose='RESET_PASSWORD')
        # Always the same answer, so this endpoint cannot be used to discover accounts.
        return Response({'message': 'If an account exists for that email, a reset code has been sent.'})


class PasswordResetConfirmView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        email = str(request.data.get('email', '')).strip().lower()
        code = str(request.data.get('otp', '')).strip()
        password = str(request.data.get('new_password', ''))
        if len(password) < 8:
            return Response({'detail': 'Use a password with at least 8 characters.'}, status=status.HTTP_400_BAD_REQUEST)

        user = User.objects.filter(email=email).first()
        if not user:
            return Response({'detail': 'Invalid reset request.'}, status=status.HTTP_400_BAD_REQUEST)
        otp = EmailOTP.objects.filter(user=user, purpose='RESET_PASSWORD', consumed_at__isnull=True).order_by('-created_at').first()
        if not otp or otp.expires_at < timezone.now() or otp.attempts >= settings.OTP_MAX_ATTEMPTS:
            return Response({'detail': 'Reset code expired. Request a new one.'}, status=status.HTTP_400_BAD_REQUEST)
        otp.attempts += 1
        otp.save(update_fields=['attempts'])
        if not code_matches(otp.code_hash,code):
            return Response({'detail': 'Incorrect reset code.'}, status=status.HTTP_400_BAD_REQUEST)
        otp.consumed_at = timezone.now()
        otp.save(update_fields=['consumed_at'])
        user.set_password(password)
        user.save(update_fields=['password'])
        return Response({'message': 'Password changed. Sign in with the new password.'})


# ---------------------------------------------------------------------------
# Admin verification API (used by the future admin dashboard, staff only)
# ---------------------------------------------------------------------------

class AdminDriverListView(APIView):
    permission_classes = [IsAdminUser]

    def get(self, request):
        status_filter = str(request.query_params.get('status', '')).upper()
        search = str(request.query_params.get('search', '')).strip()
        queryset = DriverProfile.objects.select_related('user').order_by('-updated_at')
        if status_filter in dict(DriverProfile.Status.choices):
            queryset = queryset.filter(verification_status=status_filter)
        if search:
            queryset = queryset.filter(user__full_name__icontains=search) | queryset.filter(user__email__icontains=search)
        results = []
        for profile in queryset[:200]:
            results.append(
                {
                    'driver_id': profile.id,
                    'user_id': profile.user_id,
                    'name': profile.user.full_name,
                    'email': profile.user.email,
                    'phone': profile.user.phone,
                    'city': profile.city,
                    'verification_status': profile.verification_status,
                    'submitted_at': profile.submitted_at,
                    'documents': profile.documents.count(),
                    'progress': driver_progress(profile),
                }
            )
        return Response({'count': len(results), 'results': results})


class AdminDriverReviewView(APIView):
    """Approve / reject / suspend a driver application."""

    permission_classes = [IsAdminUser]

    def post(self, request, user_id):
        profile = DriverProfile.objects.select_related('user').filter(user_id=user_id).first()
        if not profile:
            return Response({'detail': 'Driver not found.'}, status=status.HTTP_404_NOT_FOUND)
        serializer = ReviewDecisionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        action = serializer.validated_data['action']
        reason = serializer.validated_data.get('reason', '').strip()

        if action == 'approve' and not ready_for_review(profile):
            return Response(
                {
                    'detail': 'This application is not complete, so it cannot be approved yet.',
                    'progress': driver_progress(profile),
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        apply_review_decision(profile, action=action, reason=reason, reviewer=request.user)
        return Response(
            {
                'message': f'Driver status updated to {profile.get_verification_status_display()}.',
                'verification_status': profile.verification_status,
                'rejection_reason': profile.rejection_reason,
            }
        )


class AdminDocumentReviewView(APIView):
    """Approve, reject or return one document to pending review."""

    permission_classes = [IsAdminUser]

    def post(self, request, document_id):
        document = DriverDocument.objects.select_related('driver').filter(pk=document_id).first()
        if not document:
            return Response({'detail': 'Document not found.'}, status=status.HTTP_404_NOT_FOUND)
        action = str(request.data.get('action', '')).lower()
        if action not in ('approve', 'reject', 'pending'):
            return Response({'detail': 'action must be approve, reject or pending.'}, status=status.HTTP_400_BAD_REQUEST)
        reason = str(request.data.get('reason', '')).strip()
        if action == 'reject' and not (5 <= len(reason) <= 500):
            return Response({'detail': 'Provide a rejection reason of 5 to 500 characters.'}, status=status.HTTP_400_BAD_REQUEST)
        document.review_status = {'approve': DriverDocument.Review.APPROVED, 'reject': DriverDocument.Review.REJECTED, 'pending': DriverDocument.Review.PENDING}[action]
        document.rejection_reason = reason if action == 'reject' else ''
        document.reviewed_at = timezone.now()
        document.reviewed_by = request.user
        document.save()
        sync_driver_status(document.driver)
        return Response({'message': f'Document marked {document.review_status}.', 'document_id': document.id})


class AdminDriverApplicationView(APIView):
    """Full application detail for one driver (for the admin review screen)."""

    permission_classes = [IsAdminUser]

    def get(self, request, user_id):
        profile = DriverProfile.objects.select_related('user').filter(user_id=user_id).first()
        if not profile:
            return Response({'detail': 'Driver not found.'}, status=status.HTTP_404_NOT_FOUND)
        ensure_training_rows(profile)
        payload = driver_application_payload(profile)
        payload['driver'] = {
            'name': profile.user.full_name,
            'email': profile.user.email,
            'phone': profile.user.phone,
            'state': profile.state,
            'city': profile.city,
            'pincode': profile.pincode,
            'service_area': profile.service_area,
            'experience_years': profile.experience_years,
            'licence_number': profile.licence_number,
            'licence_expiry': profile.licence_expiry,
            'capabilities': [
                label
                for field, label in (
                    ('manual_transmission', 'Manual'),
                    ('automatic_transmission', 'Automatic'),
                    ('sedan', 'Sedan'),
                    ('suv', 'SUV'),
                    ('luxury', 'Luxury'),
                    ('highway', 'Highway'),
                    ('night_driving', 'Night driving'),
                    ('outstation', 'Outstation'),
                )
                if getattr(profile, field)
            ],
        }
        return Response(payload)
