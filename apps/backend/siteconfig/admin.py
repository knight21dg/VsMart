from django.contrib import admin

from .models import PlatformConfig


@admin.register(PlatformConfig)
class PlatformConfigAdmin(admin.ModelAdmin):
    list_display = ["__str__", "gst_rate", "delivery_fee", "platform_fee_type",
                    "platform_fee_value", "updated_at"]

    def has_add_permission(self, request):
        return not PlatformConfig.objects.exists()  # singleton

    def has_delete_permission(self, request, obj=None):
        return False
