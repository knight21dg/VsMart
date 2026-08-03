from django.contrib import admin

from .models import PointsLedgerEntry


@admin.register(PointsLedgerEntry)
class PointsLedgerEntryAdmin(admin.ModelAdmin):
    list_display = ["user", "type", "points", "balance_after", "created_at"]
    list_filter = ["type"]
    search_fields = ["user__phone", "user__name", "note"]
    readonly_fields = [f.name for f in PointsLedgerEntry._meta.fields]

    def has_add_permission(self, request):
        return False  # ledger is append-only via services, not the admin

    def has_change_permission(self, request, obj=None):
        return False
