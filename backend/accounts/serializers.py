from rest_framework import serializers
from .models import User

class RegisterSerializer(serializers.Serializer):
    full_name=serializers.CharField(max_length=120)
    email=serializers.EmailField()
    phone=serializers.CharField(max_length=20)
    password=serializers.CharField(min_length=8,write_only=True)
    role=serializers.ChoiceField(choices=[('CUSTOMER','Customer'),('DRIVER','Driver')])
    def validate_email(self,value):
        value=value.strip().lower()
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError('An account already exists for this email.')
        return value
    def validate_phone(self,value):
        cleaned=value.strip().replace(' ','').replace('-','').replace('(','').replace(')','')
        if not cleaned.lstrip('+').isdigit() or not 8<=len(cleaned.lstrip('+'))<=15 or cleaned.count('+')>1 or ('+' in cleaned and not cleaned.startswith('+')):
            raise serializers.ValidationError('Enter a valid phone number with 8–15 digits.')
        if User.objects.filter(phone=cleaned).exists():
            raise serializers.ValidationError('An account already exists for this phone number.')
        return cleaned

class LoginSerializer(serializers.Serializer):
    identifier=serializers.CharField(max_length=254)
    password=serializers.CharField(write_only=True)
    role=serializers.ChoiceField(choices=User.Role.choices)
    def validate_identifier(self,value):
        return value.strip()
