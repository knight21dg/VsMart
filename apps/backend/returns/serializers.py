import json

from rest_framework import serializers

from .models import ReturnEvidence, ReturnItem, ReturnPickupTask, ReturnRequest


class ReturnItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReturnItem
        fields = [
            "id", "product_name", "quantity", "amount",
            "accepted_quantity", "accepted_amount",
        ]


class ReturnEvidenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = ReturnEvidence
        fields = ["id", "source", "captured_at"]


class ReturnRequestSerializer(serializers.ModelSerializer):
    id = serializers.CharField(source="code", read_only=True)
    order_code = serializers.CharField(source="order.code", read_only=True)
    items = ReturnItemSerializer(many=True, read_only=True)
    evidence = ReturnEvidenceSerializer(many=True, read_only=True)
    pickup = serializers.SerializerMethodField()

    class Meta:
        model = ReturnRequest
        fields = [
            "id", "order_code", "reason", "description", "status",
            "refund_amount", "created_at", "resolved_at", "items",
            "evidence", "pickup",
        ]

    def get_pickup(self, obj):
        """The live pickup task, so the customer can see who's coming."""
        task = next(
            (t for t in obj.pickup_tasks.all()
             if t.status not in ReturnPickupTask.TERMINAL),
            None,
        )
        if task is None:
            task = obj.pickup_tasks.first()
        if task is None:
            return None
        agent = task.agent
        return {
            "id": str(task.id),
            "status": task.status,
            "attemptNo": task.attempt_no,
            "reasonCode": task.reason_code,
            "agentName": getattr(agent, "name", "") if agent else "",
            "agentPhone": getattr(agent, "phone", "") if agent else "",
            "assignedAt": task.assigned_at,
            "completedAt": task.completed_at,
        }


class _JSONListField(serializers.ListField):
    """Accepts a real JSON list (application/json) or a JSON-encoded string
    (multipart, where every field arrives as text)."""

    def to_internal_value(self, data):
        if isinstance(data, (list, tuple)) and len(data) == 1 and isinstance(data[0], str):
            data = data[0]
        if isinstance(data, str):
            try:
                data = json.loads(data or "[]")
            except (TypeError, ValueError):
                raise serializers.ValidationError("Must be a JSON array.")
        return super().to_internal_value(data)


class ReturnCreateSerializer(serializers.Serializer):
    reason = serializers.CharField()
    description = serializers.CharField(required=False, allow_blank=True)
    items = _JSONListField(child=serializers.DictField(), required=False)
    # At least one photo of the item is mandatory — it's the evidence the pickup
    # agent inspects against at the door.
    photos = serializers.ListField(
        child=serializers.ImageField(), required=False, allow_empty=True
    )


class ReturnPickupTaskSerializer(serializers.ModelSerializer):
    return_code = serializers.CharField(source="return_request.code", read_only=True)
    order_code = serializers.CharField(
        source="return_request.order.code", read_only=True)
    reason = serializers.CharField(source="return_request.reason", read_only=True)
    description = serializers.CharField(
        source="return_request.description", read_only=True)
    refund_amount = serializers.DecimalField(
        source="return_request.refund_amount", max_digits=12, decimal_places=2,
        read_only=True)
    customer = serializers.SerializerMethodField()
    address = serializers.SerializerMethodField()
    items = serializers.SerializerMethodField()
    photos = serializers.SerializerMethodField()

    class Meta:
        model = ReturnPickupTask
        fields = [
            "id", "status", "attempt_no", "reason_code", "note",
            "dest_lat", "dest_lng", "reschedule_at",
            "assigned_at", "accepted_at", "en_route_at", "reached_at",
            "completed_at", "return_code", "order_code", "reason",
            "description", "refund_amount", "customer", "address", "items",
            "photos",
        ]

    def get_customer(self, obj):
        u = obj.return_request.user
        return {
            "name": getattr(u, "name", "") or "",
            "phone": getattr(u, "phone", "") or "",
        }

    def get_address(self, obj):
        order = obj.return_request.order
        return getattr(order, "address_snapshot", None) or {}

    def get_items(self, obj):
        return ReturnItemSerializer(obj.return_request.items.all(), many=True).data

    def get_photos(self, obj):
        """Evidence ids — the agent app streams each via the photo endpoint."""
        return [
            {"id": str(e.id), "source": e.source}
            for e in obj.return_request.evidence.all()
        ]


class AgentPhotoSerializer(serializers.Serializer):
    photo = serializers.ImageField(required=False)
    photo_key = serializers.CharField(max_length=200, required=False,
                                      allow_blank=True)
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6,
                                        required=False, allow_null=True)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6,
                                         required=False, allow_null=True)

    def validate(self, attrs):
        if not attrs.get("photo") and not attrs.get("photo_key"):
            raise serializers.ValidationError(
                {"photo": "Provide a photo file or a photo_key."})
        return attrs


class CompletePickupSerializer(serializers.Serializer):
    """`decisions` maps ReturnItem id → accepted quantity (partial accept)."""
    decisions = serializers.DictField(
        child=serializers.IntegerField(min_value=0), required=False)
    note = serializers.CharField(required=False, allow_blank=True)


class RejectPickupSerializer(serializers.Serializer):
    reason_code = serializers.ChoiceField(choices=ReturnPickupTask.ReasonCode.choices)
    note = serializers.CharField(required=False, allow_blank=True)


class ReschedulePickupSerializer(serializers.Serializer):
    reason_code = serializers.ChoiceField(
        choices=ReturnPickupTask.ReasonCode.choices, required=False)
    note = serializers.CharField(required=False, allow_blank=True)
    at = serializers.DateTimeField(required=False, allow_null=True)
