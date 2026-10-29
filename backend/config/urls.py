"""URL map for the DriveMate API.

`/api/health/` is intentionally tiny and public: the mobile app calls it while
the splash screen is visible to find out which address actually answers (LAN IP,
USB tunnel via `adb reverse`, or emulator). It is also the fastest way to test
from a phone browser whether the backend is reachable at all.
"""

from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path
from django.views.decorators.cache import never_cache

from django.utils import timezone


@never_cache
def health(request):
    """Public reachability check - no database, no auth, no permissions."""
    return JsonResponse(
        {
            'status': 'ok',
            'service': 'drivemate-api',
            'api_version': 10,
            'map_provider': 'OpenStreetMap',
            'trip_start_otp_required': True,
            'payment_collection': 'cash-and-personal-upi-manual-confirmation',
            'time': timezone.now().isoformat(),
        }
    )


urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/health/', health, name='health'),
    path('api/auth/', include('accounts.urls')),
    path('api/rides/', include('rides.urls')),
    path('api/hub/', include('hub.urls')),
    path('api/payments/',include('payments.urls')),
]
