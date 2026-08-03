from django.contrib import admin

from .models import AgentIncentive


@admin.register(AgentIncentive)
class AgentIncentiveAdmin(admin.ModelAdmin):
    list_display = ["agent", "amount", "reason", "period", "created_at"]
    list_filter = ["period"]
    search_fields = ["agent__phone", "agent__name", "reason"]
