from rest_framework import serializers

from .models import DeliveryAssignment, Order, OrderItem, OrderStatusEvent, OrderTracking


class OrderItemSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.CharField(read_only=True)
    line_total = serializers.DecimalField(max_digits=12, decimal_places=2, read_only=True)

    class Meta:
        model = OrderItem
        fields = ["id", "product_id", "name", "brand", "unit", "image_url",
                  "price", "mrp", "quantity", "line_total"]


class StatusEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = OrderStatusEvent
        fields = ["status", "note", "at"]


class OrderListSerializer(serializers.ModelSerializer):
    id = serializers.CharField(source="code", read_only=True)
    item_count = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = ["id", "status", "placed_at", "payment_method", "payment_status",
                  "total", "item_count"]

    def get_item_count(self, obj):
        return obj.items.count()


class OrderDetailSerializer(serializers.ModelSerializer):
    id = serializers.CharField(source="code", read_only=True)
    items = OrderItemSerializer(many=True, read_only=True)
    timeline = StatusEventSerializer(many=True, read_only=True)
    # Money actually moved, so a cancelled order can say whether the refund has
    # been paid. Nothing exposed this before: the customer saw status=cancelled
    # and had no way to tell if their money had come back.
    amount_paid = serializers.SerializerMethodField()
    amount_refunded = serializers.SerializerMethodField()

    class Meta:
        model = Order
        fields = [
            "id", "status", "placed_at", "estimated_delivery", "delivery_slot",
            "address_snapshot", "payment_method", "payment_status",
            "subtotal", "delivery_fee", "gst", "platform_fee", "discount", "total",
            "credit_used", "credit_plan", "credit_due_date", "coupon_code",
            "amount_paid", "amount_refunded",
            "items", "timeline",
        ]

    def get_amount_paid(self, obj):
        """Net of refunds — what the customer is currently out of pocket through a
        payment instrument. Excludes the VS Credit leg, which is reversed in the
        credit ledger rather than refunded."""
        from .services import collected_amount

        return collected_amount(obj)

    def get_amount_refunded(self, obj):
        from django.db.models import Sum

        from payments.models import Payment

        return Payment.objects.filter(
            order=obj, purpose=Payment.Purpose.REFUND,
            status=Payment.Status.SUCCESS,
        ).aggregate(total=Sum("amount"))["total"] or 0


class TrackingSerializer(serializers.ModelSerializer):
    order_id = serializers.CharField(source="order.code", read_only=True)
    status = serializers.CharField(source="order.status", read_only=True)
    # Real endpoints of the trip so the customer map draws the actual
    # store → delivery-address route (not hardcoded/derived coordinates).
    store_lat = serializers.SerializerMethodField()
    store_lng = serializers.SerializerMethodField()
    dest_lat = serializers.SerializerMethodField()
    dest_lng = serializers.SerializerMethodField()

    class Meta:
        model = OrderTracking
        fields = [
            "order_id", "status", "agent_name", "agent_phone", "agent_photo_url",
            "latitude", "longitude", "eta",
            "store_lat", "store_lng", "dest_lat", "dest_lng",
        ]

    def get_store_lat(self, obj):
        st = getattr(obj.order, "store", None)
        return float(st.latitude) if st and st.latitude is not None else None

    def get_store_lng(self, obj):
        st = getattr(obj.order, "store", None)
        return float(st.longitude) if st and st.longitude is not None else None

    def _snap(self, obj):
        return obj.order.address_snapshot or {}

    def get_dest_lat(self, obj):
        v = self._snap(obj).get("latitude") or self._snap(obj).get("lat")
        try:
            return float(v) if v is not None else None
        except (TypeError, ValueError):
            return None

    def get_dest_lng(self, obj):
        v = self._snap(obj).get("longitude") or self._snap(obj).get("lng")
        try:
            return float(v) if v is not None else None
        except (TypeError, ValueError):
            return None


class CheckoutSerializer(serializers.Serializer):
    address_id = serializers.IntegerField()
    payment_method = serializers.ChoiceField(
        choices=["cod", "upi", "card", "netbanking", "credit"]
    )
    delivery_slot = serializers.CharField(required=False, allow_blank=True)
    coupon_code = serializers.CharField(required=False, allow_blank=True)
    # VS Credit repayment plan (only used when payment_method == "credit").
    credit_plan = serializers.ChoiceField(
        choices=["weekend", "month_end"], required=False, allow_blank=True
    )


class DeliveryStatusSerializer(serializers.Serializer):
    status = serializers.ChoiceField(choices=["picked", "delivered", "failed"])
    note = serializers.CharField(required=False, allow_blank=True)
