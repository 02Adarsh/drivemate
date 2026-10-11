from django.contrib.auth.models import AbstractUser
from django.contrib.auth.base_user import BaseUserManager
from django.db import models
from django.utils import timezone

class DriveMateUserManager(BaseUserManager):
    use_in_migrations = False
    def _create_user(self, email, full_name, password, **extra_fields):
        if not email: raise ValueError('An email address is required.')
        user = self.model(email=self.normalize_email(email).lower(), full_name=full_name, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user
    def create_user(self, email, full_name, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', False)
        extra_fields.setdefault('is_superuser', False)
        return self._create_user(email, full_name, password, **extra_fields)
    def create_superuser(self, email, full_name, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        extra_fields.setdefault('is_active', True)
        if extra_fields.get('is_staff') is not True: raise ValueError('Superuser must have is_staff=True.')
        if extra_fields.get('is_superuser') is not True: raise ValueError('Superuser must have is_superuser=True.')
        return self._create_user(email, full_name, password, **extra_fields)

class User(AbstractUser):
    class Role(models.TextChoices):
        CUSTOMER='CUSTOMER','Customer'
        DRIVER='DRIVER','Driver'
        ADMIN='ADMIN','Admin'
    username = None
    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20, blank=True)
    profile_photo_key = models.CharField(max_length=500, blank=True)
    role = models.CharField(max_length=12, choices=Role.choices, default=Role.CUSTOMER)
    email_verified = models.BooleanField(default=False)
    objects = DriveMateUserManager()
    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['full_name']
    def __str__(self): return self.email

class EmailOTP(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='email_otps')
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(default=timezone.now)
    consumed_at = models.DateTimeField(null=True, blank=True)

class CustomerProfile(models.Model):
    user=models.OneToOneField(User,on_delete=models.CASCADE,related_name='customer_profile')
    address=models.CharField(max_length=250,blank=True)
    city=models.CharField(max_length=100,blank=True)
    emergency_contact_name=models.CharField(max_length=120,blank=True)
    emergency_contact_phone=models.CharField(max_length=20,blank=True)
    profile_complete=models.BooleanField(default=False)
    updated_at=models.DateTimeField(auto_now=True)

class DriverProfile(models.Model):
    class Status(models.TextChoices): INCOMPLETE='INCOMPLETE','Incomplete'; PENDING_REVIEW='PENDING_REVIEW','Pending review'; UNDER_REVIEW='UNDER_REVIEW','Under review'; APPROVED='APPROVED','Approved'; REJECTED='REJECTED','Rejected'; SUSPENDED='SUSPENDED','Suspended'
    user=models.OneToOneField(User,on_delete=models.CASCADE,related_name='driver_profile')
    date_of_birth=models.DateField(null=True,blank=True)
    address=models.CharField(max_length=250,blank=True)
    city=models.CharField(max_length=100,blank=True)
    emergency_contact_name=models.CharField(max_length=120,blank=True)
    emergency_contact_phone=models.CharField(max_length=20,blank=True)
    languages=models.CharField(max_length=250,blank=True)
    introduction=models.CharField(max_length=500,blank=True)
    licence_number=models.CharField(max_length=80,blank=True)
    licence_expiry=models.DateField(null=True,blank=True)
    experience_years=models.PositiveSmallIntegerField(default=0)
    manual_transmission=models.BooleanField(default=False)
    automatic_transmission=models.BooleanField(default=False)
    sedan=models.BooleanField(default=False)
    suv=models.BooleanField(default=False)
    luxury=models.BooleanField(default=False)
    highway=models.BooleanField(default=False)
    night_driving=models.BooleanField(default=False)
    outstation=models.BooleanField(default=False)
    verification_status=models.CharField(max_length=20,choices=Status.choices,default=Status.INCOMPLETE)
    profile_complete=models.BooleanField(default=False)
    submitted_at=models.DateTimeField(null=True,blank=True)
    updated_at=models.DateTimeField(auto_now=True)

class DriverDocument(models.Model):
    class Type(models.TextChoices): LICENSE='LICENSE','Driving licence'; IDENTITY='IDENTITY','Identity proof'
    class Review(models.TextChoices): PENDING='PENDING','Pending'; APPROVED='APPROVED','Approved'; REJECTED='REJECTED','Rejected'
    driver=models.ForeignKey(DriverProfile,on_delete=models.CASCADE,related_name='documents')
    document_type=models.CharField(max_length=20,choices=Type.choices)
    private_storage_key=models.CharField(max_length=500)
    expires_at=models.DateField(null=True,blank=True)
    review_status=models.CharField(max_length=12,choices=Review.choices,default=Review.PENDING)
    rejection_reason=models.CharField(max_length=500,blank=True)
    uploaded_at=models.DateTimeField(auto_now_add=True)
    reviewed_at=models.DateTimeField(null=True,blank=True)
    reviewed_by=models.ForeignKey(User,null=True,blank=True,on_delete=models.SET_NULL,related_name='reviewed_driver_documents')
