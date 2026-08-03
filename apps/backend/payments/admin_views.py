"""Admin payments module — the money ledger view.

Finance needs three things the customer-facing endpoints don't provide: to
*find* a payment (across users, by gateway reference, in a date window), to see
*why* one ended where it did (the PaymentEvent audit trail), and to *reconcile*
a period (totals by status and method). This module serves those.

Read-only on purpose. Refunds go through ``payments.services.refund_payment``
so the ledger and gateway stay in step; nothing here mutates a Payment.
"""
from datetime import datetime, time

from django.db.models import Count, Q, Sum
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import ok
from core.permissions import IsAdmin

from .models import Payment, PaymentEvent


class AdminPaymentSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    customer_name = serializers.CharField(source="user.name", read_only=True)
    customer_phone = serializers.CharField(source="user.phone", read_only=True)
    # NB: no source="user_id" — DRF rejects a source identical to the field name
    # and the AssertionError surfaces as a 500 on every list/detail call.
    user_id = serializers.CharField(read_only=True)
    order_code = serializers.SerializerMethodField()

    class Meta:
        model = Payment
        fields = [
            "id", "user_id", "customer_name", "customer_phone",
            "purpose", "amount", "method", "gateway", "status",
            "gateway_order_id", "gateway_payment_id", "gateway_refund_id",
            "order_code", "statement_id", "refund_of_id", "created_at",
        ]

    def get_order_code(self, obj):
        return getattr(obj.order, "code", None)


class AdminPaymentEventSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    actor = serializers.CharField(source="created_by.name", read_only=True,
                                  default=None)

    class Meta:
        model = PaymentEvent
        fields = ["id", "status", "note", "gateway_ref", "actor", "created_at"]


def _parse_day(value, *, end=False):
    """Parse a YYYY-MM-DD filter bound into an aware datetime, or None.

    The end bound covers the whole day — a finance user filtering "to 5 Jul"
    means through 5 Jul 23:59, not 00:00.
    """
    if not value:
        return None
    try:
        day = datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except ValueError:
        return None
    stamp = datetime.combine(day, time.max if end else time.min)
    return timezone.make_aware(stamp, timezone.get_current_timezone())


def filtered_payments(params):
    """The queryset behind both the list and the summary, so the totals always
    describe exactly the rows on screen."""
    qs = Payment.objects.select_related("user", "order").all()

    for field in ("status", "method", "gateway", "purpose"):
        value = params.get(field)
        if value:
            qs = qs.filter(**{field: value})

    start = _parse_day(params.get("from"))
    end = _parse_day(params.get("to"), end=True)
    if start:
        qs = qs.filter(created_at__gte=start)
    if end:
        qs = qs.filter(created_at__lte=end)

    q = (params.get("q") or "").strip()
    if q:
        cond = (
            Q(user__name__icontains=q)
            | Q(user__phone__icontains=q)
            | Q(gateway_order_id__icontains=q)
            | Q(gateway_payment_id__icontains=q)
            | Q(order__code__icontains=q)
        )
        if q.isdigit():
            cond |= Q(id=int(q))
        qs = qs.filter(cond)
    return qs


class AdminPaymentListView(ListAPIView):
    """GET /admin/payments — searchable, filterable payment ledger."""

    permission_classes = [IsAdmin]
    serializer_class = AdminPaymentSerializer

    def get_queryset(self):
        return filtered_payments(self.request.query_params).order_by("-created_at")


class AdminPaymentDetailView(APIView):
    """GET /admin/payments/<pk> — one payment plus its full event trail."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        payment = get_object_or_404(
            Payment.objects.select_related("user", "order", "refund_of"), pk=pk
        )
        data = AdminPaymentSerializer(payment).data
        data["events"] = AdminPaymentEventSerializer(
            payment.events.select_related("created_by").order_by("created_at"),
            many=True,
        ).data
        # A refunded payment's children, so the reversal chain is visible.
        data["refunds"] = AdminPaymentSerializer(
            payment.refunds.all(), many=True
        ).data
        return Response(ok("OK", data=data))


class AdminPaymentSummaryView(APIView):
    """GET /admin/payments/summary — reconciliation totals for the same filters.

    Only ``success`` money is counted in ``collected``: created/pending rows are
    intents, not receipts, and counting them would overstate the day's takings.
    Refunds are reported separately rather than netted off, so a period shows
    gross in and gross out instead of a single figure that hides both.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        qs = filtered_payments(request.query_params)

        by_status = list(
            qs.values("status")
            .annotate(count=Count("id"), amount=Sum("amount"))
            .order_by("status")
        )
        by_method = list(
            qs.filter(status=Payment.Status.SUCCESS)
            .values("method")
            .annotate(count=Count("id"), amount=Sum("amount"))
            .order_by("method")
        )
        collected = (
            qs.filter(status=Payment.Status.SUCCESS)
            .exclude(purpose=Payment.Purpose.REFUND)
            .aggregate(total=Sum("amount"))["total"] or 0
        )
        refunded = (
            qs.filter(purpose=Payment.Purpose.REFUND, status=Payment.Status.SUCCESS)
            .aggregate(total=Sum("amount"))["total"] or 0
        )
        failed = qs.filter(status=Payment.Status.FAILED).count()

        return Response(ok("OK", data={
            "collected": collected,
            "refunded": refunded,
            "failedCount": failed,
            "total": qs.count(),
            "byStatus": by_status,
            "byMethod": by_method,
        }))
