from django.urls import path
from .views import AccountView,PreferencesView,EmailChangeView,CollectionView,TicketsView,PromotionsView,PrivacyView,MapLookupView
urlpatterns=[
 path('account/',AccountView.as_view(),name='hub-account'),
 path('preferences/',PreferencesView.as_view(),name='hub-preferences'),
 path('email/',EmailChangeView.as_view(),name='hub-email'),
 path('tickets/',TicketsView.as_view(),name='hub-tickets'),
 path('tickets/<int:ticket_id>/',TicketsView.as_view(),name='hub-ticket'),
 path('promotions/',PromotionsView.as_view(),name='hub-promotions'),
 path('privacy/',PrivacyView.as_view(),name='hub-privacy'),
 path('map/search/',MapLookupView.as_view(),name='hub-map-search'),
 path('collections/<str:collection>/',CollectionView.as_view(),name='hub-collection'),
 path('collections/<str:collection>/<int:item_id>/',CollectionView.as_view(),name='hub-item'),
]
