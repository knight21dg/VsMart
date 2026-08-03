from django.contrib import admin

from .models import Referral


@admin.register(Referral)
class ReferralAdmin(admin.ModelAdmin):
    list_display = ["code", "referrer", "referee", "reward", "status", "created_at"]
    list_filter = ["status"]
    search_fields = ["code", "referrer__phone", "referee__phone"]
