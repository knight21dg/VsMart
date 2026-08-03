from django.contrib import admin

from .models import CustomerNote


@admin.register(CustomerNote)
class CustomerNoteAdmin(admin.ModelAdmin):
    list_display = ("customer", "author", "created_at")
    search_fields = ("customer__phone", "customer__name", "body")
    raw_id_fields = ("customer", "author")
