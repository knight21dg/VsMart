from rest_framework import serializers

from .models import PointsLedgerEntry


class PointsEntrySerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)

    class Meta:
        model = PointsLedgerEntry
        fields = ["id", "type", "points", "balance_after", "note", "created_at"]
