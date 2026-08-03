from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models import Q

from catalog.models import Product
from core.models import TimeStampedModel

ZERO = Decimal("0.00")


class OrderStatus(models.TextChoices):
    DRAFT = "draft"
    PLACED = "placed"
    PENDING = "pending"  # legacy alias of placed (awaiting payment/confirmation)
    CONFIRMED = "confirmed"
    PACKED = "packed"
    READY_FOR_DISPATCH = "ready_for_dispatch"
    OUT_FOR_DELIVERY = "out_for_delivery"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"
    REJECTED = "rejected"
    RETURNED = "returned"
    PARTIALLY_RETURNED = "partially_returned"
    FAILED_DELIVERY = "failed_delivery"


ACTIVE_STATUSES = [
    "placed", "pending", "confirmed", "packed", "ready_for_dispatch",
    "out_for_delivery",
]

# Forward lifecycle for the admin "advance status" control (terminal/exception
# states sit outside the linear flow and are set explicitly).
LIFECYCLE = [
    "draft", "placed", "confirmed", "packed", "ready_for_dispatch",
    "out_for_delivery", "delivered",
]

# States from which nothing may move — the order is closed for good.
#
# `delivered` is deliberately NOT here: it's the end of the happy path, but a
# return still follows it, so it has its own outgoing edges in `can_transition`.
TERMINAL_STATUSES = frozenset({
    "cancelled", "rejected", "returned", "partially_returned",
})

# `pending` is a legacy alias of `placed`; treat them as the same rung.
_LIFECYCLE_INDEX = {name: i for i, name in enumerate(LIFECYCLE)}
_LIFECYCLE_INDEX["pending"] = _LIFECYCLE_INDEX["placed"]


def _rung(status: str):
    return _LIFECYCLE_INDEX.get(status)


def can_transition(current: str, new: str) -> bool:
    """Whether an order may move from ``current`` to ``new``.

    ``advance_status`` used to write whatever it was handed with no check at all,
    so an agent could POST "delivered" on a cancelled or never-paid order — which
    fulfilled its stock and awarded loyalty points for goods nobody bought.
    ``LIFECYCLE`` was declared for this purpose and never consulted.

    The rules, rather than a fixed edge table, because a store legitimately skips
    rungs (confirmed straight to out-for-delivery when it dispatches immediately),
    and an edge table strict enough to be useful rejected that real flow:

      * a no-op is allowed, so a retried tap or duplicate event is idempotent;
      * nothing leaves a terminal state;
      * **delivered** is reachable ONLY from out_for_delivery — this is the rule
        that stops an unpaid or cancelled order being marked delivered;
      * **failed_delivery** likewise only from out_for_delivery;
      * a failed delivery may be re-attempted or written off;
      * returns follow delivery;
      * cancellation/rejection only before the goods are with a rider;
      * otherwise the move must be FORWARD along the lifecycle — never backwards.
    """
    if current == new:
        return True
    if current in TERMINAL_STATUSES:
        return False

    if new == "delivered":
        return current == "out_for_delivery"
    if new == "failed_delivery":
        return current == "out_for_delivery"
    if new in ("returned", "partially_returned"):
        return current in ("delivered", "failed_delivery")
    if new == "cancelled":
        # Not once a rider is carrying it — that unwinds through the delivery flow.
        return current in (
            "draft", "placed", "pending", "confirmed", "packed",
            "ready_for_dispatch", "failed_delivery",
        )
    if new == "rejected":
        return current in ("draft", "placed", "pending", "confirmed")
    if new == "out_for_delivery" and current == "failed_delivery":
        return True  # re-attempt

    here, there = _rung(current), _rung(new)
    if here is None or there is None:
        return False
    return there > here


class Order(TimeStampedModel):
    class PaymentMethod(models.TextChoices):
        COD = "cod"
        UPI = "upi"
        CARD = "card"
        NETBANKING = "netbanking"
        CREDIT = "credit"

    class PaymentStatus(models.TextChoices):
        PENDING = "pending"
        PAID = "paid"
        FAILED = "failed"
        REFUNDED = "refunded"

    class StockState(models.TextChoices):
        NONE = "none"            # untracked products
        RESERVED = "reserved"    # held at checkout; on-hand not yet reduced
        FULFILLED = "fulfilled"  # delivered → sale posted to the ledger
        RELEASED = "released"    # cancelled → reservation returned

    class Source(models.TextChoices):
        APP = "app", "Mobile App"
        POS = "pos", "POS"
        ADMIN = "admin", "Admin"
        WEB = "web", "Web"

    code = models.CharField(max_length=20, unique=True, blank=True)
    source = models.CharField(max_length=8, choices=Source.choices, default=Source.APP)
    stock_state = models.CharField(
        max_length=10, choices=StockState.choices, default=StockState.NONE
    )
    idempotency_key = models.CharField(max_length=80, blank=True, db_index=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="orders"
    )
    status = models.CharField(
        max_length=20, choices=OrderStatus.choices, default=OrderStatus.PENDING
    )
    placed_at = models.DateTimeField(auto_now_add=True)
    delivery_slot = models.CharField(max_length=40, blank=True)
    estimated_delivery = models.DateTimeField(null=True, blank=True)
    address_snapshot = models.JSONField(default=dict)
    payment_method = models.CharField(max_length=12, choices=PaymentMethod.choices)
    payment_status = models.CharField(
        max_length=10, choices=PaymentStatus.choices, default=PaymentStatus.PENDING
    )
    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    delivery_fee = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    gst = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    platform_fee = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    discount = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    total = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    zone = models.ForeignKey(
        "zones.Zone", on_delete=models.SET_NULL, null=True, blank=True
    )
    # The store that fulfils this order (the serviceable store for the delivery
    # zone). Routing target for inventory, delivery agents, and collections.
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="orders",
    )
    # Immutable snapshot of WHERE this order was placed (store/zone), captured at
    # placement so invoice history never changes even if the store/zone is later
    # renamed, reassigned, or deleted (the FKs above are SET_NULL).
    store_name = models.CharField(max_length=120, blank=True)
    store_address = models.CharField(max_length=300, blank=True)
    zone_name = models.CharField(max_length=80, blank=True)
    credit_used = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    coupon_code = models.CharField(max_length=40, blank=True)

    class CreditPlan(models.TextChoices):
        WEEKEND = "weekend"
        MONTH_END = "month_end"

    # Chosen VS Credit repayment plan + the resulting payout (due) date. Only set
    # for credit orders; the date is computed server-side from the plan.
    credit_plan = models.CharField(
        max_length=12, choices=CreditPlan.choices, blank=True
    )
    credit_due_date = models.DateField(null=True, blank=True)

    class Meta:
        ordering = ["-placed_at"]
        indexes = [models.Index(fields=["user", "placed_at"])]
        constraints = [
            # Race-safe checkout idempotency: a double-submit (same key) can't create
            # two orders even under concurrent requests — the DB rejects the second
            # INSERT/UPDATE and place_order's atomic block rolls it back. Mirrors the
            # POS uniq_pos_sale_idempotency guard. Partial: blank keys are unconstrained.
            models.UniqueConstraint(
                fields=["user", "idempotency_key"],
                condition=~Q(idempotency_key=""),
                name="uniq_order_idempotency",
            ),
        ]

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.code:
            self.code = f"VSORD{100000 + self.pk}"
            super().save(update_fields=["code"])

    @property
    def is_active(self):
        return self.status in ACTIVE_STATUSES


class OrderItem(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="items")
    product = models.ForeignKey(Product, on_delete=models.SET_NULL, null=True)
    # Which pack was ordered. Until stock went per-variant the line only carried the
    # composed `name` ("Rice · 1kg"), so fulfilment could not tell which bucket to
    # decrement — it guessed the product pool. NULL = a product with no variants.
    variant = models.ForeignKey(
        "catalog.ProductVariant", on_delete=models.SET_NULL, null=True, blank=True
    )
    name = models.CharField(max_length=160)
    brand = models.CharField(max_length=80, blank=True)
    unit = models.CharField(max_length=40, blank=True)
    image_url = models.URLField(blank=True, null=True)
    price = models.DecimalField(max_digits=12, decimal_places=2)
    mrp = models.DecimalField(max_digits=12, decimal_places=2)
    # GST rate (%) snapshotted from the product at order time — so the invoice's tax
    # breakdown is reproducible even if the product's rate changes later.
    gst_rate = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    quantity = models.PositiveIntegerField()

    @property
    def line_total(self):
        return self.price * self.quantity


class OrderStatusEvent(models.Model):
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="timeline")
    status = models.CharField(max_length=20, choices=OrderStatus.choices)
    note = models.CharField(max_length=200, blank=True)
    at = models.DateTimeField(auto_now_add=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )

    class Meta:
        ordering = ["at"]


class DeliveryAssignment(TimeStampedModel):
    class Status(models.TextChoices):
        ASSIGNED = "assigned"
        PICKED = "picked"
        DELIVERED = "delivered"
        FAILED = "failed"

    order = models.OneToOneField(
        Order, on_delete=models.CASCADE, related_name="delivery"
    )
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="deliveries",
    )
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ASSIGNED)
    assigned_at = models.DateTimeField(auto_now_add=True)
    delivered_at = models.DateTimeField(null=True, blank=True)


class OrderTracking(models.Model):
    order = models.OneToOneField(Order, on_delete=models.CASCADE, related_name="tracking")
    agent_name = models.CharField(max_length=120, blank=True)
    # So the customer can actually reach the rider. Snapshotted onto the tracking row
    # when the agent is assigned — the tracking sheet reads it without joining to the
    # agent, and it survives even if the agent record changes later.
    agent_phone = models.CharField(max_length=20, blank=True)
    agent_photo_url = models.CharField(max_length=500, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    eta = models.CharField(max_length=40, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
