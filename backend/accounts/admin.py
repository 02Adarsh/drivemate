"""Django admin: the current home of the admin verification workflow.

The same rules run here and in the REST API, because both call
`accounts.progress` instead of duplicating the logic.
"""

from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.urls import reverse
from django.utils.html import format_html
from django.utils import timezone

from .models import (
    CustomerProfile,
    DriverDocument,
    DriverEmergencyContact,
    DriverProfile,
    DriverTraining,
    EmailOTP,
    User,
)
from .progress import apply_review_decision, driver_progress, ensure_training_rows


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ('email',)
    list_display = ('email', 'full_name', 'phone', 'role', 'email_verified', 'is_staff', 'is_active')
    list_filter = ('role', 'email_verified', 'is_staff', 'is_active')
    search_fields = ('email', 'full_name', 'phone')
    fieldsets = (
        (None, {'fields': ('email', 'password')}),
        ('Profile', {'fields': ('full_name', 'phone', 'profile_photo_key', 'role', 'email_verified')}),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
        ('Dates', {'fields': ('last_login', 'date_joined', 'last_seen_at')}),
    )
    add_fieldsets = ((None, {'classes': ('wide',), 'fields': ('email', 'full_name', 'password1', 'password2')}),)
    filter_horizontal = ('groups', 'user_permissions')
    readonly_fields = ('last_seen_at',)


class DriverDocumentInline(admin.TabularInline):
    model = DriverDocument
    extra = 0
    fields = ('document_type', 'document_number', 'expires_at', 'review_status', 'rejection_reason', 'private_download')
    readonly_fields = ('private_download',)

    @admin.display(description='Secure file')
    def private_download(self, obj):
        if not obj.pk:
            return '-'
        url = reverse('admin-document-download', kwargs={'document_id': obj.pk})
        return format_html('<a href="{}">Download</a>', url)


@admin.register(DriverProfile)
class DriverProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'city', 'experience_years', 'verification_status', 'profile_complete', 'documents_count', 'submitted_at')
    list_filter = ('verification_status', 'city', 'profile_complete', 'manual_transmission', 'automatic_transmission')
    search_fields = ('user__email', 'user__full_name', 'city', 'licence_number')
    readonly_fields = ('updated_at', 'progress_summary', 'reviewed_at', 'reviewed_by', 'approved_at')
    inlines = (DriverDocumentInline,)
    actions = ('action_mark_under_review', 'action_approve', 'action_reject', 'action_suspend', 'action_reactivate')
    fieldsets = (
        ('Account', {'fields': ('user', 'verification_status', 'profile_complete', 'progress_summary')}),
        ('Personal (step 2)', {'fields': ('date_of_birth', 'address', 'city', 'service_area', 'emergency_contact_name', 'emergency_contact_phone', 'languages', 'introduction')}),
        ('Driving (step 3)', {'fields': ('licence_number', 'licence_expiry', 'experience_years', 'manual_transmission', 'automatic_transmission', 'sedan', 'suv', 'luxury', 'highway', 'night_driving', 'outstation')}),
        ('Consent (step 4)', {'fields': ('consent_background_check', 'consent_terms', 'consent_data_accuracy', 'consents_accepted_at')}),
        ('Review (step 5)', {'fields': ('submitted_at', 'reviewed_at', 'reviewed_by', 'approved_at', 'rejection_reason')}),
    )

    @admin.display(description='Documents')
    def documents_count(self, obj):
        return obj.documents.count()

    @admin.display(description='Progress')
    def progress_summary(self, obj):
        if not obj.pk:
            return '-'
        progress = driver_progress(obj)
        return (
            f"profile={progress['profile_complete']} documents={progress['documents_complete']} "
            f"consents={progress['consents_complete']} training={progress['training_complete']} "
            f"next={progress['next_step']}"
        )

    def save_model(self, request, obj, form, change):
        super().save_model(request, obj, form, change)
        ensure_training_rows(obj)

    #### Staff actions (each one records who decided and when) ####

    @admin.action(description='Mark selected drivers as UNDER_REVIEW')
    def action_mark_under_review(self, request, queryset):
        for profile in queryset:
            apply_review_decision(profile, action='under_review', reviewer=request.user)

    @admin.action(description='APPROVE selected driver applications')
    def action_approve(self, request, queryset):
        approved, skipped = 0, 0
        for profile in queryset:
            from .progress import ready_for_review

            if ready_for_review(profile):
                apply_review_decision(profile, action='approve', reviewer=request.user)
                approved += 1
            else:
                skipped += 1
        self.message_user(request, f'Approved {approved} driver(s). Skipped {skipped} incomplete application(s).')

    @admin.action(description='REJECT selected driver applications')
    def action_reject(self, request, queryset):
        for profile in queryset:
            apply_review_decision(
                profile,
                action='reject',
                reason=profile.rejection_reason or 'Documents or details did not pass verification. See admin note.',
                reviewer=request.user,
            )
        self.message_user(request, f'Rejected {queryset.count()} driver(s). Edit "rejection reason" on each profile to give a clear explanation.')

    @admin.action(description='SUSPEND selected drivers')
    def action_suspend(self, request, queryset):
        for profile in queryset:
            apply_review_decision(profile, action='suspend', reason=profile.rejection_reason, reviewer=request.user)
        self.message_user(request, f'Suspended {queryset.count()} driver(s).')

    @admin.action(description='Re-activate (approve) selected drivers')
    def action_reactivate(self, request, queryset):
        for profile in queryset:
            apply_review_decision(profile, action='reactivate', reviewer=request.user)
        self.message_user(request, f'Re-activated {queryset.count()} driver(s).')


@admin.register(DriverDocument)
class DriverDocumentAdmin(admin.ModelAdmin):
    list_display = ('driver', 'document_type', 'document_number', 'review_status', 'expires_at', 'uploaded_at', 'reviewed_at', 'reviewed_by', 'private_download')
    list_filter = ('document_type', 'review_status')
    search_fields = ('driver__user__email', 'driver__user__full_name', 'document_number')
    readonly_fields = ('driver', 'document_type', 'private_storage_key', 'uploaded_at', 'updated_at', 'reviewed_at', 'reviewed_by', 'private_download')
    fields = ('driver', 'document_type', 'document_number', 'expires_at', 'private_storage_key', 'private_download', 'review_status', 'rejection_reason', 'uploaded_at', 'updated_at', 'reviewed_at', 'reviewed_by')
    actions = ('action_approve_documents', 'action_reject_documents')

    @admin.display(description='Secure file')
    def private_download(self, obj):
        if not obj.pk:
            return '-'
        url = reverse('admin-document-download', kwargs={'document_id': obj.pk})
        return format_html('<a href="{}">Download private document</a>', url)

    def save_model(self, request, obj, form, change):
        obj.reviewed_by = request.user
        obj.reviewed_at = timezone.now()
        super().save_model(request, obj, form, change)

    @admin.action(description='Mark documents APPROVED')
    def action_approve_documents(self, request, queryset):
        queryset.update(review_status=DriverDocument.Review.APPROVED, reviewed_by=request.user, reviewed_at=timezone.now(), rejection_reason='')

    @admin.action(description='Mark documents REJECTED')
    def action_reject_documents(self, request, queryset):
        queryset.update(
            review_status=DriverDocument.Review.REJECTED,
            reviewed_by=request.user,
            reviewed_at=timezone.now(),
            rejection_reason='Document rejected by verification staff. Please upload a clear photo.',
        )


@admin.register(DriverTraining)
class DriverTrainingAdmin(admin.ModelAdmin):
    list_display = ('driver', 'module', 'status', 'completed_at')
    list_filter = ('module', 'status')
    search_fields = ('driver__user__email', 'driver__user__full_name')


@admin.register(DriverEmergencyContact)
class DriverEmergencyContactAdmin(admin.ModelAdmin):
    list_display = ('name', 'relationship', 'phone', 'driver', 'is_primary')
    search_fields = ('name', 'phone', 'driver__user__email')


@admin.register(CustomerProfile)
class CustomerProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'city', 'profile_complete', 'updated_at')
    search_fields = ('user__email', 'user__full_name', 'city')


@admin.register(EmailOTP)
class EmailOTPAdmin(admin.ModelAdmin):
    list_display = ('user', 'created_at', 'expires_at', 'attempts', 'consumed_at')
    readonly_fields = ('user', 'code_hash', 'created_at', 'expires_at', 'attempts', 'consumed_at')
