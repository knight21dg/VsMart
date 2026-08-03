from django.contrib import admin

from .models import AnalyticsEvent, StockAdjustment


@admin.register(AnalyticsEvent)
class AnalyticsEventAdmin(admin.ModelAdmin):
    list_display = ["id", "created_at", "type", "actor"]
    list_filter = ["type"]
    readonly_fields = [f.name for f in AnalyticsEvent._meta.fields]

    def has_add_permission(self, request):
        return False


@admin.register(StockAdjustment)
class StockAdjustmentAdmin(admin.ModelAdmin):
    list_display = ["created_at", "product", "delta", "new_count", "by", "reason"]
    search_fields = ["product__name"]
    readonly_fields = [f.name for f in StockAdjustment._meta.fields]

    def has_add_permission(self, request):
        return False
