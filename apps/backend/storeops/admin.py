from django.contrib import admin

from .models import StaffAttendance, StoreStaff


@admin.register(StoreStaff)
class StoreStaffAdmin(admin.ModelAdmin):
    list_display = ("user", "store", "staff_role", "is_active", "created_at")
    list_filter = ("staff_role", "is_active", "store")
    search_fields = ("user__phone", "user__name", "employee_code")
    autocomplete_fields = ()
    raw_id_fields = ("user", "store")


@admin.register(StaffAttendance)
class StaffAttendanceAdmin(admin.ModelAdmin):
    list_display = ("staff", "date", "check_in_at", "check_out_at")
    list_filter = ("date",)
    raw_id_fields = ("staff",)
