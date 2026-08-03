"""Cash book API — agent deposits and finance reconciliation."""
from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.generics import ListAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError, ok
from core.permissions import IsAdmin, IsAgent

from .cashbook_services import (
    cash_in_hand,
    confirm_online_handover,
    create_deposit,
    reconciliation,
    reject_deposit,
    start_online_handover,
    undeposited_collections,
    verify_deposit,
)
from .models import CashCollection, CashDeposit


class CashDepositSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    agent_name = serializers.CharField(source="agent.name", read_only=True)
    agent_phone = serializers.CharField(source="agent.phone", read_only=True)
    verified_by_name = serializers.CharField(
        source="verified_by.name", read_only=True, default=None
    )
    shortfall = serializers.DecimalField(
        max_digits=12, decimal_places=2, read_only=True
    )
    collection_count = serializers.SerializerMethodField()

    # "online" (a gateway-verified digital transfer) vs "cash" (physical notes),
    # so the app can label a hand-over without decoding the raw method.
    channel = serializers.SerializerMethodField()

    class Meta:
        model = CashDeposit
        fields = [
            "id", "agent_name", "agent_phone", "amount", "method", "channel",
            "deposited_on", "reference", "status", "verified_amount",
            "verified_by_name", "verified_at", "shortfall", "notes",
            "collection_count", "created_at",
        ]

    def get_collection_count(self, obj):
        return obj.collections.count()

    def get_channel(self, obj):
        return "online" if obj.method == CashDeposit.Method.UPI else "cash"


class UndepositedSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    customer_name = serializers.CharField(source="user.name", read_only=True)

    class Meta:
        model = CashCollection
        fields = ["id", "customer_name", "collected_amount", "collected_at"]


# ── Agent side ───────────────────────────────────────────────────────────────

class AgentCashView(APIView):
    """GET  /agent/cash — what this agent is holding, and their deposit history.
    POST /agent/cash — declare a hand-over of collected cash."""

    permission_classes = [IsAgent]

    def get(self, request):
        pending = undeposited_collections(agent=request.user)
        held = sum((c.collected_amount for c in pending), 0)
        return Response(ok("OK", data={
            "inHand": held,
            "collections": UndepositedSerializer(pending, many=True).data,
            "deposits": CashDepositSerializer(
                CashDeposit.objects.filter(agent=request.user)[:50], many=True
            ).data,
        }))

    def post(self, request):
        deposit = create_deposit(
            request.user,
            amount=request.data.get("amount"),
            method=request.data.get("method") or "bank",
            deposited_on=request.data.get("depositedOn")
            or request.data.get("deposited_on"),
            reference=request.data.get("reference") or "",
            collection_ids=request.data.get("collectionIds")
            or request.data.get("collection_ids") or [],
            notes=request.data.get("notes") or "",
            actor=request.user,
        )
        return Response(
            ok("CASH_DEPOSIT_RECORDED", data=CashDepositSerializer(deposit).data),
            status=201,
        )


class AgentOnlineHandoverView(APIView):
    """POST /agent/cash/online — raise a Razorpay link to send held cash to the
    agent's store digitally.

    Returns the deposit (INITIATED) plus the payment link to pay. The chosen
    collections are reserved immediately, so the same cash can't also be handed
    over in person while the link is unpaid.
    """

    permission_classes = [IsAgent]

    def post(self, request):
        deposit, payment, link = start_online_handover(
            request.user,
            collection_ids=request.data.get("collectionIds")
            or request.data.get("collection_ids") or [],
            actor=request.user,
        )
        data = CashDepositSerializer(deposit).data
        data["payment"] = {
            "paymentId": str(payment.id),
            "linkId": payment.gateway_order_id,
            "shortUrl": link.get("short_url", ""),
            "status": payment.status,
        }
        # A trusted mock settles instantly, so report the terminal state honestly.
        code = ("CASH_ONLINE_CONFIRMED"
                if deposit.status == CashDeposit.Status.VERIFIED
                else "CASH_ONLINE_INITIATED")
        return Response(ok(code, data=data), status=201)


class AgentOnlineHandoverConfirmView(APIView):
    """POST /agent/cash/online/<pk>/confirm — check whether the link is paid.

    Scoped to the caller's own deposits; another agent's id 404s.
    """

    permission_classes = [IsAgent]

    def post(self, request, pk):
        deposit = get_object_or_404(CashDeposit, pk=pk, agent=request.user)
        deposit = confirm_online_handover(deposit, by=request.user)
        if deposit.status == CashDeposit.Status.CANCELLED:
            # Raised here, not in the service: the service is atomic, so raising
            # inside it would undo the cancellation it just committed.
            raise AppError("CASH_ONLINE_FAILED",
                           entity_type="cash_deposit", entity_id=str(deposit.pk))
        code = ("CASH_ONLINE_CONFIRMED"
                if deposit.status == CashDeposit.Status.VERIFIED
                else "CASH_ONLINE_PENDING")
        return Response(ok(code, data=CashDepositSerializer(deposit).data))


# ── Admin / finance side ─────────────────────────────────────────────────────

class AdminCashDepositListView(ListAPIView):
    """GET /admin/cash/deposits?status=&agent=&from=&to="""

    permission_classes = [IsAdmin]
    serializer_class = CashDepositSerializer

    def get_queryset(self):
        qs = CashDeposit.objects.select_related("agent", "verified_by")
        p = self.request.query_params
        if p.get("status"):
            qs = qs.filter(status=p["status"])
        if p.get("agent"):
            qs = qs.filter(agent_id=p["agent"])
        if p.get("from"):
            qs = qs.filter(deposited_on__gte=p["from"])
        if p.get("to"):
            qs = qs.filter(deposited_on__lte=p["to"])
        return qs


class AdminCashDepositDetailView(APIView):
    """GET /admin/cash/deposits/<pk> — the deposit and exactly which collections
    it banks, so a figure can always be traced back to the customers who paid."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        deposit = get_object_or_404(
            CashDeposit.objects.select_related("agent", "verified_by"), pk=pk
        )
        data = CashDepositSerializer(deposit).data
        data["collections"] = UndepositedSerializer(
            deposit.collections.select_related("user"), many=True
        ).data
        return Response(ok("OK", data=data))


class AdminCashDepositActionView(APIView):
    """POST /admin/cash/deposits/<pk>/<action> — verify | reject."""

    permission_classes = [IsAdmin]

    def post(self, request, pk, action):
        deposit = get_object_or_404(CashDeposit, pk=pk)
        if action == "verify":
            deposit = verify_deposit(
                deposit, request.user,
                counted_amount=request.data.get("countedAmount")
                if request.data.get("countedAmount") is not None
                else request.data.get("counted_amount"),
                notes=request.data.get("notes") or "",
            )
        elif action == "reject":
            deposit = reject_deposit(
                deposit, request.user, reason=request.data.get("reason") or ""
            )
        else:
            raise AppError("VALIDATION_ERROR",
                           message="action must be 'verify' or 'reject'.")
        return Response(ok("OK", data=CashDepositSerializer(deposit).data))


class AdminCashReconciliationView(APIView):
    """GET /admin/cash/reconciliation — collected vs deposited vs verified."""

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        return Response(ok("OK", data=reconciliation(
            date_from=p.get("from") or None,
            date_to=p.get("to") or None,
            agent=p.get("agent") or None,
        )))


class AdminCashInHandView(APIView):
    """GET /admin/cash/in-hand — how much collected cash each agent still holds."""

    permission_classes = [IsAdmin]

    def get(self, request):
        return Response(ok("OK", data=cash_in_hand()))


# ── Receipts ─────────────────────────────────────────────────────────────────

class PaymentReceiptView(APIView):
    """GET /payments/<pk>/receipt — the customer's own receipt PDF.

    Credit repayments previously had no document at all: the app's "Download
    Receipt" only showed a snackbar, so a customer who repaid had nothing to
    show for it. Scoped to the caller's own payments — another user's id 404s
    rather than revealing that it exists.
    """

    def get(self, request, pk):
        from django.http import HttpResponse

        from .models import Payment
        from .receipt import build_receipt_pdf

        payment = get_object_or_404(
            Payment.objects.select_related("user", "order"),
            pk=pk, user=request.user,
        )
        if payment.status != Payment.Status.SUCCESS:
            raise AppError(
                "RECEIPT_NOT_READY",
                message="A receipt is available once the payment completes.",
            )
        pdf = build_receipt_pdf(payment)
        response = HttpResponse(pdf, content_type="application/pdf")
        response["Content-Disposition"] = (
            f'inline; filename="vsmart-receipt-{payment.id}.pdf"'
        )
        return response


class AdminPaymentReceiptView(APIView):
    """GET /admin/payments/<pk>/receipt — the same document, for support."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        from django.http import HttpResponse

        from .models import Payment
        from .receipt import build_receipt_pdf

        payment = get_object_or_404(
            Payment.objects.select_related("user", "order"), pk=pk
        )
        pdf = build_receipt_pdf(payment)
        response = HttpResponse(pdf, content_type="application/pdf")
        response["Content-Disposition"] = (
            f'inline; filename="vsmart-receipt-{payment.id}.pdf"'
        )
        return response


class AgentOnlineHandoverCancelView(APIView):
    """Agent backs out of an unpaid online hand-over — link cancelled, cash
    returns to their in-hand figure immediately."""

    permission_classes = [IsAgent]

    def post(self, request, pk):
        from .cashbook_services import cancel_online_handover
        from .models import CashDeposit

        deposit = get_object_or_404(CashDeposit, pk=pk, agent=request.user)
        deposit = cancel_online_handover(deposit, by=request.user)
        return Response({"id": deposit.id, "status": deposit.status})
