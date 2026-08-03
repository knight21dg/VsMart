from django.contrib import admin

from .models import (
    CreditAccount,
    CreditBureauReport,
    CreditLedgerEntry,
    FamilyGroup,
    FamilyMember,
    Statement,
)


@admin.register(CreditBureauReport)
class CreditBureauReportAdmin(admin.ModelAdmin):
    list_display = ["created_at", "user", "score", "band", "status", "provider", "source"]
    list_filter = ["status", "band", "source", "provider"]
    search_fields = ["user__phone", "user__name", "mobile", "reference_id"]
    readonly_fields = [f.name for f in CreditBureauReport._meta.fields]

    def has_add_permission(self, request):
        return False  # reports are written by the bureau service, not by hand

    def has_change_permission(self, request, obj=None):
        return False  # append-only history


@admin.register(CreditAccount)
class CreditAccountAdmin(admin.ModelAdmin):
    list_display = ["user", "credit_limit", "outstanding", "available", "vs_score", "status"]
    search_fields = ["user__phone", "user__name"]
    list_filter = ["status"]
    readonly_fields = ["outstanding"]


@admin.register(CreditLedgerEntry)
class CreditLedgerEntryAdmin(admin.ModelAdmin):
    list_display = ["created_at", "account", "type", "amount", "balance_after", "note"]
    list_filter = ["type"]
    search_fields = ["account__user__phone", "note"]
    readonly_fields = [f.name for f in CreditLedgerEntry._meta.fields]

    def has_add_permission(self, request):
        return False  # ledger is append-only via services, not the admin

    def has_change_permission(self, request, obj=None):
        return False


@admin.register(Statement)
class StatementAdmin(admin.ModelAdmin):
    list_display = ["account", "period", "period_end", "closing_balance", "due_date", "status"]
    list_filter = ["period", "status"]


class FamilyMemberInline(admin.TabularInline):
    model = FamilyMember
    extra = 0


@admin.register(FamilyGroup)
class FamilyGroupAdmin(admin.ModelAdmin):
    list_display = ["primary_user", "shared_limit"]
    inlines = [FamilyMemberInline]
