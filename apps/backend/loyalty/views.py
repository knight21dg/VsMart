from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import ok

from .models import PointsLedgerEntry
from .serializers import PointsEntrySerializer
from .services import _balance, redeem_to_voucher, tier


def _lifetime_earned(user) -> int:
    """Sum of positive points earned over the account lifetime (earn entries)."""
    from django.db.models import Sum

    return PointsLedgerEntry.objects.filter(
        user=user, type=PointsLedgerEntry.Type.EARN
    ).aggregate(s=Sum("points"))["s"] or 0


class LoyaltyDashboardView(APIView):
    def get(self, request):
        lifetime = _lifetime_earned(request.user)
        return Response(
            {
                "balance": _balance(request.user),
                "lifetimeEarned": lifetime,
                "tier": tier(lifetime),
            }
        )


class LoyaltyLedgerView(ListAPIView):
    serializer_class = PointsEntrySerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return PointsLedgerEntry.objects.none()
        return PointsLedgerEntry.objects.filter(user=self.request.user)


class RedeemView(APIView):
    """POST /loyalty/redeem — convert points into a personal, single-use voucher.

    This used to deduct the points and create nothing ("Redeemed to wallet" —
    there is no wallet), so customers lost their balance for no value and
    couldn't get it back (the ledger is append-only). It now mints a real
    coupon the customer can spend at checkout.
    """

    def post(self, request):
        try:
            points = int(request.data.get("points", 0))
        except (TypeError, ValueError):
            points = 0

        coupon, entry = redeem_to_voucher(request.user, points)
        return Response(ok(
            "POINTS_REDEEMED",
            data={
                "balance": _balance(request.user),
                "redeemed": abs(entry.points),
                "voucher": {
                    "code": coupon.code,
                    "value": coupon.value,
                    "validTo": coupon.valid_to,
                },
            },
        ))
