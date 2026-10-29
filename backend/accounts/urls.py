"""URL map for /api/auth/ (see docs/API.md for the full list)."""

from django.urls import path

from .security_views import (
    AdminDocumentDownloadView,
    AdminDocumentReviewView,
    AdminDriverApplicationView,
    AdminDriverListView,
    AdminDriverReviewView,
    DriverDocumentUploadView,
    PasswordResetConfirmView,
    PasswordResetRequestView,
    ProfilePhotoUploadView,
)
from .views import (
    DriverApplicationView,
    DriverConsentsView,
    DriverTrainingCompleteView,
    DriverTrainingView,
    EmergencyContactDeleteView,
    EmergencyContactListCreateView,
    LoginView,
    LoginOTPRequestView,
    SessionRefreshView,
    MeView,
    ProfileView,
    RegisterView,
    ResendOTPView,
    VerifyOTPView,
)

urlpatterns = [
    # Step 1 - account
    path('register/', RegisterView.as_view(), name='register'),
    path('verify-otp/', VerifyOTPView.as_view(), name='verify-otp'),
    path('resend-otp/', ResendOTPView.as_view(), name='resend-otp'),
    path('login/', LoginView.as_view(), name='login'),
    path('login/otp/', LoginOTPRequestView.as_view(), name='login-email-otp'),
    path('token/refresh/',SessionRefreshView.as_view(),name='session-refresh'),
    path('me/', MeView.as_view(), name='me'),

    # Profile (steps 2 and 3 for drivers, profile for customers)
    path('profile/', ProfileView.as_view(), name='profile'),
    path('profile/photo/', ProfilePhotoUploadView.as_view(), name='profile-photo'),
    path('password/reset/request/', PasswordResetRequestView.as_view(), name='password-reset-request'),
    path('password/reset/confirm/', PasswordResetConfirmView.as_view(), name='password-reset-confirm'),

    # Driver application (steps 4 and 5)
    path('driver/application/', DriverApplicationView.as_view(), name='driver-application'),
    path('driver/documents/', DriverDocumentUploadView.as_view(), name='driver-document-upload'),
    path('profile/documents/', DriverDocumentUploadView.as_view()),  # older path kept working
    path('driver/consents/', DriverConsentsView.as_view(), name='driver-consents'),
    path('driver/training/', DriverTrainingView.as_view(), name='driver-training'),
    path('driver/training/<str:module>/complete/', DriverTrainingCompleteView.as_view(), name='driver-training-complete'),
    path('driver/emergency-contacts/', EmergencyContactListCreateView.as_view(), name='driver-emergency-contacts'),
    path('driver/emergency-contacts/<int:contact_id>/', EmergencyContactDeleteView.as_view(), name='driver-emergency-contact-detail'),

    # Admin / staff verification API
    path('admin/drivers/', AdminDriverListView.as_view(), name='admin-driver-list'),
    path('admin/drivers/<int:user_id>/application/', AdminDriverApplicationView.as_view(), name='admin-driver-application'),
    path('admin/drivers/<int:user_id>/review/', AdminDriverReviewView.as_view(), name='admin-driver-review'),
    path('admin/documents/<int:document_id>/download/', AdminDocumentDownloadView.as_view(), name='admin-document-download'),
    path('admin/documents/<int:document_id>/review/', AdminDocumentReviewView.as_view(), name='admin-document-review'),
]
