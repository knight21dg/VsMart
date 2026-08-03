from rest_framework import serializers

from payments.models import CashCollection


class CollectionTaskSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    customer = serializers.SerializerMethodField()
    customer_phone = serializers.CharField(source="user.phone", read_only=True)
    remaining = serializers.SerializerMethodField()
    # The pending amount-bound OTP (requested but not yet verified), so the app
    # can resume the confirm step after a reload.
    otp_pending = serializers.SerializerMethodField()
    otp_amount = serializers.SerializerMethodField()
    # Customer location (their default address) so the agent app can map the visit.
    customer_lat = serializers.SerializerMethodField()
    customer_lng = serializers.SerializerMethodField()
    address = serializers.SerializerMethodField()

    class Meta:
        model = CashCollection
        fields = [
            "id", "status", "amount", "collected_amount", "remaining",
            "is_priority", "escalated", "attempt_no", "otp_verified",
            "otp_pending", "otp_amount",
            "manual_verification_required", "failure_reason",
            "customer", "customer_phone", "customer_lat", "customer_lng", "address",
            "assigned_at", "accepted_at",
            "en_route_at", "reached_at", "collected_at", "created_at",
        ]

    def get_customer(self, obj):
        return getattr(obj.user, "name", "") or obj.user.phone

    def _addr(self, obj):
        """The customer's default (else most recent) address — same resolution the
        dispatch engine uses to place a collection stop."""
        if not hasattr(obj, "_resolved_addr"):
            from addresses.models import Address

            obj._resolved_addr = (
                Address.objects.filter(user_id=obj.user_id, is_default=True).first()
                or Address.objects.filter(user_id=obj.user_id).first()
            )
        return obj._resolved_addr

    def get_customer_lat(self, obj):
        addr = self._addr(obj)
        return float(addr.latitude) if addr and addr.latitude is not None else None

    def get_customer_lng(self, obj):
        addr = self._addr(obj)
        return float(addr.longitude) if addr and addr.longitude is not None else None

    def get_address(self, obj):
        addr = self._addr(obj)
        return addr.formatted if addr else ""

    def get_remaining(self, obj):
        return obj.remaining

    def _otp(self, obj):
        otp = getattr(obj, "collection_otp", None)
        return otp if (otp and not otp.verified and not otp.locked) else None

    def get_otp_pending(self, obj):
        return self._otp(obj) is not None

    def get_otp_amount(self, obj):
        otp = self._otp(obj)
        return otp.amount if otp else None


class CollectSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False)


class CollectionOtpSerializer(serializers.Serializer):
    otp = serializers.CharField(max_length=6)


class FailCollectionSerializer(serializers.Serializer):
    reason_code = serializers.ChoiceField(choices=[
        "CUSTOMER_NOT_AVAILABLE", "FAILED_ADDRESS_NOT_FOUND",
        "FAILED_CUSTOMER_REJECTED", "FAILED_SECURITY_CONCERN",
    ], default="CUSTOMER_NOT_AVAILABLE")
    note = serializers.CharField(required=False, allow_blank=True)
