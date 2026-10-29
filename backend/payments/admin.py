from django.contrib import admin
from .models import DriverUPIProfile,DriverUPIChange,DirectUPIPayment,PaymentAudit

class ReadOnlyPaymentAdmin(admin.ModelAdmin):
    def get_readonly_fields(self,request,obj=None):return tuple(f.name for f in self.model._meta.fields)
    def has_add_permission(self,request):return False
    def has_delete_permission(self,request,obj=None):return False
for model in [DriverUPIProfile,DriverUPIChange,DirectUPIPayment,PaymentAudit]:
    admin.site.register(model,ReadOnlyPaymentAdmin)
