from django.contrib import admin

from .models import Store


@admin.register(Store)
class StoreAdmin(admin.ModelAdmin):
    list_display = ("code", "name", "status", "phone", "warehouse")
    list_filter = ("status",)
    search_fields = ("code", "name", "address", "phone")
