from rest_framework import serializers

from .models import Faq, SupportTicket, TicketMessage


class TicketListSerializer(serializers.ModelSerializer):
    id = serializers.CharField(source="code", read_only=True)

    class Meta:
        model = SupportTicket
        fields = ["id", "category", "priority", "subject", "status", "created_at"]


class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.CharField(source="sender.name", read_only=True)

    class Meta:
        model = TicketMessage
        fields = ["sender_name", "body", "attachments", "created_at"]


class TicketDetailSerializer(serializers.ModelSerializer):
    id = serializers.CharField(source="code", read_only=True)
    messages = MessageSerializer(many=True, read_only=True)

    class Meta:
        model = SupportTicket
        fields = [
            "id", "category", "priority", "subject", "status",
            "order_code", "created_at", "messages",
        ]


class TicketCreateSerializer(serializers.Serializer):
    category = serializers.CharField()
    priority = serializers.ChoiceField(
        choices=["low", "medium", "high"], required=False
    )
    subject = serializers.CharField()
    order_code = serializers.CharField(required=False, allow_blank=True)


class MessageCreateSerializer(serializers.Serializer):
    body = serializers.CharField()
    attachments = serializers.JSONField(required=False)


class FaqSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Faq
        fields = ["id", "category", "question", "answer"]
