import logging
from decimal import Decimal, InvalidOperation

from rest_framework import status as http
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import AppError
from orders.models import Order

from .models import CashCollection, Payment, PaymentWebhookEvent
from .serializers import (
    CashCollectionSerializer,
    ConfirmPaymentSerializer,
    PaymentSerializer,
    RepaySerializer,
    StartPaymentSerializer,
)
from .services import (
    finalize_payment,
    log_payment_event,
    start_payment,
)

logger = logging.getLogger(__name__)


class StartPaymentView(APIView):
    throttle_scope = "checkout"

    def post(self, request):
        s = StartPaymentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        order = None
        amount = d["amount"]
        if d.get("order_id"):
            order = get_object_or_404(Order, code=d["order_id"], user=request.user)
            # NEVER charge a client-supplied amount for an order. The client used to
            # pick it, so `{"order_id": "VS123", "amount": 1}` opened a ₹1 gateway
            # order for a ₹5,000 basket and finalize_payment then marked the order
            # fully PAID. The order's own total is the only authority.
            amount = order.total
            if order.payment_status == order.PaymentStatus.PAID:
                raise AppError("PAYMENT_ALREADY_COMPLETED")
        payment = start_payment(
            request.user, purpose=d["purpose"], amount=amount, method=d["method"],
            order=order, idempotency_key=request.headers.get("Idempotency-Key", ""),
        )
        return Response(PaymentSerializer(payment).data, status=http.HTTP_201_CREATED)


class RepayView(APIView):
    throttle_scope = "checkout"

    def post(self, request):
        s = RepaySerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        from credit.models import Statement
        from credit.services import ensure_account

        # Never charge the customer more than they owe. `apply_repayment` clamps a
        # negative outstanding to zero, so an overpayment used to CHARGE the full
        # amount at the gateway and then silently drop the excess — the customer
        # paid ₹5,000 against a ₹500 balance and ₹4,500 vanished (no credit balance
        # exists to hold it, and nothing refunds it). Reject before the money moves.
        account = ensure_account(request.user)
        outstanding = account.outstanding
        if outstanding <= 0:
            raise AppError("CREDIT_NO_DUES")
        if d["amount"] > outstanding:
            raise AppError(
                "CREDIT_OVERPAYMENT",
                message=(
                    f"You owe ₹{outstanding:.2f}. Enter an amount up to that."
                ),
                context={"outstanding": str(outstanding)},
            )

        statement = None
        if d.get("statement_id"):
            statement = Statement.objects.filter(
                pk=d["statement_id"], account__user=request.user
            ).first()
        payment = start_payment(
            request.user, purpose="repayment", amount=d["amount"], method=d["method"],
            statement=statement, idempotency_key=request.headers.get("Idempotency-Key", ""),
        )
        return Response(PaymentSerializer(payment).data, status=http.HTTP_201_CREATED)


class PaymentHistoryView(ListAPIView):
    serializer_class = PaymentSerializer

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Payment.objects.none()
        return Payment.objects.filter(user=self.request.user)


class PaymentDetailView(APIView):
    def get(self, request, pk):
        payment = get_object_or_404(Payment, pk=pk, user=request.user)
        return Response(PaymentSerializer(payment).data)


class ConfirmPaymentView(APIView):
    """Settle a payment from the app's Razorpay Checkout success callback.

    The SDK hands the app ``razorpay_order_id``, ``razorpay_payment_id`` and a
    ``razorpay_signature`` — an HMAC over ``order_id|payment_id`` with our API
    secret, which only we can compute. Verifying it server-side is what makes the
    client's "payment succeeded" claim trustworthy.

    Before this existed the app threw the signature away and routed straight to the
    success screen on the client callback alone, so — with the webhook also broken
    — the backend never learned the payment had happened by any route: the customer
    saw a paid order, the server saw an unpaid one, and the expiry job cancelled it
    30 minutes later.

    Complements the webhook rather than replacing it; both funnel into the same
    idempotent :func:`finalize_payment`, so whichever arrives first settles and the
    other is a no-op.
    """

    throttle_scope = "checkout"

    def post(self, request, pk):
        from .gateway import get_gateway

        payment = get_object_or_404(Payment, pk=pk, user=request.user)
        s = ConfirmPaymentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data

        # The signed order id must be the one WE created for this payment —
        # otherwise a valid signature from any other Razorpay order of ours could
        # be replayed to settle this one.
        if payment.gateway_order_id and d["razorpay_order_id"] != payment.gateway_order_id:
            raise AppError(
                "PAYMENT_FAILED",
                message="This confirmation doesn't belong to that payment.",
            )

        verified = get_gateway().verify_checkout_signature(
            d["razorpay_order_id"], d["razorpay_payment_id"], d["razorpay_signature"],
        )
        if not verified:
            log_payment_event(payment, payment.status,
                              note="Checkout signature verification failed")
            raise AppError("PAYMENT_FAILED",
                           message="We couldn't verify that payment.")

        finalize_payment(payment, success=True,
                         gateway_payment_id=d["razorpay_payment_id"])
        payment.refresh_from_db()
        return Response(PaymentSerializer(payment).data)


def parse_webhook(headers, data):
    """Normalise a gateway webhook into ``(event_id, gateway_order_id,
    gateway_payment_id, succeeded, amount)``.

    Razorpay's real body is nested and its event id lives in a HEADER::

        X-Razorpay-Event-Id: evt_xxx
        {"event": "payment.captured",
         "payload": {"payment": {"entity": {"id": "pay_x", "order_id": "order_x",
                                            "status": "captured", "amount": 500000}}}}

    The handler previously read flat ``event_id`` / ``gateway_order_id`` /
    ``status == "success"`` keys, which only the mock ever sends. Against a real
    Razorpay event that meant: ``event_id`` resolved to ``""`` (and the column is
    unique, so the FIRST live webhook consumed the blank slot and every later one
    was answered "already_processed"), ``gateway_order_id`` was ``""`` which
    matched the most recent *cash* payment, and ``status`` never equalled
    "success" — so a genuine capture failed an unrelated COD payment and left the
    real order unpaid forever.

    Both shapes are accepted: the flat one keeps the mock gateway and the existing
    tests working in dev.
    """
    entity = (
        (data.get("payload") or {}).get("payment", {}).get("entity")
        if isinstance(data.get("payload"), dict)
        else None
    ) or {}

    event_id = (
        headers.get("X-Razorpay-Event-Id")
        or data.get("event_id")
        or entity.get("id")
        or data.get("gateway_payment_id")
        or ""
    )
    gateway_order_id = entity.get("order_id") or data.get("gateway_order_id") or ""
    gateway_payment_id = entity.get("id") or data.get("gateway_payment_id") or ""

    event_name = data.get("event") or ""
    entity_status = entity.get("status") or ""
    succeeded = (
        data.get("status") == "success"
        or event_name in ("payment.captured", "order.paid")
        or entity_status == "captured"
    )

    # Razorpay reports paise; the ledger is in rupees.
    amount = None
    if entity.get("amount") is not None:
        try:
            amount = Decimal(str(entity["amount"])) / Decimal("100")
        except (InvalidOperation, TypeError):
            amount = None

    return event_id, gateway_order_id, gateway_payment_id, succeeded, amount


class WebhookView(APIView):
    """Gateway → us. Verifies the signature over the RAW body, stores the raw
    event, and finalizes idempotently.

    Unauthenticated by necessity (the gateway can't hold our credentials), so the
    HMAC signature is the ONLY thing standing between this endpoint and arbitrary
    order settlement — see `get_gateway`, which now refuses to fall back to a
    signature-trusting mock when real keys are configured.
    """

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        from .gateway import get_gateway

        gw = get_gateway()
        sig = request.headers.get("X-Razorpay-Signature", "")
        if not gw.verify_webhook(request.body, sig):
            return Response({"error": {"code": "bad_signature", "message": "Invalid signature", "fields": {}}}, status=400)

        data = request.data
        (event_id, gateway_order_id, gateway_payment_id, succeeded,
         amount) = parse_webhook(request.headers, data)

        # An event we can't identify must not be recorded under a blank id — that
        # id is unique, so one unidentifiable event would permanently shadow every
        # future one.
        if not event_id:
            logger.warning("Webhook with no resolvable event id: %s", data)
            return Response(
                {"error": {"code": "bad_request", "message": "Missing event id", "fields": {}}},
                status=400,
            )

        event, created = PaymentWebhookEvent.objects.get_or_create(
            event_id=event_id,
            defaults={"gateway": gw.name, "signature_ok": True, "payload": data},
        )
        if not created and event.processed:
            return Response({"status": "already_processed"})

        # Only ever match a REAL gateway order id. Filtering on "" used to match
        # cash payments, which never have one.
        payment = (
            Payment.objects.filter(gateway_order_id=gateway_order_id).first()
            if gateway_order_id
            else None
        )
        if payment:
            try:
                finalize_payment(
                    payment,
                    success=succeeded,
                    gateway_payment_id=gateway_payment_id,
                    settled_amount=amount,
                )
            except AppError:
                # Amount mismatch: leave the event UNPROCESSED so it is visible for
                # reconciliation and can be replayed once corrected.
                logger.exception("Webhook settlement rejected for payment %s", payment.pk)
                raise
        else:
            logger.warning(
                "Webhook %s references unknown gateway order %r", event_id, gateway_order_id
            )
        event.processed = True
        event.save(update_fields=["processed"])
        return Response({"status": "ok"})


# ── Cash collection ──────────────────────────────────────
class CashCollectionRequestView(APIView):
    def post(self, request):
        raw_amount = request.data.get("amount")
        if not raw_amount:
            return Response({"error": {"code": "bad_request", "message": "amount required", "fields": {}}}, status=400)
        # Was passed straight through as whatever JSON type the client sent —
        # `.create()` doesn't run field validation/coercion, so the row's
        # in-memory `amount` stayed a raw str until the next DB round-trip.
        # Harmless as long as nothing touched it before a refresh — until
        # auto-assign (below) started reading `.remaining` (amount −
        # collected_amount) synchronously right after creation and blew up on
        # `str - int`. Validating up front also rejects "abc"/negative
        # amounts the endpoint silently accepted before.
        try:
            amount = Decimal(str(raw_amount))
        except InvalidOperation:
            return Response({"error": {"code": "bad_request", "message": "amount must be a number", "fields": {}}}, status=400)
        if amount <= 0:
            return Response({"error": {"code": "bad_request", "message": "amount must be positive", "fields": {}}}, status=400)
        # Honor a stable Idempotency-Key so a timed-out retry returns the existing
        # pickup request instead of creating a duplicate. Mirrors the payment path.
        key = request.headers.get("Idempotency-Key", "")
        if key:
            collection, created = CashCollection.objects.get_or_create(
                user=request.user, idempotency_key=key,
                defaults={"amount": amount},
            )
        else:
            collection = CashCollection.objects.create(user=request.user, amount=amount)
            created = True
        if created:
            # Used to just sit in REQUESTED until someone noticed and manually
            # assigned it — nothing ever picked it up on its own. auto_assign()
            # both routes it to an agent (free-agent-first, see
            # agents.dispatch) AND writes the CollectionAssignmentHistory audit
            # row + notifies the agent, so a raised pickup is never silent.
            from cashcollections.services import auto_assign

            auto_assign(collection, by=request.user)
            collection.refresh_from_db()
        return Response(CashCollectionSerializer(collection).data,
                        status=201 if created else 200)



