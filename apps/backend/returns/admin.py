from django.contrib import admin

from .models import ReturnItem, ReturnRequest


class ReturnItemInline(admin.TabularInline):
    model = ReturnItem
    extra = 0


@admin.register(ReturnRequest)
class ReturnRequestAdmin(admin.ModelAdmin):
    list_display = ["code", "user", "order", "status", "refund_amount", "created_at"]
    list_filter = ["status"]
    search_fields = ["code", "order__code", "user__phone", "user__name"]
    inlines = [ReturnItemInline]
    readonly_fields = ["code"]


@admin.register(ReturnItem)
class ReturnItemAdmin(admin.ModelAdmin):
    list_display = ["return_request", "product_name", "quantity", "amount"]
    search_fields = ["return_request__code", "product_name"]
