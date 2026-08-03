"""POS billing engine. Every sale/return posts an InventoryLedger movement via
`InventoryService` (stock truth) and, for credit tender, debits/credits the credit
ledger by exactly what it bills (money truth). Cash movements append to the
CashDrawer log, reconciled at day-closing."""
import uuid
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Sum
from django.utils import timezone

from core.events import record_event
from core.pricing import q
from credit.services import CreditError, apply_refund, debit_purchase, ensure_account
from inventory.models import InventoryLedger
from inventory.services import (
    InventoryError,
    InventoryService,
    StockCalculationService,
    consume_fefo,
)
from siteconfig.models import PlatformConfig

from .models import (
    CashDrawer,
    DayClosing,
    POSPayment,
    POSRefund,
    POSSession,
    POSTransaction,
    POSTransactionItem,
)

ZERO = Decimal("0.00")
LType = InventoryLedger.Type


class POSError(Exception):
    pass


class OutOfStockError(POSError):
    """Insufficient stock to ring up a line. Raised distinctly so the API can
    return a structured 409 the offline-sync client treats as a conflict (the
    cash was already taken physically) rather than a generic bad request."""

    def __init__(self, message, *, product=None, available=None):
        super().__init__(message)
        self.product = product
        self.available = available


def _code(prefix):
    return f"{prefix}-{uuid.uuid4().hex[:10].upper()}"


def gst_rate():
    return PlatformConfig.load().gst_rate


# ── Sessions ─────────────────────────────────────────────
def open_session(*, cashier, warehouse, opening_cash=ZERO):
    if POSSession.objects.filter(
        cashier=cashier, status=POSSession.Status.OPEN
    ).exists():
        raise POSError("You already have an open session. Close it first.")
    session = POSSession.objects.create(
        cashier=cashier, warehouse=warehouse, opening_cash=q(opening_cash)
    )
    if opening_cash:
        CashDrawer.objects.create(
            session=session, type=CashDrawer.Type.OPENING, amount=q(opening_cash),
            note="Opening float", created_by=cashier,
        )
    return session


def current_session(cashier):
    return POSSession.objects.filter(
        cashier=cashier, status=POSSession.Status.OPEN
    ).first()


def drawer_summary(session):
    """Signed cash totals for the session's drawer."""
    moves = session.cash_movements.all()

    def _sum(*types):
        return moves.filter(type__in=types).aggregate(s=Sum("amount"))["s"] or ZERO

    cash_sales = _sum(CashDrawer.Type.SALE)
    cash_refunds = -(_sum(CashDrawer.Type.REFUND))  # stored negative → report positive
    cash_in = _sum(CashDrawer.Type.PAY_IN)
    cash_out = -(_sum(CashDrawer.Type.PAY_OUT, CashDrawer.Type.DROP))
    expected = q(
        session.opening_cash + cash_sales - cash_refunds + cash_in - cash_out
    )
    return {
        "opening_cash": q(session.opening_cash),
        "cash_sales": q(cash_sales),
        "cash_refunds": q(cash_refunds),
        "cash_in": q(cash_in),
        "cash_out": q(cash_out),
        "expected_cash": expected,
    }


@transaction.atomic
def close_session(*, session, counted_cash=None, notes="", by=None):
    if session.status == POSSession.Status.CLOSED:
        raise POSError("Session is already closed.")
    d = drawer_summary(session)
    counted = q(counted_cash) if counted_cash is not None else d["expected_cash"]
    sales = session.transactions.filter(
        type=POSTransaction.Type.SALE, is_voided=False
    )
    total_sales = sales.aggregate(s=Sum("total"))["s"] or ZERO

    # Tender breakdown across the session's non-cash payments.
    def _tender(method):
        return (
            POSPayment.objects.filter(transaction__session=session, method=method)
            .aggregate(s=Sum("amount"))["s"]
            or ZERO
        )

    closing = DayClosing.objects.create(
        session=session,
        opening_cash=d["opening_cash"],
        cash_sales=d["cash_sales"],
        cash_refunds=d["cash_refunds"],
        cash_in=d["cash_in"],
        cash_out=d["cash_out"],
        upi_sales=q(_tender(POSPayment.Method.UPI)),
        card_sales=q(_tender(POSPayment.Method.CARD)),
        credit_sales=q(_tender(POSPayment.Method.CREDIT)),
        expected_cash=d["expected_cash"],
        counted_cash=counted,
        variance=q(counted - d["expected_cash"]),
        total_sales=q(total_sales),
        transaction_count=sales.count(),
        notes=notes,
        closed_by=by,
        closed_at=timezone.now(),
    )
    CashDrawer.objects.create(
        session=session, type=CashDrawer.Type.CLOSING, amount=ZERO,
        note=f"Counted {counted}", created_by=by,
    )
    session.status = POSSession.Status.CLOSED
    session.closed_at = timezone.now()
    session.save(update_fields=["status", "closed_at", "updated_at"])
    payload = {"session": session.id, "expected": closing.expected_cash,
               "counted": closing.counted_cash, "variance": closing.variance,
               "totalSales": closing.total_sales}
    transaction.on_commit(lambda: record_event("day_closed", payload, actor=by))
    return closing


def cash_movement(*, session, type, amount, note="", by=None):
    """Manual drawer adjustment (pay-in / pay-out / drop). Amount is signed by type."""
    signed = q(abs(Decimal(amount)))
    if type in (CashDrawer.Type.PAY_OUT, CashDrawer.Type.DROP, CashDrawer.Type.REFUND):
        signed = -signed
    return CashDrawer.objects.create(
        session=session, type=type, amount=signed, note=note, created_by=by
    )


# ── Billing ──────────────────────────────────────────────
def _price(product, variant, warehouse=None):
    # Per-store selling price when store_pricing is enabled (the POS warehouse maps
    # 1:1 to a store); otherwise the global Product.price — unchanged by default.
    base = product.price
    from stores.services import store_price, store_pricing_enabled, warehouse_store

    if warehouse is not None and store_pricing_enabled():
        base = store_price(product, warehouse_store(warehouse))
    return base + (variant.price_delta if variant else ZERO)


def _split_tax(amount, rate, inclusive):
    """Return (net, tax). When `inclusive`, `amount` is the tax-inclusive shelf price
    (Indian MRP) and tax is backed out; otherwise tax is added on top."""
    amount = q(amount)
    if inclusive:
        net = q(amount / (Decimal(1) + Decimal(rate)))
        return net, q(amount - net)
    return amount, q(amount * Decimal(rate))


@transaction.atomic
def checkout(*, session, lines, payments, customer=None, discount=ZERO, note="",
             by=None, warehouse=None, allow_oversell=False, allow_partial=False,
             idempotency_key=""):
    """Ring up a sale: build the bill, post a `sale` ledger row per line, take
    payments (cash → drawer, credit → credit ledger), set the payment status.
    Idempotent on `idempotency_key` — a retry returns the existing sale."""
    if idempotency_key:
        existing = POSTransaction.objects.filter(
            session=session, idempotency_key=idempotency_key,
            type=POSTransaction.Type.SALE,
        ).first()
        if existing:
            return existing
    if not lines:
        raise POSError("Cannot check out an empty cart.")
    warehouse = warehouse or session.warehouse
    rate = gst_rate()
    inclusive = PlatformConfig.load().pos_price_tax_inclusive

    resolved, subtotal, tax = [], ZERO, ZERO
    for ln in lines:
        product, variant, qty = ln["product"], ln.get("variant"), int(ln["qty"])
        if qty <= 0:
            raise POSError("Quantity must be positive.")
        if not allow_oversell:
            # Check the SAME bucket the sale will draw from. Checking the product
            # total here while the movement posts against the variant meant a pack
            # with no stock sailed past the guard and then blew up inside
            # post_movement as an unhandled 500 — the cashier saw "temporary problem
            # on our end" for a plain out-of-stock.
            avail = StockCalculationService.available(product, warehouse, variant)
            if qty > avail:
                label = f"{product.name} · {variant.label}" if variant else product.name
                raise OutOfStockError(
                    f"Only {avail} of {label} available.",
                    product=product, available=avail,
                )
        unit_price = _price(product, variant, warehouse)
        line_discount = q(ln.get("discount", 0))
        base = max(q(unit_price * qty) - line_discount, ZERO)
        net, line_tax = _split_tax(base, rate, inclusive)
        line_total = q(net + line_tax)
        subtotal += net
        tax += line_tax
        resolved.append(
            (product, variant, qty, unit_price, line_discount, line_tax, line_total)
        )

    discount = q(discount)  # bill-level discount, on top of any per-line discounts
    total = max(q(subtotal + tax - discount), ZERO)

    try:
        # Savepoint so a duplicate-key race (two concurrent replays of the same
        # queued offline sale) rolls back just this insert, not the whole call.
        with transaction.atomic():
            txn = POSTransaction.objects.create(
                session=session, code=_code("POS"), type=POSTransaction.Type.SALE,
                customer=customer, subtotal=q(subtotal), tax=q(tax), discount=discount,
                total=total, note=note, created_by=by, idempotency_key=idempotency_key,
            )
    except IntegrityError:
        # The other request won the race and committed the same idempotent sale;
        # return it instead of double-posting inventory + payment.
        existing = POSTransaction.objects.filter(
            session=session, idempotency_key=idempotency_key,
            type=POSTransaction.Type.SALE,
        ).first()
        if existing is not None:
            return existing
        raise
    for product, variant, qty, unit_price, line_discount, line_tax, line_total in resolved:
        POSTransactionItem.objects.create(
            transaction=txn, product=product, variant=variant, name=product.name,
            quantity=qty, unit_price=unit_price, discount=line_discount,
            tax=line_tax, line_total=line_total,
        )
        # FEFO: draw from the oldest-expiring lot first so batch stock and the
        # expiry report track reality. No batches (today's norm) => one unbatched
        # movement, exactly as before.
        try:
            consume_fefo(
                product=product, warehouse=warehouse, type=LType.SALE, quantity=qty,
                variant=variant, ref_type="pos", ref_id=txn.code,
                note=f"POS {txn.code}", created_by=by, allow_negative=allow_oversell,
            )
        except InventoryError as e:
            # The precheck above should have caught this, but it reads before the
            # row lock — a concurrent sale of the last unit lands here. Surface it as
            # the same structured 409 the cashier already knows, never a 500.
            raise OutOfStockError(
                str(e), product=product,
                available=StockCalculationService.available(product, warehouse, variant),
            )

    _take_payments(txn, payments, session=session, customer=customer, by=by,
                   allow_partial=allow_partial)
    payload = {"code": txn.code, "total": txn.total, "items": len(resolved),
               "cashier": session.cashier_id}
    transaction.on_commit(lambda: record_event("sale_completed", payload, actor=by))
    return txn


def _take_payments(txn, payments, *, session, customer, by, allow_partial=False):
    """Validate tender, take it, and set the payment status.

    Non-cash tender (upi/card/credit) cannot exceed the total; cash can over-tender
    and the surplus is returned as change. Unless `allow_partial`, the collected
    amount must cover the total. Only the *net* cash (tender − change) hits the drawer.
    """
    total = txn.total
    norm = [(p["method"], q(p["amount"]), p.get("reference", ""))
            for p in payments if q(p["amount"]) > 0]
    cash_given = sum((a for m, a, _ in norm if m == POSPayment.Method.CASH), ZERO)
    non_cash = sum((a for m, a, _ in norm if m != POSPayment.Method.CASH), ZERO)

    if non_cash > total:
        raise POSError("Non-cash payment exceeds the bill total.")
    cash_due = total - non_cash
    if cash_given + non_cash < total and not allow_partial:
        raise POSError(
            f"Short payment: collected {cash_given + non_cash} of total {total}."
        )
    change = max(cash_given - cash_due, ZERO)
    net_cash = min(cash_given, cash_due)

    credit_used = ZERO
    for method, amount, ref in norm:
        if method == POSPayment.Method.CREDIT:
            if customer is None:
                raise POSError("Credit tender requires a customer.")
            account = ensure_account(customer)
            try:
                debit_purchase(account, amount, note=f"POS {txn.code}")
            except CreditError as e:
                raise POSError(str(e))
            credit_used += amount
        POSPayment.objects.create(
            transaction=txn, method=method, amount=amount, reference=ref
        )
    if net_cash > 0:
        CashDrawer.objects.create(
            session=session, type=CashDrawer.Type.SALE, amount=net_cash,
            transaction=txn, created_by=by,
        )

    paid_value = non_cash + net_cash
    txn.credit_used = credit_used
    txn.change_due = change
    if paid_value >= total:
        txn.payment_status = POSTransaction.PaymentStatus.PAID
    elif paid_value > 0:
        txn.payment_status = POSTransaction.PaymentStatus.PARTIAL
    else:
        txn.payment_status = POSTransaction.PaymentStatus.PENDING
    txn.save(update_fields=["credit_used", "change_due", "payment_status", "updated_at"])


# ── Returns / refunds ────────────────────────────────────
@transaction.atomic
def process_return(*, session, original, lines, reason="", refund_method=None,
                   by=None, warehouse=None):
    """Return goods against an original sale: post `return` ledger rows (stock back),
    then refund to the chosen method (cash → drawer, credit → credit ledger)."""
    if original.type != POSTransaction.Type.SALE:
        raise POSError("Returns must reference a sale.")
    if original.is_voided:
        raise POSError("This sale has been voided; nothing to return.")
    warehouse = warehouse or session.warehouse
    rate = gst_rate()
    inclusive = PlatformConfig.load().pos_price_tax_inclusive

    resolved, subtotal, tax = [], ZERO, ZERO
    for ln in lines:
        product, qty = ln["product"], int(ln["qty"])
        orig_item = original.items.filter(product=product).first()
        if orig_item is None:
            raise POSError(f"{product.name} was not on the original sale.")
        already = (
            POSTransaction.objects.filter(original=original)
            .filter(items__product=product)
            .aggregate(s=Sum("items__quantity"))["s"]
            or 0
        )
        if qty <= 0 or qty + already > orig_item.quantity:
            raise POSError(f"Cannot return {qty} of {product.name} (over the sold qty).")
        unit_price = orig_item.unit_price
        base = q(unit_price * qty)
        net, line_tax = _split_tax(base, rate, inclusive)
        line_total = q(net + line_tax)
        subtotal += net
        tax += line_tax
        resolved.append((product, orig_item.variant, qty, unit_price, line_tax, line_total))

    total = q(subtotal + tax)
    rtxn = POSTransaction.objects.create(
        session=session, code=_code("RET"), type=POSTransaction.Type.RETURN,
        customer=original.customer, original=original, subtotal=q(subtotal),
        tax=q(tax), total=total, note=reason, created_by=by,
    )
    for product, variant, qty, unit_price, line_tax, line_total in resolved:
        POSTransactionItem.objects.create(
            transaction=rtxn, product=product, variant=variant, name=product.name,
            quantity=qty, unit_price=unit_price, tax=line_tax, line_total=line_total,
        )
        InventoryService.post_movement(
            product=product, warehouse=warehouse, type=LType.RETURN, quantity=qty,
            variant=variant, ref_type="pos_return", ref_id=rtxn.code,
            note=f"Return {rtxn.code}", created_by=by,
        )

    method = refund_method or _original_method(original)
    refund(transaction=rtxn, method=method, amount=total, session=session,
           customer=original.customer, by=by)
    rtxn.payment_status = POSTransaction.PaymentStatus.REFUNDED
    rtxn.save(update_fields=["payment_status", "updated_at"])
    return rtxn


def _original_method(original):
    p = original.payments.first()
    return p.method if p else POSPayment.Method.CASH


@transaction.atomic
def refund(*, transaction, method, amount, session, customer=None, reference="",
           by=None):
    """Record a refund for a return transaction and move the money."""
    amount = q(amount)
    if method == POSPayment.Method.CREDIT:
        if customer is None:
            raise POSError("Credit refund requires a customer.")
        apply_refund(ensure_account(customer), amount, note=f"Refund {transaction.code}")
    elif method == POSPayment.Method.CASH:
        CashDrawer.objects.create(
            session=session, type=CashDrawer.Type.REFUND, amount=-amount,
            transaction=transaction, created_by=by,
        )
    return POSRefund.objects.create(
        transaction=transaction, method=method, amount=amount, reference=reference
    )


@transaction.atomic
def void_transaction(*, txn, session, reason="", by=None):
    """Cancel a whole sale (cashier error): put every line's stock back, reverse each
    tender (cash → drawer out, credit → credit ledger), and mark it voided. A void is
    all-or-nothing; partial customer returns use `process_return` instead."""
    if txn.type != POSTransaction.Type.SALE:
        raise POSError("Only sales can be voided.")
    if txn.is_voided:
        raise POSError("This sale is already voided.")
    if txn.returns.exists():
        raise POSError("This sale has returns; void is not allowed — refund instead.")
    warehouse = session.warehouse
    for item in txn.items.select_related("product"):
        InventoryService.post_movement(
            product=item.product, warehouse=warehouse, type=LType.RETURN,
            quantity=item.quantity, variant=item.variant, ref_type="pos_void",
            ref_id=txn.code, note=f"Void {txn.code}", created_by=by,
        )
    for pay in txn.payments.all():
        refund(transaction=txn, method=pay.method, amount=pay.amount, session=session,
               customer=txn.customer, reference=f"void:{pay.reference}", by=by)
    txn.is_voided = True
    txn.voided_at = timezone.now()
    txn.void_reason = reason
    txn.payment_status = POSTransaction.PaymentStatus.REFUNDED
    txn.save(update_fields=["is_voided", "voided_at", "void_reason",
                            "payment_status", "updated_at"])
    return txn


def build_receipt(txn) -> dict:
    """Thermal-printer-friendly receipt payload: store header, lines, CGST/SGST split,
    tenders and change. Intra-state GST is shown as equal CGST + SGST halves. The
    line ``amount`` is the PRE-TAX taxable value (rate×qty − discount) so it
    reconciles with Subtotal + CGST + SGST = Total (tax is broken out separately)."""
    cfg = PlatformConfig.load()
    half_tax = q(txn.tax / 2)
    # Prefer the actual selling store (from the till's warehouse) over the generic
    # platform-config header, so the receipt shows the real branch + its GSTIN.
    from stores.services import warehouse_store
    store = warehouse_store(getattr(txn.session, "warehouse", None)) if txn.session_id else None
    store_name = (store.name if store else "") or cfg.store_name
    store_addr = (store.address if store and store.address else "") or cfg.store_address
    store_gstin = (store.gstin if store and store.gstin else "") or cfg.store_gstin
    store_phone = (store.phone if store and store.phone else "") or cfg.support_phone
    return {
        "store": {
            "name": store_name,
            "address": store_addr,
            "gstin": store_gstin,
            "phone": store_phone,
        },
        "receipt_no": txn.code,
        "type": txn.type,
        "datetime": txn.created_at.isoformat() if txn.created_at else None,
        "cashier_id": str(txn.created_by_id) if txn.created_by_id else None,
        "customer_id": str(txn.customer_id) if txn.customer_id else None,
        "currency": cfg.currency,
        "items": [
            {
                "name": i.name,
                "qty": i.quantity,
                "rate": i.unit_price,
                "discount": i.discount,
                "tax": i.tax,
                # Pre-tax taxable line (= line_total − line_tax); tax is shown separately.
                "amount": q(i.line_total - i.tax),
            }
            for i in txn.items.all()
        ],
        "subtotal": txn.subtotal,
        "discount": txn.discount,
        "tax": {"total": txn.tax, "cgst": half_tax, "sgst": q(txn.tax - half_tax)},
        "total": txn.total,
        "payments": [
            {"method": p.method, "amount": p.amount, "reference": p.reference}
            for p in txn.payments.all()
        ],
        "change_due": txn.change_due,
        "is_voided": txn.is_voided,
        "footer": "Thank you for shopping at " + store_name,
    }
