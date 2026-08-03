from django.contrib import admin

from .models import Zone, ZoneAgent


class ZoneAgentInline(admin.TabularInline):
    model = ZoneAgent
    extra = 0


@admin.register(Zone)
class ZoneAdmin(admin.ModelAdmin):
    list_display = ["name", "radius_km", "is_active", "delivery_fee", "platform_fee_value"]
    list_filter = ["is_active"]
    search_fields = ["name"]
    inlines = [ZoneAgentInline]
