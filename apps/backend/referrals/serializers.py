from rest_framework import serializers

from .models import Referral


class ReferralSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    referred_count = serializers.SerializerMethodField()

    class Meta:
        model = Referral
        fields = ["id", "code", "reward", "status", "referred_count"]

    def get_referred_count(self, obj):
        return Referral.objects.filter(
            referrer=obj.referrer, referee__isnull=False
        ).count()
