import hashlib, secrets
from datetime import timedelta, date
from pathlib import Path
from uuid import uuid4
from django.core.files.storage import default_storage
from django.http import FileResponse, Http404
from django.conf import settings
from django.contrib.auth import authenticate
from django.core.mail import send_mail
from django.utils import timezone
from rest_framework import status, serializers
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from .models import User, EmailOTP, CustomerProfile, DriverProfile
from .serializers import RegisterSerializer, LoginSerializer

def token_data(user):
    refresh=RefreshToken.for_user(user)
    profile_complete=False; driver_documents_complete=False
    if user.role=='DRIVER':
        profile=getattr(user,'driver_profile',None)
        profile_complete=bool(profile and profile.profile_complete)
        driver_documents_complete=bool(profile and {'LICENSE','IDENTITY'} <= set(profile.documents.values_list('document_type',flat=True)))
    elif user.role=='CUSTOMER':
        profile=getattr(user,'customer_profile',None);profile_complete=bool(profile and profile.profile_complete)
    return {'access':str(refresh.access_token),'refresh':str(refresh),'user':{'id':user.id,'name':user.full_name,'email':user.email,'phone':user.phone,'role':user.role,'email_verified':user.email_verified,'profile_complete':profile_complete,'driver_documents_complete':driver_documents_complete}}
def issue_otp(user):
    code=f'{secrets.randbelow(1000000):06d}'
    EmailOTP.objects.filter(user=user,consumed_at__isnull=True).update(consumed_at=timezone.now())
    EmailOTP.objects.create(user=user,code_hash=hashlib.sha256(code.encode()).hexdigest(),expires_at=timezone.now()+timedelta(minutes=settings.OTP_EXPIRY_MINUTES))
    send_mail('Your DriveMate verification code',f'Your verification code is {code}. It expires in {settings.OTP_EXPIRY_MINUTES} minutes. Do not share it.',settings.DEFAULT_FROM_EMAIL,[user.email],fail_silently=False)

class RegisterView(APIView):
    permission_classes=[AllowAny]
    def post(self,request):
        s=RegisterSerializer(data=request.data); s.is_valid(raise_exception=True); data=s.validated_data
        user=User(email=data['email'],full_name=data['full_name'],phone=data['phone'],role=data['role'])
        user.set_password(data['password']); user.save()
        if user.role=='DRIVER': DriverProfile.objects.create(user=user)
        else: CustomerProfile.objects.create(user=user)
        issue_otp(user)
        return Response({'message':'Account created. Check your email for a verification code.','email':user.email},status=201)
class VerifyOTPView(APIView):
    permission_classes=[AllowAny]
    def post(self,request):
        email=str(request.data.get('email','')).lower().strip(); code=str(request.data.get('otp','')).strip()
        try: user=User.objects.get(email=email)
        except User.DoesNotExist: return Response({'detail':'Account not found.'},status=404)
        if user.email_verified: return Response(token_data(user))
        otp=EmailOTP.objects.filter(user=user,consumed_at__isnull=True).order_by('-created_at').first()
        if not otp or otp.expires_at < timezone.now(): return Response({'detail':'Code expired. Request a new code.'},status=400)
        if otp.attempts >= settings.OTP_MAX_ATTEMPTS: return Response({'detail':'Too many attempts. Request a new code.'},status=429)
        otp.attempts+=1; otp.save(update_fields=['attempts'])
        if not secrets.compare_digest(otp.code_hash,hashlib.sha256(code.encode()).hexdigest()): return Response({'detail':'Incorrect verification code.'},status=400)
        otp.consumed_at=timezone.now(); otp.save(update_fields=['consumed_at']); user.email_verified=True; user.save(update_fields=['email_verified'])
        return Response(token_data(user))
class ResendOTPView(APIView):
    permission_classes=[AllowAny]
    def post(self,request):
        try: user=User.objects.get(email=str(request.data.get('email','')).lower().strip())
        except User.DoesNotExist: return Response({'detail':'Account not found.'},status=404)
        if user.email_verified: return Response({'detail':'Email is already verified.'},status=400)
        issue_otp(user); return Response({'message':'A new code has been sent.'})
class LoginView(APIView):
    permission_classes=[AllowAny]
    def post(self,request):
        s=LoginSerializer(data=request.data); s.is_valid(raise_exception=True)
        identifier=s.validated_data['identifier'].strip()
        if '@' in identifier:
            candidate=User.objects.filter(email__iexact=identifier).first()
        else:
            phone=identifier.replace(' ','').replace('-','').replace('(','').replace(')','')
            candidate=User.objects.filter(phone=phone).first()
        user=authenticate(request,email=candidate.email,password=s.validated_data['password']) if candidate else None
        if not user: return Response({'detail':'Email/phone or password is incorrect.'},status=401)
        if user.role != s.validated_data['role']: return Response({'detail':'Choose the role linked to this account.'},status=403)
        if not user.email_verified: issue_otp(user); return Response({'detail':'Verify your email first. A new code has been sent.','email':user.email,'needs_verification':True},status=403)
        if user.role=='ADMIN' and not user.is_staff: return Response({'detail':'Admin access is not enabled for this account.'},status=403)
        return Response(token_data(user))
class MeView(APIView):
    permission_classes=[IsAuthenticated]
    def get(self,request): return Response({'id':request.user.id,'name':request.user.full_name,'email':request.user.email,'phone':request.user.phone,'role':request.user.role,'email_verified':request.user.email_verified})

class ProfileView(APIView):
    permission_classes=[IsAuthenticated]
    def get(self,request):
        u=request.user
        if u.role=='DRIVER':
            p=DriverProfile.objects.get_or_create(user=u)[0]
            data={'date_of_birth':p.date_of_birth,'address':p.address,'city':p.city,'emergency_contact_name':p.emergency_contact_name,'emergency_contact_phone':p.emergency_contact_phone,'languages':p.languages,'introduction':p.introduction,'licence_number':p.licence_number,'licence_expiry':p.licence_expiry,'experience_years':p.experience_years,'manual_transmission':p.manual_transmission,'automatic_transmission':p.automatic_transmission,'sedan':p.sedan,'suv':p.suv,'luxury':p.luxury,'highway':p.highway,'night_driving':p.night_driving,'outstation':p.outstation,'verification_status':p.verification_status,'profile_complete':p.profile_complete}
        elif u.role=='CUSTOMER':
            p=CustomerProfile.objects.get_or_create(user=u)[0]
            data={'address':p.address,'city':p.city,'emergency_contact_name':p.emergency_contact_name,'emergency_contact_phone':p.emergency_contact_phone,'profile_complete':p.profile_complete}
        else: return Response({'detail':'Profile editing is not available for this role.'},status=403)
        return Response({'name':u.full_name,'email':u.email,'phone':u.phone,'role':u.role,'profile':data})
    def put(self,request):
        u=request.user; d=request.data
        if u.role=='DRIVER':
            p=DriverProfile.objects.get_or_create(user=u)[0]
            for key in ('address','city','emergency_contact_name','emergency_contact_phone','languages','introduction','licence_number'):
                if key in d: setattr(p,key,str(d[key]).strip())
            for key in ('manual_transmission','automatic_transmission','sedan','suv','luxury','highway','night_driving','outstation'):
                if key in d: setattr(p,key,bool(d[key]))
            if 'experience_years' in d:
                try: p.experience_years=max(0,min(60,int(d['experience_years'])))
                except (ValueError,TypeError): return Response({'detail':'Experience must be a number of years.'},status=400)
            try:
                if d.get('date_of_birth'): p.date_of_birth=date.fromisoformat(str(d['date_of_birth']))
                if d.get('licence_expiry'): p.licence_expiry=date.fromisoformat(str(d['licence_expiry']))
            except ValueError: return Response({'detail':'Enter dates in YYYY-MM-DD format.'},status=400)
            if p.date_of_birth and (date.today().year-p.date_of_birth.year-( (date.today().month,date.today().day)<(p.date_of_birth.month,p.date_of_birth.day) ))<18:
                return Response({'detail':'Driver applicants must be at least 18 to continue.'},status=400)
            required=[p.date_of_birth,p.address,p.city,p.emergency_contact_name,p.emergency_contact_phone,p.languages,p.introduction,p.licence_number,p.licence_expiry,p.experience_years>=0,request.user.profile_photo_key,any([p.manual_transmission,p.automatic_transmission,p.sedan,p.suv,p.luxury,p.highway,p.night_driving,p.outstation])]
            p.profile_complete=all(bool(x) for x in required)
            if p.licence_expiry and p.licence_expiry<=date.today():return Response({'detail':'Licence expiry date must be in the future.'},status=400)
            p.save()
            return Response({'message':'Driver details saved. Submit both identity and licence documents to enter admin review.','profile_complete':p.profile_complete,'verification_status':p.verification_status})
        if u.role=='CUSTOMER':
            p=CustomerProfile.objects.get_or_create(user=u)[0]
            for key in ('address','city','emergency_contact_name','emergency_contact_phone'):
                if key in d: setattr(p,key,str(d[key]).strip())
            p.profile_complete=bool(p.address and p.city and p.emergency_contact_name and p.emergency_contact_phone and u.profile_photo_key); p.save()
            return Response({'message':'Customer profile saved.','profile_complete':p.profile_complete})
        return Response({'detail':'Profile editing is not available for this role.'},status=403)
