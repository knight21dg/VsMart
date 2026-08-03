from django.contrib import admin

from .models import Invoice, InvoiceItem, Receipt


class InvoiceItemInline(admin.TabularInline):
    model = InvoiceItem
    extra = 0


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ["number", "user", "amount", "gst", "status", "issued_at", "created_at"]
    list_filter = ["status"]
    search_fields = ["number", "user__phone", "user__name"]
    inlines = [InvoiceItemInline]
    readonly_fields = ["number", "created_at"]


@admin.register(Receipt)
class ReceiptAdmin(admin.ModelAdmin):
    list_display = ["number", "user", "amount", "method", "issued_at", "created_at"]
    list_filter = ["method"]
    search_fields = ["number", "user__phone", "user__name"]
    readonly_fields = ["number", "created_at"]
