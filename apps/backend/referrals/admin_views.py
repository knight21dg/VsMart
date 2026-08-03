"""Referrals admin: who invited whom, how many, and what it paid out.

There was no console for this at all — the scheme mints real vouchers on both sides
of every completed referral and nobody could see the tree, the conversion rate, or
the cost. Read-only by design: a referral completes on the referee's first delivered
order, so an admin who could flip a status by hand would be minting vouchers for
invites that never converted.
"""
from django.db.models import Count, Q, Sum
from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from core.pagination import EnvelopePagination
from core.permissions import IsAdmin

from .models import Referral


class AdminReferralSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    referrer_id = serializers.CharField(read_only=True)
    referrer_name = serializers.CharField(source="referrer.name", read_only=True)
    referrer_phone = serializers.CharField(source="referrer.phone", read_only=True)
    # The referee is SET_NULL, so a deleted account leaves the row intact with a
    # blank invitee rather than vanishing from the referrer's count.
    referee_id = serializers.CharField(read_only=True)
    referee_name = serializers.SerializerMethodField()
    referee_phone = serializers.SerializerMethodField()

    class Meta:
        model = Referral
        fields = [
            "id", "code", "status", "reward",
            "referrer_id", "referrer_name", "referrer_phone",
            "referee_id", "referee_name", "referee_phone",
            "created_at",
        ]

    def get_referee_name(self, obj):
        return obj.referee.name if obj.referee_id else ""

    def get_referee_phone(self, obj):
        return obj.referee.phone if obj.referee_id else ""


class AdminReferralListView(ListAPIView):
    """Every referral, newest first. Filter by status, referrer, or free-text."""

    serializer_class = AdminReferralSerializer
    permission_classes = [IsAdmin]
    pagination_class = EnvelopePagination

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Referral.objects.none()
        qs = Referral.objects.select_related("referrer", "referee")
        params = self.request.query_params
        status = params.get("status")
        if status:
            qs = qs.filter(status=status)
        referrer_id = params.get("referrer_id")
        if referrer_id:
            qs = qs.filter(referrer_id=referrer_id)
        search = (params.get("search") or "").strip()
        if search:
            qs = qs.filter(
                Q(code__icontains=search)
                | Q(referrer__name__icontains=search)
                | Q(referrer__phone__icontains=search)
                | Q(referee__name__icontains=search)
                | Q(referee__phone__icontains=search)
            )
        return qs.order_by("-created_at")


class AdminReferrerListView(ListAPIView):
    """One row per INVITER: how many they invited and how many converted.

    This is the "this user invited this many people" view. Ordered by completed
    invites rather than raw invites, so the leaderboard reflects referrals that
    actually became customers instead of rewarding bulk code-sharing.
    """

    permission_classes = [IsAdmin]
    pagination_class = EnvelopePagination

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Referral.objects.none()
        qs = (
            Referral.objects
            .values("referrer_id", "referrer__name", "referrer__phone")
            .annotate(
                invited=Count("id"),
                completed=Count("id", filter=Q(status=Referral.Status.COMPLETED)),
                pending=Count("id", filter=Q(status=Referral.Status.PENDING)),
                rewards_paid=Sum(
                    "reward", filter=Q(status=Referral.Status.COMPLETED)),
            )
            .order_by("-completed", "-invited")
        )
        search = (self.request.query_params.get("search") or "").strip()
        if search:
            qs = qs.filter(
                Q(referrer__name__icontains=search)
                | Q(referrer__phone__icontains=search)
            )
        return qs

    def list(self, request, *args, **kwargs):
        page = self.paginate_queryset(self.get_queryset())
        rows = [
            {
                "user_id": str(row["referrer_id"]),
                "name": row["referrer__name"],
                "phone": row["referrer__phone"],
                "invited": row["invited"],
                "completed": row["completed"],
                "pending": row["pending"],
                "rewards_paid": row["rewards_paid"] or 0,
            }
            for row in (page if page is not None else self.get_queryset())
        ]
        if page is not None:
            return self.get_paginated_response(rows)
        return Response(rows)


class AdminReferrerDetailView(APIView):
    """The people ONE referrer invited — "and these are they"."""

    permission_classes = [IsAdmin]

    def get(self, request, user_id):
        rows = (
            Referral.objects
            .select_related("referrer", "referee")
            .filter(referrer_id=user_id)
            .order_by("-created_at")
        )
        first = rows.first()
        return Response({
            "user_id": str(user_id),
            "name": first.referrer.name if first else "",
            "phone": first.referrer.phone if first else "",
            "invited": rows.count(),
            "completed": rows.filter(status=Referral.Status.COMPLETED).count(),
            "invitees": AdminReferralSerializer(rows, many=True).data,
        })


class AdminReferralSummaryView(APIView):
    """Programme totals: reach, conversion and cost."""

    permission_classes = [IsAdmin]

    def get(self, request):
        rows = Referral.objects.aggregate(
            total=Count("id"),
            completed=Count("id", filter=Q(status=Referral.Status.COMPLETED)),
            pending=Count("id", filter=Q(status=Referral.Status.PENDING)),
            expired=Count("id", filter=Q(status=Referral.Status.EXPIRED)),
            paid=Sum("reward", filter=Q(status=Referral.Status.COMPLETED)),
        )
        total = rows["total"] or 0
        completed = rows["completed"] or 0
        return Response({
            "total": total,
            "completed": completed,
            "pending": rows["pending"] or 0,
            "expired": rows["expired"] or 0,
            # Rewards are paid per SIDE (referrer + referee both get a voucher), so
            # the real cost is twice the recorded reward on a completed referral.
            "rewards_paid": (rows["paid"] or 0) * 2,
            "conversion_rate": round(completed / total * 100, 1) if total else 0.0,
            "referrers": Referral.objects.values("referrer_id").distinct().count(),
        })
