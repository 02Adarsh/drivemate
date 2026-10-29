"""Django admin registration so staff can inspect bookings in the panel."""

from django.contrib import admin

from .models import Booking, BookingDecline, BookingEvent, Notification, Vehicle, ServiceRate


class ReadOnlyLedgerAdmin(admin.ModelAdmin):
    # All state changes go through the API so no transition can skip its audit
    # event or notification. Django admin is an inspection surface, not a way
    # to silently edit money/status.
    def get_readonly_fields(self, request, obj=None):
        return tuple(field.name for field in self.model._meta.fields)

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False


class BookingEventInline(admin.TabularInline):
    model = BookingEvent
    extra = 0
    readonly_fields = ('kind', 'note', 'created_by', 'created_at')
    can_delete = False

    def has_add_permission(self, request, obj=None):
        return False


@admin.register(Vehicle)
class VehicleAdmin(ReadOnlyLedgerAdmin):
    list_display = ('display_name', 'registration', 'owner', 'fuel', 'transmission', 'is_default')
    search_fields = ('registration', 'make', 'model', 'owner__email', 'owner__full_name')
    list_filter = ('fuel', 'transmission', 'is_default')


@admin.register(Booking)
class BookingAdmin(ReadOnlyLedgerAdmin):
    list_display = ('id', 'customer', 'driver', 'service', 'status', 'estimated_fare', 'final_fare', 'created_at')
    list_filter = ('status', 'service')
    search_fields = ('customer__email', 'customer__full_name', 'driver__email', 'pickup', 'vehicle__registration')
    readonly_fields = ('created_at', 'updated_at', 'accepted_at', 'started_at', 'completed_at', 'cancelled_at')
    inlines = [BookingEventInline]


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ('user', 'title', 'kind', 'is_read', 'created_at')
    list_filter = ('kind',)
    search_fields = ('user__email', 'title')


admin.site.register(BookingDecline)


@admin.register(ServiceRate)
class ServiceRateAdmin(admin.ModelAdmin):
    list_display = ('service', 'base', 'per_hour', 'updated_at')
    readonly_fields = ('service', 'updated_at')

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False
