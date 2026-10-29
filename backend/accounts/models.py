"""DriveMate account models.

Design rules kept in mind (see docs/ARCHITECTURE.md):
* Customers own the car. Drivers are verified professionals who drive it.
* One `User` row per login. Customer and driver data live in separate profile
  tables instead of being mixed into `User`.
* Documents are stored privately (storage key only, never a public URL).
* Verification state is a small, explicit state machine (`DriverProfile.Status`).
"""

from django.contrib.auth.models import AbstractUser
from django.contrib.auth.base_user import BaseUserManager
from django.db import models
from django.utils import timezone


class DriveMateUserManager(BaseUserManager):
    """Email-first manager. Phone numbers are collected but are not the login key."""

    use_in_migrations = False

    def _create_user(self, email, full_name, password, **extra_fields):
        if not email:
            raise ValueError('An email address is required.')
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
        # A Django superuser is platform staff, so the role follows automatically.
        extra_fields.setdefault('role', self.model.Role.ADMIN)
        extra_fields.setdefault('email_verified', True)
        if extra_fields.get('is_staff') is not True:
            raise ValueError('Superuser must have is_staff=True.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('Superuser must have is_superuser=True.')
        return self._create_user(email, full_name, password, **extra_fields)


class User(AbstractUser):
    """Login row for every person. Role decides which app surface they may open."""

    class Role(models.TextChoices):
        CUSTOMER = 'CUSTOMER', 'Customer'
        DRIVER = 'DRIVER', 'Driver'
        ADMIN = 'ADMIN', 'Admin'

    username = None
    email = models.EmailField(unique=True)
    full_name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20, blank=True)
    profile_photo_key = models.CharField(max_length=500, blank=True)
    role = models.CharField(max_length=12, choices=Role.choices, default=Role.CUSTOMER)
    email_verified = models.BooleanField(default=False)
    last_seen_at = models.DateTimeField(null=True, blank=True)

    objects = DriveMateUserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['full_name']

    class Meta:
        indexes = [
            models.Index(fields=['role'], name='user_role_idx'),
            models.Index(fields=['phone'], name='user_phone_idx'),
        ]

    def __str__(self):
        return f'{self.full_name} <{self.email}>'


class EmailOTP(models.Model):
    """One-time codes for email verification and password reset (hashed at rest)."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='email_otps')
    purpose = models.CharField(max_length=20, default='VERIFY_EMAIL')
    code_hash = models.CharField(max_length=128)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(default=timezone.now)
    consumed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=['user', 'consumed_at'], name='otp_user_consumed_idx')]


class CustomerProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='customer_profile')
    address = models.CharField(max_length=250, blank=True)
    state = models.CharField(max_length=100, blank=True)
    city = models.CharField(max_length=100, blank=True)
    pincode = models.CharField(max_length=10, blank=True)
    emergency_contact_name = models.CharField(max_length=120, blank=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True)
    profile_complete = models.BooleanField(default=False)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'Customer profile #{self.pk}'


class DriverProfile(models.Model):
    """Everything a driver must complete before an admin can approve them."""

    class Status(models.TextChoices):
        INCOMPLETE = 'INCOMPLETE', 'Incomplete'
        PENDING_REVIEW = 'PENDING_REVIEW', 'Pending review'
        UNDER_REVIEW = 'UNDER_REVIEW', 'Under review'
        APPROVED = 'APPROVED', 'Approved'
        REJECTED = 'REJECTED', 'Rejected'
        SUSPENDED = 'SUSPENDED', 'Suspended'
        INACTIVE = 'INACTIVE', 'Inactive'

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='driver_profile')

    # Step 2 - personal profile
    date_of_birth = models.DateField(null=True, blank=True)
    address = models.CharField(max_length=250, blank=True)
    state = models.CharField(max_length=100, blank=True)
    city = models.CharField(max_length=100, blank=True)
    pincode = models.CharField(max_length=10, blank=True)
    service_area = models.CharField(max_length=120, blank=True)
    emergency_contact_name = models.CharField(max_length=120, blank=True)
    emergency_contact_phone = models.CharField(max_length=20, blank=True)
    languages = models.CharField(max_length=250, blank=True)
    introduction = models.CharField(max_length=500, blank=True)

    # Step 3 - driving details
    licence_number = models.CharField(max_length=80, blank=True)
    licence_expiry = models.DateField(null=True, blank=True)
    experience_years = models.PositiveSmallIntegerField(default=0)
    manual_transmission = models.BooleanField(default=False)
    automatic_transmission = models.BooleanField(default=False)
    sedan = models.BooleanField(default=False)
    suv = models.BooleanField(default=False)
    luxury = models.BooleanField(default=False)
    highway = models.BooleanField(default=False)
    night_driving = models.BooleanField(default=False)
    outstation = models.BooleanField(default=False)

    # Step 4 - consent
    consent_background_check = models.BooleanField(default=False)
    consent_terms = models.BooleanField(default=False)
    consent_data_accuracy = models.BooleanField(default=False)
    consents_accepted_at = models.DateTimeField(null=True, blank=True)

    # Step 5 - verification workflow
    verification_status = models.CharField(max_length=20, choices=Status.choices, default=Status.INCOMPLETE)
    profile_complete = models.BooleanField(default=False)
    submitted_at = models.DateTimeField(null=True, blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.SET_NULL, related_name='reviewed_driver_profiles'
    )
    approved_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.CharField(max_length=500, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Availability is separate from approval: an APPROVED driver is still
    # offline until they turn themselves on (v7 booking phase). Only an
    # approved AND available driver can accept a request.
    is_available = models.BooleanField(default=False)
    available_since = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=['verification_status'], name='driver_status_idx'),
            models.Index(fields=['city'], name='driver_city_idx'),
            models.Index(fields=['state'], name='driver_state_idx'),
        ]

    def __str__(self):
        return f'{self.user.full_name} ({self.verification_status})'

    @property
    def is_approved(self) -> bool:
        return self.verification_status == self.Status.APPROVED


class DriverDocument(models.Model):
    """Private verification document. Files are stored under a private storage key."""

    class Type(models.TextChoices):
        LICENCE_FRONT = 'LICENCE_FRONT', 'Driving licence (front)'
        LICENCE_BACK = 'LICENCE_BACK', 'Driving licence (back)'
        IDENTITY = 'IDENTITY', 'Identity proof'
        ADDRESS_PROOF = 'ADDRESS_PROOF', 'Address proof (optional)'

    class Review(models.TextChoices):
        PENDING = 'PENDING', 'Pending'
        APPROVED = 'APPROVED', 'Approved'
        REJECTED = 'REJECTED', 'Rejected'

    driver = models.ForeignKey(DriverProfile, on_delete=models.CASCADE, related_name='documents')
    document_type = models.CharField(max_length=20, choices=Type.choices)
    private_storage_key = models.CharField(max_length=500)
    document_number = models.CharField(max_length=80, blank=True)
    expires_at = models.DateField(null=True, blank=True)
    review_status = models.CharField(max_length=12, choices=Review.choices, default=Review.PENDING)
    rejection_reason = models.CharField(max_length=500, blank=True)
    uploaded_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.SET_NULL, related_name='reviewed_driver_documents'
    )

    class Meta:
        unique_together = ('driver', 'document_type')
        indexes = [
            models.Index(fields=['document_type', 'review_status'], name='doc_type_review_idx'),
            models.Index(fields=['expires_at'], name='doc_expiry_idx'),
        ]

    def __str__(self):
        return f'{self.get_document_type_display()} - {self.driver.user.full_name}'


class DriverTraining(models.Model):
    """Training checklist. Content is a placeholder until real modules are added."""

    class Module(models.TextChoices):
        SAFE_DRIVING = 'SAFE_DRIVING', 'Safe driving basics'
        CUSTOMER_SERVICE = 'CUSTOMER_SERVICE', 'Customer service and conduct'
        VEHICLE_INSPECTION = 'VEHICLE_INSPECTION', 'Vehicle inspection and handover'
        AUTOMATIC_TRANSMISSION = 'AUTOMATIC_TRANSMISSION', 'Driving automatic vehicles'
        MANUAL_TRANSMISSION = 'MANUAL_TRANSMISSION', 'Driving manual vehicles'
        HIGHWAY_DRIVING = 'HIGHWAY_DRIVING', 'Highway driving'
        NIGHT_DRIVING = 'NIGHT_DRIVING', 'Night driving'
        EMERGENCY_PROCEDURES = 'EMERGENCY_PROCEDURES', 'Emergency procedures'
        APP_USAGE = 'APP_USAGE', 'Using the DriveMate app'

    class Status(models.TextChoices):
        NOT_STARTED = 'NOT_STARTED', 'Not started'
        IN_PROGRESS = 'IN_PROGRESS', 'In progress'
        COMPLETED = 'COMPLETED', 'Completed'

    driver = models.ForeignKey(DriverProfile, on_delete=models.CASCADE, related_name='training')
    module = models.CharField(max_length=32, choices=Module.choices)
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.NOT_STARTED)
    completed_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('driver', 'module')
        indexes = [models.Index(fields=['driver', 'status'], name='training_driver_status_idx')]

    def __str__(self):
        return f'{self.get_module_display()} - {self.status}'


class DriverEmergencyContact(models.Model):
    """Extra emergency contacts for a driver (the primary one lives on DriverProfile)."""

    driver = models.ForeignKey(DriverProfile, on_delete=models.CASCADE, related_name='emergency_contacts')
    name = models.CharField(max_length=120)
    relationship = models.CharField(max_length=60, blank=True)
    phone = models.CharField(max_length=20)
    is_primary = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [models.Index(fields=['driver'], name='emergency_driver_idx')]

    def __str__(self):
        return f'{self.name} ({self.phone})'
