"""Canonical definitions for the numbers more than one screen shows.

Lives in `core` rather than in a feature app because every surface consumes it —
the admin dashboard, accounting, the store panel, CRM and the report builders.
A shared definition owned by a leaf BI app would invert the dependency.

The admin dashboard, the accounting page, the store dashboard and the report
builders each grew their own arithmetic for "revenue", "collections" and
"inventory value". They disagreed, and because every one of them returned a
plausible number nothing ever looked broken:

* **Revenue** — the dashboard summed `Order.total` over every non-cancelled order,
  so it booked money on PLACEMENT, counted orders that later returned, and left POS
  counter sales out entirely. Accounting was fixed to mean delivered + POS − refunds;
  the dashboard was not, so the two headline figures on the two most-used screens
  contradicted each other.
* **Collections** — the dashboard summed `CashCollection.amount`, which is the
  amount we set out to recover, not `collected_amount`, which is what came back. On
  prod that read ₹6,075 against ₹5,351 actually recovered, and a partial collection
  reported as a full one.
* **Inventory value** — valued at `product.price`, the SELLING price, overstating
  the balance sheet by the entire margin. `inventory.services.stock_valuation`
  already values at weighted-average cost; nothing used it.

Anything user-visible that needs one of these numbers should call this module
rather than re-deriving it.
"""
from decimal import Decimal

from django.db.models import Count, Sum

ZERO = Decimal("0.00")

DELIVERED = "delivered"
RETURNED = "returned"
CANCELLED = "cancelled"

#: Order states that are neither settled nor abandoned — written business that has
#: not yet become revenue. Derived from what is NOT terminal so a newly added
#: status defaults to "in flight" rather than silently becoming revenue.
TERMINAL = {DELIVERED, RETURNED, CANCELLED}


def _f(v):
    return float(v or 0)


def order_book(start, end=None, *, store=None):
    """Orders placed in the window, bucketed by what each state means for revenue."""
    from orders.models import Order

    qs = Order.objects.filter(placed_at__gte=start)
    if end is not None:
        qs = qs.filter(placed_at__lte=end)
    if store is not None:
        qs = qs.filter(store_id=store)

    rows = {
        r["status"]: {"n": r["n"], "value": _f(r["v"])}
        for r in qs.values("status").annotate(n=Count("id"), v=Sum("total"))
    }
    delivered = rows.get(DELIVERED, {"n": 0, "value": 0.0})
    returned = rows.get(RETURNED, {"n": 0, "value": 0.0})
    cancelled = rows.get(CANCELLED, {"n": 0, "value": 0.0})
    in_flight_n = sum(b["n"] for s, b in rows.items() if s not in TERMINAL)
    in_flight_v = sum(b["value"] for s, b in rows.items() if s not in TERMINAL)
    return {
        "placed": delivered["n"] + returned["n"] + in_flight_n,
        "grossOrdered": round(delivered["value"] + returned["value"] + in_flight_v, 2),
        "delivered": delivered["n"],
        "deliveredValue": round(delivered["value"], 2),
        "inFlight": in_flight_n,
        "inFlightValue": round(in_flight_v, 2),
        "returned": returned["n"],
        "returnedValue": round(returned["value"], 2),
        "cancelled": cancelled["n"],
        "cancelledValue": round(cancelled["value"], 2),
    }


def pos_net(start, end=None, *, warehouse=None):
    """(net, sale_count) for POS counter trading — sales less returns, voids excluded."""
    try:
        from pos.models import POSTransaction
    except Exception:
        return 0.0, 0

    qs = POSTransaction.objects.filter(created_at__gte=start, is_voided=False)
    if end is not None:
        qs = qs.filter(created_at__lte=end)
    if warehouse is not None:
        qs = qs.filter(session__warehouse_id=warehouse)
    sales = qs.filter(type="sale").aggregate(s=Sum("total"), n=Count("id"))
    rets = qs.filter(type="return").aggregate(s=Sum("total"))
    return round(_f(sales["s"]) - _f(rets["s"]), 2), (sales["n"] or 0)


def refunds(start, end=None, *, store=None):
    """(amount, count) of returns actually refunded in the window.

    `store` scopes to refunds against that store's own orders. Without it a
    store-scoped revenue figure was reduced by every refund on the platform — three
    different stores reported the identical monthly revenue because one ₹808 refund
    was being charged to all of them.
    """
    try:
        from returns.models import ReturnRequest
    except Exception:
        return 0.0, 0

    qs = ReturnRequest.objects.filter(status="refunded", resolved_at__gte=start)
    if end is not None:
        qs = qs.filter(resolved_at__lte=end)
    if store is not None:
        qs = qs.filter(order__store_id=store)
    r = qs.aggregate(s=Sum("refund_amount"), n=Count("id"))
    return round(_f(r["s"]), 2), (r["n"] or 0)


def net_revenue(start, end=None, *, store=None, warehouse=None):
    """The one revenue definition: delivered orders + POS counter net − refunds."""
    book = order_book(start, end, store=store)
    pos, pos_n = pos_net(start, end, warehouse=warehouse)
    refunded, refund_n = refunds(start, end, store=store)
    return {
        "delivered": book["deliveredValue"],
        "pos": pos,
        "posTransactions": pos_n,
        "refunds": refunded,
        "returnsCount": refund_n,
        "net": round(book["deliveredValue"] + pos - refunded, 2),
    }


def cash_recovered(start=None, end=None, *, agent=None, user=None):
    """What collections actually brought back — `collected_amount`, partials included.

    NOT `amount`, which is the target. A ₹1,000 case that recovered ₹400 is ₹400.
    """
    from payments.models import CashCollection

    qs = CashCollection.objects.filter(
        status__in=(
            CashCollection.Status.COLLECTED,
            CashCollection.Status.PARTIALLY_COLLECTED,
        ),
    )
    if start is not None:
        qs = qs.filter(collected_at__gte=start)
    if end is not None:
        qs = qs.filter(collected_at__lte=end)
    if agent is not None:
        qs = qs.filter(agent=agent)
    if user is not None:
        qs = qs.filter(user=user)
    return _f(qs.aggregate(s=Sum("collected_amount"))["s"])


def inventory_valuation(warehouse=None):
    """`(value, costed_pct)` for stock on hand.

    `stock_valuation` costs each bucket via `weighted_average_cost`, which **falls
    back to `Product.price` when nothing costed was ever received for that
    product×warehouse**. That fallback is defensible for a valuation — a number is
    needed and the selling price is the only one available — but it is emphatically
    not cost, and left unqualified it reintroduces the very overstatement this audit
    removed. On prod today 33% of the holding (₹377,844 of ₹1,144,044) is valued that
    way.

    So the share genuinely backed by costed receipts is returned alongside the value.
    Callers that display the figure should surface it; a 67%-costed valuation is not
    the same claim as a costed valuation.
    """
    from inventory.models import InventoryLedger, StockItem
    from inventory.services import weighted_average_cost

    costed = ZERO
    fallback = ZERO
    items = StockItem.objects.select_related("product", "variant", "warehouse").filter(
        quantity__gt=0
    )
    if warehouse is not None:
        items = items.filter(warehouse_id=warehouse)
    # One query for which (product, warehouse) pairs have any costed inbound, rather
    # than an .exists() per stock row.
    priced = set(
        InventoryLedger.objects.filter(unit_cost__isnull=False, quantity__gt=0)
        .values_list("product_id", "warehouse_id")
        .distinct()
    )
    for it in items:
        value = Decimal(it.quantity) * weighted_average_cost(
            it.product, it.warehouse, it.variant
        )
        if (it.product_id, it.warehouse_id) in priced:
            costed += value
        else:
            fallback += value
    total = costed + fallback
    pct = round(float(costed / total * 100), 1) if total else None
    return float(total), pct


def inventory_value_at_cost(warehouse=None):
    """Just the value. Prefer `inventory_valuation` where the coverage can be shown."""
    return inventory_valuation(warehouse=warehouse)[0]


def customer_lifetime_revenue(user):
    """What a customer has actually generated — delivered orders less refunds.

    CRM used `Σ Order.total EXCLUDE cancelled`, which books revenue the moment an
    order is placed and so inflates every customer-health and segmentation figure by
    whatever is currently in flight. Same rule as the platform revenue definition,
    scoped to one customer.
    """
    from orders.models import Order

    delivered = _f(
        Order.objects.filter(user=user, status=DELIVERED)
        .aggregate(s=Sum("total"))["s"]
    )
    refunded = 0.0
    try:
        from returns.models import ReturnRequest

        refunded = _f(
            ReturnRequest.objects.filter(user=user, status="refunded")
            .aggregate(s=Sum("refund_amount"))["s"]
        )
    except Exception:
        pass
    return round(delivered - refunded, 2)
