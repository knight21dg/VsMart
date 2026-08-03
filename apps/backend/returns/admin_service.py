"""Admin Returns / Refunds workflow — review return requests, move them through
requested → approved/rejected → picked → refunded, and process the refund
(credit reversal + inventory restock) on completion.
"""
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from .models import ReturnRequest, ReturnStatus

ZERO = Decimal("0.00")

# Allowed forward transitions (admin can also reject from most states).
# `requested → picked` is the field-agent path: the agent inspects the goods at
# the customer's door and collects them, which approves and picks up in one step
# (see returns.pickup_services.complete). The refund itself stays a store action.
TRANSITIONS = {
    "requested": {"approved", "rejected", "picked"},
    "approved": {"picked", "rejected", "refunded"},
    "picked": {"refunded", "rejected"},
}

# Final states — no further transitions, so the refund/restock side effects run once.
TERMINAL = {ReturnStatus.REFUNDED, ReturnStatus.REJECTED}


def _f(v):
    return float(v or 0)


def list_returns_qs(status=None):
    """Unbounded, lazily-evaluated queryset of return requests for the admin list.

    Kept free of any slice so the caller can paginate it — a paginator turns this
    into one ``COUNT`` plus a single-page query rather than materialising every
    return.
    """
    qs = ReturnRequest.objects.select_related("user", "order").prefetch_related("items")
    if status:
        qs = qs.filter(status=status)
    return qs


def return_rows(page):
    """Render one page of :func:`list_returns_qs` into API rows."""
    return [
        {
            "code": r.code,
            "orderCode": r.order.code if r.order else None,
            "customer": (r.user.name or r.user.phone) if r.user else None,
            "phone": r.user.phone if r.user else None,
            "reason": r.reason,
            "status": r.status,
            "refundAmount": _f(r.refund_amount),
            "items": r.items.count(),
            "createdAt": r.created_at,
            "resolvedAt": r.resolved_at,
        }
        for r in page
    ]


def list_returns(status=None, limit=200):
    """Bounded convenience wrapper — the first ``limit`` rows. Prefer paginating
    :func:`list_returns_qs` for anything an operator reads."""
    return return_rows(list_returns_qs(status)[:limit])


def return_detail(ret):
    o = ret.order
    return {
        "code": ret.code,
        "status": ret.status,
        "reason": ret.reason,
        "description": ret.description,
        "refundAmount": _f(ret.refund_amount),
        "createdAt": ret.created_at,
        "resolvedAt": ret.resolved_at,
        "decisionNote": ret.decision_note,
        "decidedBy": ret.decided_by.name if ret.decided_by else None,
        "order": {
            "code": o.code if o else None,
            "total": _f(o.total) if o else 0,
            "paymentMethod": o.payment_method if o else None,
            "paymentStatus": o.payment_status if o else None,
            "status": o.status if o else None,
        },
        "customer": {
            "id": str(ret.user_id) if ret.user_id else None,
            "name": (ret.user.name or ret.user.phone) if ret.user else None,
            "phone": ret.user.phone if ret.user else None,
        },
        "items": [
            {"name": it.product_name, "quantity": it.quantity, "amount": _f(it.amount)}
            for it in ret.items.all()
        ],
    }


@transaction.atomic
def set_return_status(ret, status, by=None, note=""):
    """Transition a return; on `refunded`, reverse credit + restock inventory.

    Locks the return row and re-reads its status so a double-click / concurrent
    approval can't refund + restock twice, and runs the whole reversal (credit +
    inventory + order + status) atomically. Re-entering a terminal state is rejected.

    `note` is the reviewer's optional decision rationale; `by` is the staff member
    making the call. Both are persisted for the audit trail.
    """
    if status not in ReturnStatus.values:
        raise ValueError(f"Invalid status '{status}'")
    ret = ReturnRequest.objects.select_for_update().get(pk=ret.pk)
    if ret.status in TERMINAL:
        raise ValueError(f"Return {ret.code} is already {ret.status}.")
    allowed = TRANSITIONS.get(ret.status, set())
    if status != ret.status and allowed and status not in allowed:
        raise ValueError(f"Cannot move {ret.status} → {status}")

    fields = ["status", "decided_by"]
    ret.status = status
    ret.decided_by = by
    if note:
        ret.decision_note = note
        fields.append("decision_note")
    if status == ReturnStatus.REFUNDED:
        _process_refund(ret, by)
        ret.resolved_at = timezone.now()
        fields.append("resolved_at")
    elif status == ReturnStatus.REJECTED:
        ret.resolved_at = timezone.now()
        fields.append("resolved_at")
    ret.save(update_fields=fields)
    return ret


def _process_refund(ret, by=None):
    order = ret.order
    if order is None:
        return
    amount = ret.refund_amount or ZERO

    # 1. Credit reversal (only for credit orders that drew on the limit).
    if (
        order.payment_method == "credit"
        and order.credit_used
        and order.credit_used > 0
        and amount > 0
    ):
        from credit.services import apply_refund, ensure_account

        apply_refund(
            ensure_account(order.user), min(amount, order.credit_used),
            order=order, note=f"Return {ret.code}",
        )
    # 1b. Money actually paid on an instrument (online / COD) → record an outbound
    #     refund transaction and reverse it through the gateway. Idempotent on the
    #     return code so re-approval never double-refunds. Credit orders are handled
    #     on the ledger above (nothing left the instrument there).
    elif amount > 0 and order.payment_status == "paid":
        from payments.services import refund_payment

        refund_payment(
            order, min(amount, order.total or amount), by=by,
            reason=f"Return {ret.code}", idempotency_key=f"refund_{ret.code}",
        )

    # 2. Restock returned items into the store's warehouse (best-effort).
    from inventory.models import InventoryLedger
    from inventory.services import InventoryError, InventoryService

    wh = order.store.warehouse if order.store and order.store.warehouse_id else None
    order_items = {
        oi.name: oi for oi in order.items.select_related("product", "variant")
    }
    restocked = False
    for ri in ret.items.all():
        oi = order_items.get(ri.product_name)
        if oi and oi.product and oi.product.stock_count is not None:
            try:
                # Back into the pack that was sold — the order line records it, so
                # a returned 1kg restocks 1kg rather than landing somewhere unsellable.
                InventoryService.post_movement(
                    product=oi.product, variant=oi.variant, warehouse=wh,
                    type=InventoryLedger.Type.RETURN, quantity=ri.quantity,
                    ref_type="return", ref_id=ret.code,
                    note=f"Return {ret.code}", created_by=by,
                )
                restocked = True
            except InventoryError:
                pass

    # 3. Reflect on the order (full vs partial return) + payment status.
    order.payment_status = "refunded"
    new_status = "returned" if not _is_partial(ret, order) else "partially_returned"
    if order.status not in ("cancelled", "rejected"):
        order.status = new_status
        order.save(update_fields=["payment_status", "status"])
    else:
        order.save(update_fields=["payment_status"])

    from orders.models import OrderStatusEvent

    OrderStatusEvent.objects.create(
        order=order, status=order.status, by=by, note=f"Refund {ret.code}"
    )
    return restocked


def _is_partial(ret, order) -> bool:
    """A return is partial if it covers fewer units than the order shipped."""
    ret_units = sum(it.quantity for it in ret.items.all())
    order_units = sum(oi.quantity for oi in order.items.all())
    return bool(ret_units) and ret_units < order_units
