from decimal import Decimal, InvalidOperation

from rest_framework import serializers

from core.pricing import (
    GST_SLABS,
    gst_fraction_to_pct,
    gst_pct_to_fraction,
    gst_slab_error,
)

from .models import PlatformConfig


class PlatformConfigSerializer(serializers.ModelSerializer):
    """Platform money settings.

    ``gst_rate`` is stored as a fraction (0.18) because that is what the pricing
    maths multiplies by, but it is *exposed and accepted as a percentage* (18) —
    the number on the invoice, the number in the statute, and the number the
    operator types. The settings form used to be labelled "GST rate (0–1)",
    which is how 0.18-style values leaked into product records too. Conversion
    happens here and nowhere else.
    """

    gst_rate = serializers.SerializerMethodField()

    class Meta:
        model = PlatformConfig
        fields = [
            "gst_rate", "delivery_fee", "free_delivery_threshold", "min_order",
            "platform_fee_type", "platform_fee_value", "platform_fee_cap",
            "credit_default_limit", "late_fee_flat", "late_fee_percent",
            "min_collection_amount",
            "currency", "support_phone", "support_email", "updated_at",
        ]
        read_only_fields = ["updated_at"]

    def get_gst_rate(self, obj) -> Decimal:
        return gst_fraction_to_pct(obj.gst_rate)

    def to_internal_value(self, data):
        """Accept the percentage the client sends and convert it to the stored
        fraction. ``gst_rate`` is a SerializerMethodField (read-only), so the
        write side has to be handled explicitly."""
        validated = super().to_internal_value(data)
        raw = data.get("gst_rate", data.get("gstRate"))
        if raw is not None and raw != "":
            try:
                pct = Decimal(str(raw))
            except (InvalidOperation, TypeError, ValueError):
                raise serializers.ValidationError(
                    {"gst_rate": ["Enter a GST percentage, e.g. 18."]}
                )
            if pct not in GST_SLABS:
                raise serializers.ValidationError({"gst_rate": [gst_slab_error(pct)]})
            validated["gst_rate"] = gst_pct_to_fraction(pct)
        return validated
