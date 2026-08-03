from django.contrib import admin

from .models import (
    DeliveryAssignment,
    Order,
    OrderItem,
    OrderStatusEvent,
    OrderTracking,
)


class OrderItemInline(admin.TabularInline):
    model = OrderItem
    extra = 0


class StatusEventInline(admin.TabularInline):
    model = OrderStatusEvent
    extra = 0


@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ["code", "user", "status", "payment_method", "payment_status", "total", "placed_at"]
    list_filter = ["status", "payment_method", "payment_status"]
    search_fields = ["code", "user__phone", "user__name"]
    inlines = [OrderItemInline, StatusEventInline]
    readonly_fields = ["code", "placed_at"]


@admin.register(DeliveryAssignment)
class DeliveryAssignmentAdmin(admin.ModelAdmin):
    list_display = ["order", "agent", "status", "assigned_at"]
    list_filter = ["status"]


admin.site.register(OrderTracking)
