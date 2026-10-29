from django.urls import path
from .views import DriverProfileView,DriverQRImageView,TripUPIView,TripQRImageView,ReportPaymentView,ReviewPaymentView,CancelRequestView
urlpatterns=[
 path('driver/profile/',DriverProfileView.as_view(),name='upi-driver-profile'),
 path('driver/qr/',DriverQRImageView.as_view(),name='upi-driver-qr'),
 path('trips/<int:booking_id>/',TripUPIView.as_view(),name='upi-trip'),
 path('trips/<int:booking_id>/qr/',TripQRImageView.as_view(),name='upi-trip-qr'),
 path('trips/<int:booking_id>/report/',ReportPaymentView.as_view(),name='upi-report'),
 path('trips/<int:booking_id>/review/',ReviewPaymentView.as_view(),name='upi-review'),
 path('trips/<int:booking_id>/cancel/',CancelRequestView.as_view(),name='upi-cancel'),
]
