from django.contrib import admin

from .models import (
    CashDrawer,
    DayClosing,
    HeldCart,
    POSPayment,
    POSRefund,
    POSSession,
    POSTransaction,
    POSTransactionItem,
)


@admin.register(POSSession)
class POSSessionAdmin(admin.ModelAdmin):
    list_display = ["id", "cashier", "warehouse", "status", "opening_cash",
                    "opened_at", "closed_at"]
    list_filter = ["status", "warehouse"]


class POSTransactionItemInline(admin.TabularInline):
    model = POSTransactionItem
    extra = 0


class POSPaymentInline(admin.TabularInline):
    model = POSPayment
    extra = 0


@admin.register(POSTransaction)
class POSTransactionAdmin(admin.ModelAdmin):
    list_display = ["code", "type", "session", "customer", "total", "credit_used",
                    "payment_status", "created_at"]
    list_filter = ["type", "payment_status"]
    search_fields = ["code"]
    inlines = [POSTransactionItemInline, POSPaymentInline]


@admin.register(POSRefund)
class POSRefundAdmin(admin.ModelAdmin):
    list_display = ["transaction", "method", "amount", "created_at"]


@admin.register(CashDrawer)
class CashDrawerAdmin(admin.ModelAdmin):
    list_display = ["session", "type", "amount", "note", "created_at"]
    list_filter = ["type"]


@admin.register(DayClosing)
class DayClosingAdmin(admin.ModelAdmin):
    list_display = ["session", "expected_cash", "counted_cash", "variance",
                    "total_sales", "transaction_count", "closed_at"]


@admin.register(HeldCart)
class HeldCartAdmin(admin.ModelAdmin):
    list_display = ["id", "session", "label", "customer", "created_at"]
