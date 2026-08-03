from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Referral
from .serializers import ReferralSerializer
from .services import apply_code, my_referral


class ReferralView(APIView):
    """GET /referrals — the customer's own code, plus how it's doing."""

    def get(self, request):
        referral = my_referral(request.user)
        data = ReferralSerializer(referral).data
        # Split the counts so "invited" and "actually paid out" stay distinct —
        # a pending referral has earned nobody anything yet, and reporting it as
        # a success is how the old flow misled people.
        made = Referral.objects.filter(referrer=request.user).exclude(
            referee__isnull=True
        )
        data["referredCount"] = made.count()
        data["completedCount"] = made.filter(
            status=Referral.Status.COMPLETED
        ).count()
        data["pendingCount"] = made.filter(status=Referral.Status.PENDING).count()
        return Response(data)


class ReferralApplyView(APIView):
    """POST /referrals/apply — link this customer to whoever referred them.

    Deliberately pays nothing here. The reward is minted when the referee's
    first order is delivered (`services.complete_for_order`), so the scheme
    can't be farmed by creating accounts and typing codes at each other.
    """

    def post(self, request):
        referral = apply_code(request.user, request.data.get("code"))
        return Response({
            "status": "applied",
            "reward": referral.reward,
            "rewardStatus": referral.status,
            "message": "Your reward unlocks when your first order is delivered.",
        })
