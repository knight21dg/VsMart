from django.contrib import admin

from .models import VerificationEvidence, VerificationTask


class EvidenceInline(admin.TabularInline):
    model = VerificationEvidence
    extra = 0


@admin.register(VerificationTask)
class VerificationTaskAdmin(admin.ModelAdmin):
    list_display = ["id", "customer", "agent", "type", "status", "submitted_at",
                    "created_at"]
    list_filter = ["type", "status"]
    search_fields = ["customer__phone", "customer__name", "agent__phone"]
    inlines = [EvidenceInline]


@admin.register(VerificationEvidence)
class VerificationEvidenceAdmin(admin.ModelAdmin):
    list_display = ["id", "task", "kind", "photo_key", "latitude", "longitude",
                    "created_at"]
    list_filter = ["kind"]
