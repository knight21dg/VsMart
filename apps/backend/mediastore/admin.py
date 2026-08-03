from django.contrib import admin

from .models import MediaAsset


@admin.register(MediaAsset)
class MediaAssetAdmin(admin.ModelAdmin):
    list_display = (
        "id", "category", "visibility", "owner", "content_type",
        "size_bytes", "created_at",
    )
    list_filter = ("visibility", "category", "content_type")
    search_fields = ("id", "original_name")
    readonly_fields = ("id", "checksum", "size_bytes", "width", "height")
