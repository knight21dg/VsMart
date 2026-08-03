from rest_framework import serializers

from .models import Notification, NotificationPreference


class NotificationSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    is_read = serializers.SerializerMethodField()

    class Meta:
        model = Notification
        fields = ["id", "type", "title", "body", "data", "read_at",
                  "created_at", "is_read"]

    def get_is_read(self, obj):
        return obj.read_at is not None


class NotificationPreferenceSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = NotificationPreference
        fields = [
            "id", "push", "sms", "whatsapp", "email", "reminder_time",
            "reminder_enabled", "reminder_offset_days", "categories",
        ]
