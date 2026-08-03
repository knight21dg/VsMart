from django.contrib import admin

from .models import CashCollection, Payment, PaymentWebhookEvent


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ["id", "user", "purpose", "amount", "method", "status", "created_at"]
    list_filter = ["purpose", "method", "status", "gateway"]
    search_fields = ["user__phone", "gateway_payment_id", "gateway_order_id"]


@admin.register(CashCollection)
class CashCollectionAdmin(admin.ModelAdmin):
    list_display = ["id", "user", "agent", "amount", "status", "collected_at"]
    list_filter = ["status"]
    search_fields = ["user__phone", "agent__phone"]


@admin.register(PaymentWebhookEvent)
class WebhookEventAdmin(admin.ModelAdmin):
    list_display = ["event_id", "gateway", "signature_ok", "processed", "received_at"]
    readonly_fields = [f.name for f in PaymentWebhookEvent._meta.fields]
