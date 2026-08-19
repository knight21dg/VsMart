from rest_framework import serializers

from .models import AgentIncentive


class AgentProfileSerializer(serializers.Serializer):
    id = serializers.CharField(read_only=True)
    code = serializers.CharField(read_only=True)
    assigned_pincodes = serializers.JSONField()
    is_available = serializers.BooleanField()
    name = serializers.CharField(read_only=True)
    phone = serializers.CharField(read_only=True)
    # Set by the store (Store panel), not by the agent — read-only here. Drives
    # whether the app shows this agent per-task/lifetime earnings at all.
    employment_type = serializers.CharField(read_only=True)
    # Empty until the agent completes the first-login photo capture — the app
    # uses that to decide whether to show the capture screen at all.
    avatar_url = serializers.CharField(read_only=True, allow_blank=True)


class AgentProfileUpdateSerializer(serializers.Serializer):
    is_available = serializers.BooleanField(required=False)
    assigned_pincodes = serializers.JSONField(required=False)


class AgentPerformanceDaySerializer(serializers.Serializer):
    date = serializers.CharField()
    deliveries = serializers.IntegerField()
    collections = serializers.IntegerField()
    verifications = serializers.IntegerField()


class AgentPerformanceSerializer(serializers.Serializer):
    deliveries_completed = serializers.IntegerField()
    collections_done = serializers.IntegerField()
    verifications_done = serializers.IntegerField()
    daily = AgentPerformanceDaySerializer(many=True)


class AgentEarningsSerializer(serializers.Serializer):
    # Lifetime — what the Earnings screen shows, and labels honestly as totals.
    base = serializers.DecimalField(max_digits=12, decimal_places=2)
    incentives = serializers.DecimalField(max_digits=12, decimal_places=2)
    total = serializers.DecimalField(max_digits=12, decimal_places=2)
    # Today only — what the dashboard's "Earned today" tile must render. Added
    # alongside rather than changing the three above, so a shipped APK reading
    # `total` keeps working until it is updated.
    today_base = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False)
    today_incentives = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False)
    today_total = serializers.DecimalField(
        max_digits=12, decimal_places=2, required=False)
    today_deliveries = serializers.IntegerField(required=False)
    today_collections = serializers.IntegerField(required=False)


class AgentIncentiveSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = AgentIncentive
        fields = ["id", "amount", "reason", "period", "created_at"]
