"""Loyalty admin: points ledger oversight and redemption tracking.

Points and vouchers were being minted and spent with no console anywhere — the only
way to answer "who redeemed what, and did they actually use it" was a Django-admin
row hunt. These are deliberately READ-ONLY: the ledger is append-only, so an admin
screen that could edit it would be lying about its own guarantees. Corrections go
through an `adjust` entry, not an update.
"""
from django.db.models import Count, Q, Sum
from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from core.pagination import EnvelopePagination
from core.permissions import IsAdmin
from offers.models import Coupon, CouponRedemption

from .models import PointsLedgerEntry
from .services import tier


class AdminPointsEntrySerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    user_id = serializers.CharField(read_only=True)
    user_name = serializers.CharField(source="user.name", read_only=True)
    user_phone = serializers.CharField(source="user.phone", read_only=True)

    class Meta:
        model = PointsLedgerEntry
        fields = [
            "id", "user_id", "user_name", "user_phone", "type", "points",
            "balance_after", "note", "ref_type", "ref_id", "created_at",
        ]


class AdminPointsLedgerView(ListAPIView):
    """Every points movement, newest first. Filter by user, type or free-text."""

    serializer_class = AdminPointsEntrySerializer
    permission_classes = [IsAdmin]
    pagination_class = EnvelopePagination

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return PointsLedgerEntry.objects.none()
        qs = PointsLedgerEntry.objects.select_related("user")
        params = self.request.query_params
        user_id = params.get("user_id")
        if user_id:
            qs = qs.filter(user_id=user_id)
        entry_type = params.get("type")
        if entry_type:
            qs = qs.filter(type=entry_type)
        search = (params.get("search") or "").strip()
        if search:
            qs = qs.filter(
                Q(user__name__icontains=search)
                | Q(user__phone__icontains=search)
                | Q(note__icontains=search)
                | Q(ref_id__icontains=search)
            )
        return qs


class AdminLoyaltySummaryView(APIView):
    """Programme-level totals — what loyalty is actually costing and returning."""

    permission_classes = [IsAdmin]

    def get(self, request):
        rows = PointsLedgerEntry.objects.aggregate(
            earned=Sum("points", filter=Q(type=PointsLedgerEntry.Type.EARN)),
            redeemed=Sum("points", filter=Q(type=PointsLedgerEntry.Type.REDEEM)),
            adjusted=Sum("points", filter=Q(type=PointsLedgerEntry.Type.ADJUST)),
            expired=Sum("points", filter=Q(type=PointsLedgerEntry.Type.EXPIRE)),
        )
        earned = rows["earned"] or 0
        # REDEEM/EXPIRE rows are stored negative; report them as positive magnitudes
        # so the console doesn't have to know the sign convention.
        redeemed = abs(rows["redeemed"] or 0)
        expired = abs(rows["expired"] or 0)
        adjusted = rows["adjusted"] or 0
        return Response({
            "points_earned": earned,
            "points_redeemed": redeemed,
            "points_expired": expired,
            "points_adjusted": adjusted,
            # Outstanding = what customers could still redeem = a real liability.
            "points_outstanding": earned + adjusted - redeemed - expired,
            "members": PointsLedgerEntry.objects.values("user_id").distinct().count(),
        })


class AdminTopMembersView(APIView):
    """Highest lifetime earners, with the tier that earns them."""

    permission_classes = [IsAdmin]

    def get(self, request):
        try:
            limit = min(int(request.query_params.get("limit") or 20), 100)
        except (TypeError, ValueError):
            limit = 20
        rows = (
            PointsLedgerEntry.objects
            .filter(type=PointsLedgerEntry.Type.EARN)
            .values("user_id", "user__name", "user__phone")
            .annotate(lifetime=Sum("points"), orders=Count("id"))
            .order_by("-lifetime")[:limit]
        )
        return Response([
            {
                "user_id": str(row["user_id"]),
                "name": row["user__name"],
                "phone": row["user__phone"],
                "lifetime_points": row["lifetime"] or 0,
                "earning_events": row["orders"],
                "tier": tier(row["lifetime"] or 0),
            }
            for row in rows
        ])


class AdminRedemptionSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    user_id = serializers.CharField(read_only=True)
    user_name = serializers.CharField(source="user.name", read_only=True)
    user_phone = serializers.CharField(source="user.phone", read_only=True)
    coupon_code = serializers.CharField(source="coupon.code", read_only=True)
    discount_type = serializers.CharField(source="coupon.discount_type", read_only=True)
    # A personally-minted voucher (loyalty redemption / referral reward) vs a public
    # marketing code — the distinction the console actually needs.
    is_personal = serializers.SerializerMethodField()

    class Meta:
        model = CouponRedemption
        fields = [
            "id", "user_id", "user_name", "user_phone", "coupon_code",
            "discount_type", "is_personal", "order_code", "amount", "created_at",
        ]

    def get_is_personal(self, obj):
        return obj.coupon.owner_id is not None


class AdminRedemptionListView(ListAPIView):
    """Coupons actually SPENT — the money side of loyalty and referrals.

    Distinct from the points ledger: redeeming points mints a voucher, but the
    voucher is only a cost once someone spends it on an order. Both views are
    needed to see the programme honestly.
    """

    serializer_class = AdminRedemptionSerializer
    permission_classes = [IsAdmin]
    pagination_class = EnvelopePagination

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CouponRedemption.objects.none()
        qs = CouponRedemption.objects.select_related("coupon", "user")
        params = self.request.query_params
        search = (params.get("search") or "").strip()
        if search:
            qs = qs.filter(
                Q(coupon__code__icontains=search)
                | Q(user__name__icontains=search)
                | Q(user__phone__icontains=search)
                | Q(order_code__icontains=search)
            )
        kind = params.get("kind")
        if kind == "personal":
            qs = qs.filter(coupon__owner__isnull=False)
        elif kind == "public":
            qs = qs.filter(coupon__owner__isnull=True)
        return qs.order_by("-created_at")


class AdminVoucherOutstandingView(APIView):
    """Personal vouchers minted but NOT yet spent — an unbilled liability.

    Points redeemed already left the ledger, so without this the business sees the
    cost twice or not at all: once when points burn, and again (invisibly) when the
    voucher is finally used.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        personal = Coupon.objects.filter(owner__isnull=False)
        spent_ids = CouponRedemption.objects.values_list("coupon_id", flat=True)
        outstanding = personal.exclude(id__in=spent_ids)
        return Response({
            "issued": personal.count(),
            "spent": personal.filter(id__in=spent_ids).distinct().count(),
            "outstanding": outstanding.count(),
            # Only FLAT vouchers have a knowable rupee value; a percent code's cost
            # depends on the basket it lands on, so summing it would invent a number.
            "outstanding_value": outstanding.filter(
                discount_type=Coupon.DiscountType.FLAT
            ).aggregate(s=Sum("value"))["s"] or 0,
        })
