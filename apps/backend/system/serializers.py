from rest_framework import serializers

from .models import Feedback, FeatureFlag


class FeatureFlagSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = FeatureFlag
        fields = ["id", "key", "enabled", "description"]


class FeedbackSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = Feedback
        fields = ["id", "message", "rating"]
