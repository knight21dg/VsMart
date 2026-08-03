from rest_framework import serializers

from core.serializer_fields import CoordinateField

from .models import DeliveryLocation, DeliveryTask


class DeliveryTaskSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    order_code = serializers.CharField(source="order.code", read_only=True)
    customer = serializers.SerializerMethodField()
    address = serializers.SerializerMethodField()
    amount = serializers.DecimalField(source="order.total", max_digits=12,
                                      decimal_places=2, read_only=True)
    payment_method = serializers.CharField(source="order.payment_method", read_only=True)
    payment_status = serializers.CharField(source="order.payment_status", read_only=True)
    item_count = serializers.SerializerMethodField()
    earnings = serializers.SerializerMethodField()

    class Meta:
        model = DeliveryTask
        fields = [
            "id", "order_code", "status", "attempt_no", "customer", "address",
            "dest_lat", "dest_lng", "distance_km", "amount", "payment_method",
            "payment_status", "item_count", "otp_verified",
            "manual_verification_required", "failure_reason", "photo_key",
            "assigned_at", "accepted_at", "picked_up_at", "out_for_delivery_at",
            "reached_at", "delivered_at", "earnings", "created_at",
        ]

    def get_customer(self, obj):
        snap = obj.order.address_snapshot or {}
        return {"name": snap.get("name", ""), "phone": snap.get("phone", "")}

    def get_address(self, obj):
        return (obj.order.address_snapshot or {}).get("formatted", "")

    def get_item_count(self, obj):
        return obj.order.items.count()

    def get_earnings(self, obj):
        e = getattr(obj, "earnings", None)
        return float(e.total) if e else None


class OtpSerializer(serializers.Serializer):
    otp = serializers.CharField(max_length=6)


class PhotoSerializer(serializers.Serializer):
    # Either upload the image file directly (multipart `photo` → media engine) OR
    # pass a loose `photo_key` string (legacy). At least one is required.
    photo = serializers.ImageField(required=False)
    photo_key = serializers.CharField(max_length=200, required=False, allow_blank=True)
    latitude = CoordinateField(required=False)
    longitude = CoordinateField(required=False)

    def validate(self, attrs):
        if not attrs.get("photo") and not attrs.get("photo_key"):
            raise serializers.ValidationError(
                {"photo": "Provide a photo file or a photo_key."}
            )
        return attrs


class LocationSerializer(serializers.Serializer):
    latitude = CoordinateField()
    longitude = CoordinateField()
    task_id = serializers.IntegerField(required=False)
    accuracy_m = serializers.DecimalField(max_digits=7, decimal_places=2, required=False)


class ArriveSerializer(serializers.Serializer):
    latitude = CoordinateField()
    longitude = CoordinateField()


class FailSerializer(serializers.Serializer):
    reason_code = serializers.ChoiceField(choices=[
        "FAILED_CUSTOMER_UNREACHABLE", "FAILED_ADDRESS_NOT_FOUND",
        "FAILED_CUSTOMER_REJECTED", "FAILED_OTP_VERIFICATION",
        "FAILED_SECURITY_CONCERN",
    ])
    note = serializers.CharField(required=False, allow_blank=True)
    photo_key = serializers.CharField(required=False, allow_blank=True)
    latitude = CoordinateField(required=False)
    longitude = CoordinateField(required=False)


class DeliveryLocationSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = DeliveryLocation
        fields = ["id", "latitude", "longitude", "at"]
