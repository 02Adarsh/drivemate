from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.urls import reverse
from django.utils import timezone
from django.utils.html import format_html
from .models import User, EmailOTP, CustomerProfile, DriverProfile, DriverDocument

@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering=('email',);list_display=('email','full_name','phone','role','email_verified','is_staff');search_fields=('email','full_name','phone')
    fieldsets=((None,{'fields':('email','password')}),('Profile',{'fields':('full_name','phone','profile_photo_key','role','email_verified')}),('Permissions',{'fields':('is_active','is_staff','is_superuser','groups','user_permissions')}),('Dates',{'fields':('last_login','date_joined')}))
    add_fieldsets=((None,{'classes':('wide',),'fields':('email','full_name','password1','password2')}),)
    filter_horizontal=('groups','user_permissions',)

@admin.register(DriverProfile)
class DriverProfileAdmin(admin.ModelAdmin):
    list_display=('user','city','experience_years','verification_status','profile_complete','submitted_at')
    list_filter=('verification_status','city','profile_complete');search_fields=('user__email','user__full_name','city','licence_number')
    readonly_fields=('user','updated_at')

@admin.register(DriverDocument)
class DriverDocumentAdmin(admin.ModelAdmin):
    list_display=('driver','document_type','review_status','uploaded_at','reviewed_at','reviewed_by','private_download')
    list_filter=('document_type','review_status');search_fields=('driver__user__email','driver__user__full_name')
    readonly_fields=('driver','document_type','private_storage_key','uploaded_at','reviewed_at','reviewed_by','private_download')
    fields=('driver','document_type','private_storage_key','private_download','expires_at','review_status','rejection_reason','uploaded_at','reviewed_at','reviewed_by')
    @admin.display(description='Secure file')
    def private_download(self,obj):
        if not obj.pk:return '-'
        url=reverse('admin-document-download',kwargs={'document_id':obj.pk})
        return format_html('<a href="{}">Download private document</a>',url)
    def save_model(self,request,obj,form,change):
        obj.reviewed_by=request.user;obj.reviewed_at=timezone.now();super().save_model(request,obj,form,change)
        profile=obj.driver;docs=list(profile.documents.values_list('review_status',flat=True))
        types=set(profile.documents.values_list('document_type',flat=True))
        if docs and all(x=='APPROVED' for x in docs) and types=={'LICENSE','IDENTITY'} and profile.profile_complete:profile.verification_status='APPROVED'
        elif obj.review_status=='REJECTED':profile.verification_status='REJECTED'
        else:profile.verification_status='UNDER_REVIEW'
        profile.save(update_fields=['verification_status','updated_at'])

admin.site.register(CustomerProfile)
admin.site.register(EmailOTP)
