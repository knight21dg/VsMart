from django.core.validators import MaxValueValidator, MinValueValidator
from rest_framework import serializers

from .models import Review


class ReviewSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    author_name = serializers.CharField(source="user.name", read_only=True)

    class Meta:
        model = Review
        fields = [
            "id", "rating", "title", "body", "created_at", "author_name",
            # `status` rides along so a customer reading /reviews/mine can see
            # their review is awaiting approval instead of thinking it vanished.
            "status", "is_verified_purchase",
        ]


class ReviewCreateSerializer(serializers.Serializer):
    rating = serializers.IntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)]
    )
    title = serializers.CharField(required=False, allow_blank=True)
    body = serializers.CharField(required=False, allow_blank=True)
