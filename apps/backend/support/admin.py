from django.contrib import admin

from .models import Faq, SupportTicket, TicketMessage


class TicketMessageInline(admin.TabularInline):
    model = TicketMessage
    extra = 0


@admin.register(SupportTicket)
class SupportTicketAdmin(admin.ModelAdmin):
    list_display = ["code", "user", "category", "priority", "subject", "status", "assigned_to", "created_at"]
    list_filter = ["status", "priority", "category"]
    search_fields = ["code", "subject", "user__phone", "user__name", "order_code"]
    inlines = [TicketMessageInline]
    readonly_fields = ["code"]


@admin.register(TicketMessage)
class TicketMessageAdmin(admin.ModelAdmin):
    list_display = ["ticket", "sender", "created_at"]
    search_fields = ["ticket__code", "sender__phone", "body"]


@admin.register(Faq)
class FaqAdmin(admin.ModelAdmin):
    list_display = ["question", "category", "sort_order", "is_active"]
    list_filter = ["category", "is_active"]
    search_fields = ["question", "answer"]
