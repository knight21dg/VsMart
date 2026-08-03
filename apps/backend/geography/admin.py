from django.contrib import admin

from .models import Area, District, GeoZone, State, Village, Warehouse


@admin.register(State)
class StateAdmin(admin.ModelAdmin):
    list_display = ["name", "code"]
    search_fields = ["name", "code"]


@admin.register(District)
class DistrictAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "state"]
    list_filter = ["state"]
    search_fields = ["name", "code"]


@admin.register(GeoZone)
class GeoZoneAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "district"]
    list_filter = ["district"]
    search_fields = ["name", "code"]


@admin.register(Area)
class AreaAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "zone"]
    list_filter = ["zone"]
    search_fields = ["name", "code"]


@admin.register(Village)
class VillageAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "area"]
    list_filter = ["area"]
    search_fields = ["name", "code"]


@admin.register(Warehouse)
class WarehouseAdmin(admin.ModelAdmin):
    list_display = ["name", "code", "area", "is_active"]
    list_filter = ["is_active", "area"]
    search_fields = ["name", "code"]
