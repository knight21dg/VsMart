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


# ── Reconciliation queue ────────────────────────────────────────────────────
#
# The one mutating endpoint in this module, and deliberately so: when every
# automated path has failed to establish what the gateway did, someone has to
# decide, and that decision needs a screen, an authorisation check and a trail.
#
# Before this existed an unresolvable payment simply stayed PENDING. Nothing
# surfaced it, the expiry sweep correctly refused to cancel the order (the money
# might be captured), and its stock stayed reserved indefinitely — prod order
# VSORD100025 held stock for 17 days with no operator anywhere able to see why.

class AdminReconciliationListView(APIView):
    """GET /admin/payments/reconciliation — payments awaiting a human decision.

    Carries everything needed to act without leaving the page: what the gateway last
    said, how many times we asked, and whether the order's stock is still held —
    which is what leaving one unresolved actually costs.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        from .reconciliation import payments_needing_reconciliation

        now = timezone.now()
        rows = []
        for p in payments_needing_reconciliation():
            order = p.order
            rows.append({
                "id": p.id,
                "amount": float(p.amount),
                "status": p.status,
                "method": p.method,
                "gateway": p.gateway,
                "gatewayOrderId": p.gateway_order_id,
                "gatewayPaymentId": p.gateway_payment_id,
                "customer": p.user.name or p.user.phone,
                "customerPhone": p.user.phone,
                "createdAt": p.created_at,
                "ageMinutes": int((now - p.created_at).total_seconds() // 60),
                "attempts": p.reconcile_attempts,
                "lastCheckedAt": p.last_reconciled_at,
                "lastGatewaySaid": p.reconcile_note,
                "orderCode": getattr(order, "code", None),
                "orderStatus": getattr(order, "status", None),
                "stockHeld": bool(order and order.stock_state == "reserved"),
                # A capture against a cancelled order is money owed back, not
                # revenue — surfaced so the operator knows before they click.
                "refundOnCapture": bool(order and order.status == "cancelled"),
            })
        return Response(ok("OK", data={
            "payments": rows,
            "total": len(rows),
            "note": (
                "Verify each capture in the payment provider's dashboard before "
                "confirming. Confirming a capture on a cancelled order records the "
                "capture and then raises a refund; confirming no capture releases "
                "the order's stock."
            ),
        }))


class AdminConfirmCapturedView(APIView):
    """POST /admin/payments/<pk>/confirm-captured — record a verified capture.

    Body: ``{"capturedAmount": "649.00", "attested": true,
             "gatewayPaymentId": "pay_...", "reason": "..."}``

    Deliberately not a "Mark Paid" button. It asserts an externally observed fact,
    so it requires the amount the provider captured and an explicit attestation that
    the operator has seen it. Settlement itself still runs through
    ``finalize_payment`` — including its refusal to settle a short capture.
    """

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        from .reconciliation import confirm_captured

        payment = get_object_or_404(Payment, pk=pk)
        data = request.data or {}
        payment, applied = confirm_captured(
            payment,
            captured_amount=data.get("capturedAmount", data.get("captured_amount")),
            by=request.user,
            attested=bool(data.get("attested")),
            gateway_payment_id=str(
                data.get("gatewayPaymentId") or data.get("gateway_payment_id") or ""),
            reason=str(data.get("reason") or ""),
        )
        return Response(ok(
            "PAYMENT_SUCCESS" if applied else "OK",
            data=_resolution_payload(payment, applied),
        ))


class AdminConfirmNotCapturedView(APIView):
    """POST /admin/payments/<pk>/confirm-not-captured — the provider took nothing.

    Body: ``{"reason": "..."}``. Marks the payment failed, which lifts the in-flight
    guard so the order's stock can be released by the normal expiry path.
    """

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        from .reconciliation import confirm_not_captured

        payment = get_object_or_404(Payment, pk=pk)
        payment, applied = confirm_not_captured(
            payment, by=request.user,
            reason=str((request.data or {}).get("reason") or ""),
        )
        return Response(ok(
            "PAYMENT_FAILED" if applied else "OK",
            data=_resolution_payload(payment, applied),
        ))


def _resolution_payload(payment, applied):
    """The row's state after the decision — including when someone else got there first."""
    order = payment.order
    return {
        "id": payment.id,
        "status": payment.status,
        "applied": applied,
        "alreadyFinal": not applied,
        "resolvedAt": payment.resolved_at,
        "orderCode": getattr(order, "code", None),
        "orderStatus": getattr(order, "status", None),
        "orderPaymentStatus": getattr(order, "payment_status", None),
        # Present when a cancelled order's capture was reversed.
        "refundId": (
            payment.refunds.values_list("id", flat=True).first()
            if hasattr(payment, "refunds") else None
        ),
        "message": (
            "Recorded." if applied
            else "Already resolved elsewhere — showing the current state."
        ),
    }
