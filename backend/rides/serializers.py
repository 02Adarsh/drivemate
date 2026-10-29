"""Strict input validation. Prices and roles are never accepted from clients."""
import re
from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers

from .models import Booking, Vehicle, normalise_registration
from .pricing import MAX_HOURS, SERVICE_PRICING


class VehicleInputSerializer(serializers.Serializer):
    make = serializers.CharField(min_length=2, max_length=60)
    model = serializers.CharField(min_length=1, max_length=60)
    registration = serializers.CharField(max_length=24)
    fuel = serializers.ChoiceField(choices=Vehicle.Fuel.choices, default=Vehicle.Fuel.PETROL)
    transmission = serializers.ChoiceField(choices=Vehicle.Transmission.choices, default=Vehicle.Transmission.MANUAL)
    seats = serializers.IntegerField(min_value=2, max_value=9, default=5)
    is_default = serializers.BooleanField(default=False)

    def validate_registration(self, value):
        value = normalise_registration(value)
        # Includes standard Indian plates and the BH-series. This is a format
        # check, not an ownership / government registry verification.
        if not re.fullmatch(r'[A-Z0-9]{6,16}', value):
            raise serializers.ValidationError('Enter a full 6–16 character registration number.')
        return value


class BookingInputSerializer(serializers.Serializer):
    vehicle_id = serializers.IntegerField(min_value=1)
    service = serializers.ChoiceField(choices=Booking.Service.choices)
    duration_hours = serializers.IntegerField(min_value=1, max_value=MAX_HOURS)
    pickup = serializers.CharField(min_length=4, max_length=240)
    drop_address = serializers.CharField(max_length=240, allow_blank=True, default='')
    notes = serializers.CharField(max_length=500, allow_blank=True, default='')
    scheduled_at = serializers.DateTimeField(required=False, allow_null=True)
    request_key = serializers.CharField(max_length=64, required=False, allow_blank=True)
    pickup_latitude = serializers.DecimalField(max_digits=10, decimal_places=7, min_value=-90, max_value=90)
    pickup_longitude = serializers.DecimalField(max_digits=10, decimal_places=7, min_value=-180, max_value=180)
    drop_latitude = serializers.DecimalField(max_digits=10, decimal_places=7, min_value=-90, max_value=90, required=False, allow_null=True)
    drop_longitude = serializers.DecimalField(max_digits=10, decimal_places=7, min_value=-180, max_value=180, required=False, allow_null=True)
    passenger_name = serializers.CharField(max_length=120, allow_blank=True, required=False)
    passenger_phone = serializers.CharField(max_length=20, allow_blank=True, required=False)
    business_id = serializers.IntegerField(min_value=1, required=False)
    promo_code = serializers.CharField(max_length=32, required=False, allow_blank=True)


    def validate_scheduled_at(self, value):
        if value is not None:
            if value < timezone.now():
                raise serializers.ValidationError('Choose a time in the future.')
            if value > timezone.now() + timedelta(days=90):
                raise serializers.ValidationError('You can schedule up to 90 days ahead.')
        return value

    def validate(self, data):
        for prefix in ['pickup', 'drop']:
            if (data.get(prefix+'_latitude') is None) != (data.get(prefix+'_longitude') is None):
                raise serializers.ValidationError({prefix:'Latitude and longitude must be provided together.'})
        name=data.get('passenger_name','')
        phone=data.get('passenger_phone','')
        if bool(name) != bool(phone):
            raise serializers.ValidationError({'passenger_name':'Traveller name and mobile must be provided together.'})
        if phone and not re.fullmatch(r'\+?[0-9]{10,15}',phone):
            raise serializers.ValidationError({'passenger_phone':'Enter a complete mobile number.'})
        service = data['service']
        minimum = SERVICE_PRICING[service]['min_hours']
        if data['duration_hours'] < minimum:
            raise serializers.ValidationError({'duration_hours': f'{minimum} hours minimum for this service.'})
        if service == Booking.Service.OUTSTATION and (len(data['drop_address']) < 4 or data.get('drop_latitude') is None or data.get('drop_longitude') is None):
            raise serializers.ValidationError({'drop_address': 'Enter the outstation destination.'})
        return data


class AvailabilityInputSerializer(serializers.Serializer):
    available = serializers.BooleanField()


class CancelInputSerializer(serializers.Serializer):
    reason = serializers.CharField(min_length=3, max_length=240)
