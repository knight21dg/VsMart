from django.contrib import admin

from .models import DeliveryLocation, DeliveryTask


@admin.register(DeliveryTask)
class DeliveryTaskAdmin(admin.ModelAdmin):
    list_display = ["id", "order", "agent", "status", "started_at", "delivered_at", "created_at"]
    list_filter = ["status"]
    search_fields = ["order__code", "agent__phone", "agent__name"]
    readonly_fields = ["created_at", "updated_at"]


@admin.register(DeliveryLocation)
class DeliveryLocationAdmin(admin.ModelAdmin):
    list_display = ["id", "agent", "latitude", "longitude", "at"]
    list_filter = ["agent"]
