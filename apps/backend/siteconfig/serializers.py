from rest_framework import serializers

from .models import PlatformConfig


class PlatformConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = PlatformConfig
        fields = [
            "gst_rate", "delivery_fee", "free_delivery_threshold", "min_order",
            "platform_fee_type", "platform_fee_value", "platform_fee_cap",
            "credit_default_limit", "late_fee_flat", "late_fee_percent",
            "currency", "support_phone", "support_email", "updated_at",
        ]
        read_only_fields = ["updated_at"]
