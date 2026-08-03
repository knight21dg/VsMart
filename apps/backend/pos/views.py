from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from catalog.models import Product
from core.permissions import IsCashier
from credit.services import ensure_account
from inventory.models import Barcode
from inventory.services import StockCalculationService, default_warehouse

from .models import HeldCart, POSSession, POSTransaction
from .serializers import (
    CashDrawerSerializer,
    CashMovementSerializer,
    CheckoutSerializer,
    DayClosingSerializer,
    HeldCartSerializer,
    HoldCartSerializer,
    POSSessionSerializer,
    POSTransactionSerializer,
    RefundSerializer,
    ReturnSerializer,
    SessionCloseSerializer,
    SessionOpenSerializer,
    VoidSerializer,
)
from .services import (
    POSError,
    build_receipt,
    cash_movement,
    checkout,
    close_session,
    current_session,
    drawer_summary,
    open_session,
    process_return,
    refund,
    void_transaction,
)


def _err(message, status=400, code="pos_error"):
    return Response(
        {"success": False, "message": message,
         "error": {"code": code, "message": message, "fields": {}}},
        status=status,
    )


def _require_session(request):
    session = current_session(request.user)
    if session is None:
        raise POSError("No open POS session. Open one first.")
    return session


# ── Sessions ─────────────────────────────────────────────
class SessionOpenView(APIView):
    permission_classes = [IsCashier]

    def post(self, request):
        s = SessionOpenSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        warehouse = s.validated_data.get("warehouse") or default_warehouse()
        try:
            session = open_session(
                cashier=request.user, warehouse=warehouse,
                opening_cash=s.validated_data.get("opening_cash") or 0,
            )
        except POSError as e:
            return _err(str(e))
        return Response(POSSessionSerializer(session).data, status=201)


class SessionView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        session = current_session(request.user)
        if session is None:
            return Response({"session": None})
        data = POSSessionSerializer(session).data
        data["drawer"] = drawer_summary(session)
        return Response(data)


class SessionCloseView(APIView):
    permission_classes = [IsCashier]

    def post(self, request):
        s = SessionCloseSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            session = _require_session(request)
            closing = close_session(
                session=session,
                counted_cash=s.validated_data.get("counted_cash"),
                notes=s.validated_data.get("notes", ""),
                by=request.user,
            )
        except POSError as e:
            return _err(str(e))
        return Response(DayClosingSerializer(closing).data, status=201)


class DayClosingView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        from .models import DayClosing

        qs = DayClosing.objects.all()
        if request.query_params.get("mine") in ("1", "true"):
            qs = qs.filter(session__cashier=request.user)
        return Response(DayClosingSerializer(qs[:100], many=True).data)


# ── Catalog lookups for billing ──────────────────────────
class ScanView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        code = request.query_params.get("barcode") or request.query_params.get("code")
        if not code:
            return _err("barcode is required")
        bc = Barcode.objects.select_related("product").filter(code=code).first()
        if bc is None:
            return _err("Unknown barcode.", status=404, code="not_found")
        product = bc.product
        wh = default_warehouse()
        return Response({
            "product_id": str(product.id),
            "variant_id": str(bc.variant_id) if bc.variant_id else None,
            "name": product.name,
            "price": product.price,
            "mrp": product.mrp,
            "available": StockCalculationService.available(product, wh),
            "barcode": bc.code,
        })


class ProductSearchView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        q = request.query_params.get("q", "").strip()
        products = Product.objects.filter(is_active=True)
        if q:
            products = products.filter(name__icontains=q)
        wh = default_warehouse()
        rows = [
            {
                "product_id": str(p.id),
                "name": p.name,
                "brand": p.brand,
                "unit": p.unit,
                "price": p.price,
                "mrp": p.mrp,
                "available": StockCalculationService.available(p, wh),
            }
            for p in products[:30]
        ]
        return Response(rows)


class CustomerLookupView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        phone = request.query_params.get("phone", "").strip()
        if not phone:
            return _err("phone is required")
        user = User.objects.filter(phone__endswith=phone[-10:], role="customer").first()
        if user is None:
            return _err("No customer with that phone.", status=404, code="not_found")
        account = ensure_account(user)
        return Response({
            "customer_id": str(user.id),
            "name": user.name,
            "phone": user.phone,
            "credit_status": account.status,
            "credit_limit": account.credit_limit,
            "credit_available": account.available,
            "outstanding": account.outstanding,
        })


# ── Checkout / transactions ──────────────────────────────
class CheckoutView(APIView):
    permission_classes = [IsCashier]
    throttle_scope = "pos"

    def post(self, request):
        s = CheckoutSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        lines = [
            {"product": it["product"], "variant": it.get("variant"),
             "qty": it["qty"], "discount": it.get("discount", 0)}
            for it in d["items"]
        ]
        try:
            session = _require_session(request)
            txn = checkout(
                session=session, lines=lines, payments=d.get("payments", []),
                customer=d.get("customer"), discount=d.get("discount") or 0,
                note=d.get("note", ""), by=request.user,
                allow_oversell=d.get("allow_oversell", False),
                idempotency_key=request.headers.get("Idempotency-Key", ""),
            )
        except POSError as e:
            return _err(str(e))
        return Response(POSTransactionSerializer(txn).data, status=201)


class TransactionListView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        qs = POSTransaction.objects.prefetch_related("items", "payments", "refunds")
        session_id = request.query_params.get("session")
        if session_id:
            qs = qs.filter(session_id=session_id)
        if request.query_params.get("mine") in ("1", "true"):
            qs = qs.filter(session__cashier=request.user)
        type_ = request.query_params.get("type")
        if type_:
            qs = qs.filter(type=type_)
        return Response(POSTransactionSerializer(qs[:100], many=True).data)


class TransactionDetailView(APIView):
    permission_classes = [IsCashier]

    def get(self, request, pk):
        txn = get_object_or_404(
            POSTransaction.objects.prefetch_related("items", "payments", "refunds"),
            pk=pk,
        )
        return Response(POSTransactionSerializer(txn).data)


class ReceiptView(APIView):
    permission_classes = [IsCashier]

    def get(self, request, pk):
        txn = get_object_or_404(
            POSTransaction.objects.prefetch_related("items", "payments"), pk=pk
        )
        return Response(build_receipt(txn))


class TransactionVoidView(APIView):
    permission_classes = [IsCashier]

    def post(self, request, pk):
        s = VoidSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        txn = get_object_or_404(POSTransaction, pk=pk)
        try:
            session = _require_session(request)
            void_transaction(
                txn=txn, session=session,
                reason=s.validated_data.get("reason", ""), by=request.user,
            )
        except POSError as e:
            return _err(str(e))
        txn = POSTransaction.objects.prefetch_related(
            "items", "payments", "refunds"
        ).get(pk=txn.pk)
        return Response(POSTransactionSerializer(txn).data)


class ReturnView(APIView):
    permission_classes = [IsCashier]

    def post(self, request):
        s = ReturnSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        lines = [{"product": it["product"], "qty": it["qty"]} for it in d["items"]]
        try:
            session = _require_session(request)
            rtxn = process_return(
                session=session, original=d["original"], lines=lines,
                reason=d.get("reason", ""), refund_method=d.get("refund_method"),
                by=request.user,
            )
        except POSError as e:
            return _err(str(e))
        return Response(POSTransactionSerializer(rtxn).data, status=201)


class RefundView(APIView):
    permission_classes = [IsCashier]

    def post(self, request):
        s = RefundSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        try:
            session = _require_session(request)
            ref = refund(
                transaction=d["transaction"], method=d["method"], amount=d["amount"],
                session=session, customer=d["transaction"].customer,
                reference=d.get("reference", ""), by=request.user,
            )
        except POSError as e:
            return _err(str(e))
        return Response({
            "id": str(ref.id), "transaction_id": str(ref.transaction_id),
            "method": ref.method, "amount": ref.amount,
        }, status=201)


# ── Cash drawer ──────────────────────────────────────────
class CashDrawerView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        try:
            session = _require_session(request)
        except POSError as e:
            return _err(str(e))
        moves = session.cash_movements.all()
        data = drawer_summary(session)
        data["movements"] = CashDrawerSerializer(moves, many=True).data
        return Response(data)

    def post(self, request):
        s = CashMovementSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            session = _require_session(request)
            mv = cash_movement(
                session=session, type=s.validated_data["type"],
                amount=s.validated_data["amount"],
                note=s.validated_data.get("note", ""), by=request.user,
            )
        except POSError as e:
            return _err(str(e))
        return Response(CashDrawerSerializer(mv).data, status=201)


# ── Held carts (park / resume) ───────────────────────────
class HeldCartView(APIView):
    permission_classes = [IsCashier]

    def get(self, request):
        try:
            session = _require_session(request)
        except POSError as e:
            return _err(str(e))
        carts = HeldCart.objects.filter(session=session)
        return Response(HeldCartSerializer(carts, many=True).data)

    def post(self, request):
        s = HoldCartSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        try:
            session = _require_session(request)
        except POSError as e:
            return _err(str(e))
        payload = {
            "items": [
                {"productId": it["product"].id,
                 "variantId": it["variant"].id if it.get("variant") else None,
                 "qty": it["qty"]}
                for it in d["items"]
            ]
        }
        cart = HeldCart.objects.create(
            session=session, label=d.get("label", ""), customer=d.get("customer"),
            payload=payload,
        )
        return Response(HeldCartSerializer(cart).data, status=201)


class HeldCartDetailView(APIView):
    permission_classes = [IsCashier]

    def delete(self, request, pk):
        HeldCart.objects.filter(pk=pk, session__cashier=request.user).delete()
        return Response({"status": "discarded"})


# ── Events feed (realtime substitute) ────────────────────
class EventsView(APIView):
    """Poll for stock/sale events since the last seen id — the realtime substitute
    until a websocket transport lands. `?since=<id>&type=<event_type>`."""

    permission_classes = [IsCashier]

    def get(self, request):
        from ops.models import AnalyticsEvent

        qs = AnalyticsEvent.objects.all()
        since = request.query_params.get("since")
        if since and since.isdigit():
            qs = qs.filter(id__gt=int(since))
        etype = request.query_params.get("type")
        if etype:
            qs = qs.filter(type=etype)
        rows = list(qs.order_by("id")[:200])
        return Response({
            "events": [
                {"id": e.id, "type": e.type, "payload": e.payload,
                 "createdAt": e.created_at.isoformat()}
                for e in rows
            ],
            "lastId": rows[-1].id if rows else (int(since) if since and since.isdigit() else 0),
        })


# ── POS reports ──────────────────────────────────────────
class POSReportsView(APIView):
    """`/pos/reports/<name>` — sales-by-cashier · day-closings · fast-movers ·
    slow-movers · expiry."""

    permission_classes = [IsCashier]

    def get(self, request, name):
        from datetime import timedelta

        from django.db.models import Count, F, Sum
        from django.utils import timezone

        from inventory.models import StockBatch

        if name == "sales-by-cashier":
            rows = (
                POSTransaction.objects.filter(
                    type=POSTransaction.Type.SALE, is_voided=False
                )
                .values("session__cashier_id")
                .annotate(sales=Sum("total"), count=Count("id"))
                .order_by("-sales")
            )
            return Response([
                {"cashierId": str(r["session__cashier_id"]), "sales": r["sales"],
                 "transactions": r["count"]}
                for r in rows
            ])

        if name == "day-closings":
            from .models import DayClosing
            return Response(
                DayClosingSerializer(DayClosing.objects.all()[:100], many=True).data
            )

        if name in ("fast-movers", "slow-movers"):
            from .models import POSTransactionItem
            order = "-qty" if name == "fast-movers" else "qty"
            rows = (
                POSTransactionItem.objects.filter(
                    transaction__type=POSTransaction.Type.SALE,
                    transaction__is_voided=False,
                )
                .values("product_id", "name")
                .annotate(qty=Sum("quantity"), revenue=Sum("line_total"))
                .order_by(order)[:25]
            )
            return Response([
                {"productId": str(r["product_id"]), "name": r["name"],
                 "qtySold": r["qty"], "revenue": r["revenue"]}
                for r in rows
            ])

        if name == "expiry":
            days = int(request.query_params.get("days", 30))
            cutoff = timezone.now().date() + timedelta(days=days)
            batches = (
                StockBatch.objects.filter(
                    quantity__gt=0, expiry_date__isnull=False, expiry_date__lte=cutoff
                )
                .select_related("product")
                .order_by("expiry_date")[:200]
            )
            return Response([
                {"productId": str(b.product_id), "name": b.product.name,
                 "batchNo": b.batch_no, "expiryDate": b.expiry_date.isoformat(),
                 "quantity": b.quantity}
                for b in batches
            ])

        return _err("Unknown report.", status=404, code="not_found")
