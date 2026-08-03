from django.contrib import admin

from .models import Notification, NotificationPreference


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ["id", "user", "type", "title", "read_at", "created_at"]
    list_filter = ["type", "read_at"]
    search_fields = ["title", "body", "user__phone", "user__name"]
    readonly_fields = ["created_at", "updated_at"]


@admin.register(NotificationPreference)
class NotificationPreferenceAdmin(admin.ModelAdmin):
    list_display = ["user", "push", "sms", "whatsapp", "email", "reminder_time"]
    list_filter = ["push", "sms", "whatsapp", "email"]
