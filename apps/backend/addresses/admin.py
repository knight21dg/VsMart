from django.contrib import admin

from .models import Address


@admin.register(Address)
class AddressAdmin(admin.ModelAdmin):
    list_display = ["name", "user", "city", "pincode", "is_default"]
    search_fields = ["name", "phone", "pincode", "user__phone"]
    list_filter = ["is_default", "state"]
