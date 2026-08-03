from rest_framework import serializers

from .imaging import image_urls
from .models import Coupon, Offer


class OfferSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    category_id = serializers.CharField(read_only=True)
    subcategory_id = serializers.CharField(read_only=True)
    image = serializers.SerializerMethodField()

    class Meta:
        model = Offer
        fields = [
            "id", "type", "placement", "title", "subtitle", "code", "image_url",
            "badge", "discount_percent", "deal_price", "original_price",
            "product_id", "category_id", "subcategory_id", "is_fallback", "valid_to",
            # v1.0 additions
            "title_te", "title_hi", "subtitle_te", "subtitle_hi",
            "action", "payload", "is_pinned", "image",
            # v1.1 overlay: CTA pill + how the copy is painted over the artwork
            "cta_text", "cta_text_te", "cta_text_hi",
            "text_theme", "text_position", "accent_color",
        ]

    def get_image(self, obj):
        """Resolved WebP size variants + focal point. Festival per-language overrides
        ride under ``te``/``hi``. Falls back to the legacy pasted ``image_url``."""
        if obj.image_uuid:
            data = {
                **image_urls(obj.image_uuid, obj.image_version),
                "focus": {"x": obj.focus_x, "y": obj.focus_y},
            }
            if obj.image_te:
                data["te"] = image_urls(obj.image_te, obj.image_version)
            if obj.image_hi:
                data["hi"] = image_urls(obj.image_hi, obj.image_version)
            return data
        if obj.image_url:
            return {"legacy_url": obj.image_url}
        return None


class CouponSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Coupon
        fields = ["id", "code", "discount_type", "value", "min_order",
                  "max_discount", "valid_to"]
