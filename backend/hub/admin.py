from django.contrib import admin
from .models import Preferences,SavedPlace,Contact,BusinessProfile,SupportTicket,SupportMessage,PromoCode,ClaimedPromo
for model in [Preferences,SavedPlace,Contact,BusinessProfile,SupportTicket,SupportMessage,PromoCode,ClaimedPromo]:
    admin.site.register(model)
