from rest_framework import serializers

from .models import Page


class PageSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Page
        fields = ["id", "slug", "title", "body", "type", "updated_at"]


class PageAdminSerializer(serializers.ModelSerializer):
    """Full page view for the super-admin CMS (includes is_active + sort_order)."""

    id = serializers.CharField(read_only=True)

    class Meta:
        model = Page
        fields = ["id", "slug", "title", "body", "type", "is_active",
                  "sort_order", "updated_at"]


class PageWriteSerializer(serializers.Serializer):
    slug = serializers.SlugField(required=False)
    title = serializers.CharField(max_length=200)
    body = serializers.CharField(allow_blank=True, required=False)
    type = serializers.CharField(required=False)
    is_active = serializers.BooleanField(required=False)
    sort_order = serializers.IntegerField(required=False)
