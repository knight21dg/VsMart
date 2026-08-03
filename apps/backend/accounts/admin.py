from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import AgentProfile, AuditLog, DeviceToken, User


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ["-created_at"]
    list_display = ["phone", "name", "role", "kyc_status", "credit_enabled", "is_active"]
    list_filter = ["role", "kyc_status", "credit_enabled", "is_active"]
    search_fields = ["phone", "name", "email"]
    readonly_fields = ["created_at", "last_login"]
    filter_horizontal = ["groups", "user_permissions"]
    fieldsets = (
        (None, {"fields": ("phone", "password")}),
        ("Profile", {"fields": ("name", "email", "avatar_url")}),
        ("Role & status", {"fields": ("role", "kyc_status", "credit_enabled", "is_active")}),
        ("Permissions", {"fields": ("is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Dates", {"fields": ("last_login", "created_at")}),
    )
    add_fieldsets = (
        (None, {"classes": ("wide",), "fields": ("phone", "name", "role", "password1", "password2")}),
    )


@admin.register(AgentProfile)
class AgentProfileAdmin(admin.ModelAdmin):
    list_display = ["code", "user", "is_available"]
    search_fields = ["code", "user__phone", "user__name"]


@admin.register(AuditLog)
class AuditLogAdmin(admin.ModelAdmin):
    list_display = ["created_at", "actor", "action", "target_type", "target_id"]
    list_filter = ["action", "target_type"]
    search_fields = ["actor__phone", "action", "target_id"]
    readonly_fields = [f.name for f in AuditLog._meta.fields]

    def has_add_permission(self, request):
        return False


admin.site.register(DeviceToken)

admin.site.site_header = "VS Mart Admin"
admin.site.site_title = "VS Mart"
admin.site.index_title = "Operations Console"
