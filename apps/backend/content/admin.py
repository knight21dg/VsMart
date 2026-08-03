from django.contrib import admin

from .models import Page


@admin.register(Page)
class PageAdmin(admin.ModelAdmin):
    list_display = ["slug", "title", "type", "is_active"]
    list_filter = ["type", "is_active"]
    search_fields = ["slug", "title"]
