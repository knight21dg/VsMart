from django.contrib import admin

from .models import KycApplication, KycDocument, VerificationStep


class DocumentInline(admin.TabularInline):
    model = KycDocument
    extra = 0


class StepInline(admin.TabularInline):
    model = VerificationStep
    extra = 0


@admin.register(KycApplication)
class KycApplicationAdmin(admin.ModelAdmin):
    list_display = ["user", "status", "submitted_at", "reviewed_by", "reviewed_at"]
    list_filter = ["status"]
    search_fields = ["user__phone", "user__name"]
    inlines = [DocumentInline, StepInline]
