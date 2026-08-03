from rest_framework import serializers

from core.serializer_fields import CoordinateField

from .models import VerificationEvidence, VerificationTask


class EvidenceSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    task_id = serializers.CharField(read_only=True)

    class Meta:
        model = VerificationEvidence
        fields = ["id", "task_id", "kind", "photo_key", "latitude", "longitude",
                  "created_at"]


class TaskListSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    customer_id = serializers.CharField(read_only=True)
    customer_name = serializers.CharField(source="customer.name", read_only=True)

    class Meta:
        model = VerificationTask
        fields = ["id", "customer_id", "customer_name", "type", "status", "note",
                  "created_at"]


class TaskDetailSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    customer_id = serializers.CharField(read_only=True)
    customer_name = serializers.CharField(source="customer.name", read_only=True)
    agent_id = serializers.CharField(read_only=True)
    evidence = EvidenceSerializer(many=True, read_only=True)

    class Meta:
        model = VerificationTask
        fields = ["id", "customer_id", "customer_name", "agent_id", "type", "status",
                  "note", "submitted_at", "created_at", "evidence"]


class SubmitSerializer(serializers.Serializer):
    note = serializers.CharField(required=False, allow_blank=True)
    decision = serializers.ChoiceField(choices=["approve", "reject"], required=False)


class PhotoSerializer(serializers.Serializer):
    task_id = serializers.IntegerField()
    # Legacy loose-string key. Optional now: the preferred path is a multipart
    # `file`/`photo` upload, ingested through the media engine in the view.
    photo_key = serializers.CharField(required=False, allow_blank=True)


class GpsSerializer(serializers.Serializer):
    task_id = serializers.IntegerField()
    latitude = CoordinateField()
    longitude = CoordinateField()
