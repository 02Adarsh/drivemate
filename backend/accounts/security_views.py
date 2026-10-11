import hashlib, secrets
from pathlib import Path
from uuid import uuid4
from datetime import timedelta
from django.conf import settings
from django.core.files.storage import default_storage
from django.core.mail import send_mail
from django.http import FileResponse, Http404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated, IsAdminUser
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import User, EmailOTP, DriverProfile, DriverDocument
from .views import issue_otp

IMAGE_TYPES={'image/jpeg':'.jpg','image/png':'.png','image/webp':'.webp'}
DOC_TYPES={**IMAGE_TYPES,'application/pdf':'.pdf'}
def validate_upload(upload, allowed):
    if not upload: return 'Select a file first.'
    if upload.size > 5*1024*1024: return 'Maximum upload size is 5 MB.'
    if upload.content_type not in allowed: return 'Use JPG, PNG, WebP'+(' or PDF.' if 'application/pdf' in allowed else '.')
    return None

class ProfilePhotoUploadView(APIView):
    permission_classes=[IsAuthenticated]
    def post(self,request):
        upload=request.FILES.get('file'); error=validate_upload(upload,IMAGE_TYPES)
        if error:return Response({'detail':error},status=400)
        ext=IMAGE_TYPES[upload.content_type]; key=f'private/profile/{request.user.id}/{uuid4().hex}{ext}'
        saved=default_storage.save(key,upload)
        old=request.user.profile_photo_key
        request.user.profile_photo_key=saved;request.user.save(update_fields=['profile_photo_key'])
        if old and default_storage.exists(old):default_storage.delete(old)
        return Response({'message':'Profile photo saved privately.','has_profile_photo':True},status=201)

class DriverDocumentUploadView(APIView):
    permission_classes=[IsAuthenticated]
    def post(self,request):
        if request.user.role!='DRIVER':return Response({'detail':'Only drivers can submit verification documents.'},status=403)
        doc_type=str(request.data.get('document_type','')).upper()
        if doc_type not in ('LICENSE','IDENTITY'):return Response({'detail':'Document type must be LICENSE or IDENTITY.'},status=400)
        upload=request.FILES.get('file');error=validate_upload(upload,DOC_TYPES)
        if error:return Response({'detail':error},status=400)
        profile=DriverProfile.objects.get_or_create(user=request.user)[0]
        ext=DOC_TYPES[upload.content_type];key=f'private/driver-documents/{request.user.id}/{uuid4().hex}{ext}'
        saved=default_storage.save(key,upload)
        obj=DriverDocument.objects.filter(driver=profile,document_type=doc_type).first()
        old_key=obj.private_storage_key if obj else ''
        if obj:
            obj.private_storage_key=saved;obj.review_status='PENDING';obj.rejection_reason='';obj.reviewed_at=None;obj.reviewed_by=None;obj.save()
        else: obj=DriverDocument.objects.create(driver=profile,document_type=doc_type,private_storage_key=saved)
        if old_key and default_storage.exists(old_key):default_storage.delete(old_key)
        docs=set(profile.documents.values_list('document_type',flat=True))
        if profile.profile_complete and docs=={'LICENSE','IDENTITY'} and profile.verification_status in ('INCOMPLETE','REJECTED'):
            profile.verification_status='PENDING_REVIEW';profile.submitted_at=timezone.now();profile.save(update_fields=['verification_status','submitted_at','updated_at'])
        return Response({'message':'Document uploaded privately and queued for review.','document_type':doc_type,'review_status':obj.review_status},status=201)

class AdminDocumentDownloadView(APIView):
    permission_classes=[IsAdminUser]
    def get(self,request,document_id):
        try: doc=DriverDocument.objects.get(pk=document_id)
        except DriverDocument.DoesNotExist: raise Http404
        if not default_storage.exists(doc.private_storage_key):raise Http404
        fh=default_storage.open(doc.private_storage_key,'rb')
        return FileResponse(fh,as_attachment=True,filename=Path(doc.private_storage_key).name)

class PasswordResetRequestView(APIView):
    permission_classes=[AllowAny]
    def post(self,request):
        email=str(request.data.get('email','')).strip().lower()
        try:user=User.objects.get(email=email)
        except User.DoesNotExist:return Response({'message':'If an account exists, a reset code has been sent.'})
        issue_otp(user)
        return Response({'message':'If an account exists, a reset code has been sent.'})

class PasswordResetConfirmView(APIView):
    permission_classes=[AllowAny]
    def post(self,request):
        email=str(request.data.get('email','')).strip().lower();code=str(request.data.get('otp','')).strip();password=str(request.data.get('new_password',''))
        if len(password)<8:return Response({'detail':'Use a password with at least 8 characters.'},status=400)
        try:user=User.objects.get(email=email)
        except User.DoesNotExist:return Response({'detail':'Invalid reset request.'},status=400)
        otp=EmailOTP.objects.filter(user=user,consumed_at__isnull=True).order_by('-created_at').first()
        if not otp or otp.expires_at<timezone.now() or otp.attempts>=settings.OTP_MAX_ATTEMPTS:return Response({'detail':'Reset code expired. Request a new one.'},status=400)
        otp.attempts+=1;otp.save(update_fields=['attempts'])
        if not secrets.compare_digest(otp.code_hash,hashlib.sha256(code.encode()).hexdigest()):return Response({'detail':'Incorrect reset code.'},status=400)
        otp.consumed_at=timezone.now();otp.save(update_fields=['consumed_at']);user.set_password(password);user.save(update_fields=['password'])
        return Response({'message':'Password changed. Sign in with the new password.'})
