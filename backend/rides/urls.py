"""URL map for /api/rides/."""

from django.urls import path

from .views import (
    AdminRidesOverviewView,
    AvailabilityView,
    BookingAcceptView,
    BookingCancelView,
    BookingCompleteView,
    BookingDeclineView,
    BookingDetailView,
    BookingListCreateView,
    BookingStartView,
    DriverRequestFeedView,
    DriverSummaryView,
    DriverTripsView,
    NotificationListView,
    NotificationReadView,
    PricingView,
    VehicleDetailView,
    VehicleListCreateView,
)

from .enhanced_views import StartCodeView,LocationView,CashReceivedView,RatingView,ReceiptView,ParticipantPhotoView

urlpatterns = [
    # Pricing + availability
    path('pricing/', PricingView.as_view(), name='ride-pricing'),
    path('availability/', AvailabilityView.as_view(), name='ride-availability'),

    # Vehicles (the customer's garage, now on the server)
    path('vehicles/', VehicleListCreateView.as_view(), name='ride-vehicles'),
    path('vehicles/<int:vehicle_id>/', VehicleDetailView.as_view(), name='ride-vehicle-detail'),

    # Bookings
    path('bookings/', BookingListCreateView.as_view(), name='ride-bookings'),
    path('bookings/<int:booking_id>/', BookingDetailView.as_view(), name='ride-booking-detail'),
    path('bookings/<int:booking_id>/cancel/', BookingCancelView.as_view(), name='ride-booking-cancel'),

    # Driver side
    path('requests/', DriverRequestFeedView.as_view(), name='ride-requests'),
    path('requests/<int:booking_id>/accept/', BookingAcceptView.as_view(), name='ride-request-accept'),
    path('requests/<int:booking_id>/decline/', BookingDeclineView.as_view(), name='ride-request-decline'),
    path('trips/', DriverTripsView.as_view(), name='ride-trips'),
    path('trips/<int:booking_id>/start/', BookingStartView.as_view(), name='ride-trip-start'),
    path('trips/<int:booking_id>/complete/', BookingCompleteView.as_view(), name='ride-trip-complete'),
    path('summary/', DriverSummaryView.as_view(), name='ride-summary'),

    # Notifications
    path('notifications/', NotificationListView.as_view(), name='ride-notifications'),
    path('notifications/read-all/', NotificationReadView.as_view(), name='ride-notifications-read-all'),
    path('notifications/<int:notification_id>/read/', NotificationReadView.as_view(), name='ride-notification-read'),

    # Admin
    path('admin/overview/', AdminRidesOverviewView.as_view(), name='ride-admin-overview'),
]

urlpatterns += [
 path('bookings/<int:booking_id>/start-code/',StartCodeView.as_view(),name='ride-start-code'),
 path('bookings/<int:booking_id>/location/',LocationView.as_view(),name='ride-location'),
 path('bookings/<int:booking_id>/cash/',CashReceivedView.as_view(),name='ride-cash'),
 path('bookings/<int:booking_id>/rating/',RatingView.as_view(),name='ride-rating'),
 path('bookings/<int:booking_id>/receipt/',ReceiptView.as_view(),name='ride-receipt'),
]

urlpatterns += [path('bookings/<int:booking_id>/photo/',ParticipantPhotoView.as_view(),name='ride-participant-photo')]
