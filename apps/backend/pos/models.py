from decimal import Decimal

from django.conf import settings
from django.db import models

from catalog.models import Product, ProductVariant
from core.models import TimeStampedModel
from inventory.models import Warehouse

ZERO = Decimal("0.00")


class POSSession(TimeStampedModel):
    """A cashier's till session at a store/warehouse. One open session per cashier."""

    class Status(models.TextChoices):
        OPEN = "open"
        CLOSED = "closed"

    cashier = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="pos_sessions"
    )
    warehouse = models.ForeignKey(
        Warehouse, on_delete=models.PROTECT, related_name="pos_sessions"
    )
    status = models.CharField(
        max_length=8, choices=Status.choices, default=Status.OPEN
    )
    terminal = models.CharField(max_length=40, blank=True)  # register / till id
    opening_cash = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    opened_at = models.DateTimeField(auto_now_add=True)
    closed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-opened_at"]

    def __str__(self):
        return f"Session {self.pk} ({self.cashier_id}, {self.status})"


class POSTransaction(TimeStampedModel):
    """A till sale or return. `code` is the human-facing receipt number."""

    class Type(models.TextChoices):
        SALE = "sale"
        RETURN = "return"

    class PaymentStatus(models.TextChoices):
        PAID = "paid"
        PARTIAL = "partial"
        PENDING = "pending"
        REFUNDED = "refunded"

    session = models.ForeignKey(
        POSSession, on_delete=models.PROTECT, related_name="transactions"
    )
    code = models.CharField(max_length=24, unique=True)
    type = models.CharField(max_length=8, choices=Type.choices, default=Type.SALE)
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="pos_purchases",
    )
    original = models.ForeignKey(
        "self", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="returns",
    )
    subtotal = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    tax = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    discount = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    total = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    payment_status = models.CharField(
        max_length=9, choices=PaymentStatus.choices, default=PaymentStatus.PENDING
    )
    credit_used = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    change_due = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    is_voided = models.BooleanField(default=False)
    voided_at = models.DateTimeField(null=True, blank=True)
    void_reason = models.CharField(max_length=200, blank=True)
    idempotency_key = models.CharField(max_length=80, blank=True, db_index=True)
    note = models.CharField(max_length=200, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="pos_created",
    )

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["session", "created_at"])]
        constraints = [
            # Race-safe idempotency for offline sale replay: at most one SALE per
            # (session, idempotency_key) when a key is supplied. Blank keys (no
            # idempotency requested) are excluded so they never collide.
            models.UniqueConstraint(
                fields=["session", "idempotency_key"],
                condition=models.Q(type="sale") & ~models.Q(idempotency_key=""),
                name="uniq_pos_sale_idempotency",
            ),
        ]

    def __str__(self):
        return f"{self.type} {self.code} ₹{self.total}"


class POSTransactionItem(models.Model):
    transaction = models.ForeignKey(
        POSTransaction, on_delete=models.CASCADE, related_name="items"
    )
    product = models.ForeignKey(Product, on_delete=models.PROTECT)
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.SET_NULL, null=True, blank=True
    )
    name = models.CharField(max_length=160)
    quantity = models.PositiveIntegerField()
    unit_price = models.DecimalField(max_digits=12, decimal_places=2)
    discount = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    tax = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    line_total = models.DecimalField(max_digits=12, decimal_places=2)


class POSPayment(models.Model):
    class Method(models.TextChoices):
        CASH = "cash"
        UPI = "upi"
        CARD = "card"
        CREDIT = "credit"

    transaction = models.ForeignKey(
        POSTransaction, on_delete=models.CASCADE, related_name="payments"
    )
    method = models.CharField(max_length=8, choices=Method.choices)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reference = models.CharField(max_length=80, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.method} ₹{self.amount}"


class POSRefund(models.Model):
    """Money returned to the customer for a return transaction."""

    transaction = models.ForeignKey(
        POSTransaction, on_delete=models.CASCADE, related_name="refunds"
    )
    method = models.CharField(max_length=8, choices=POSPayment.Method.choices)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reference = models.CharField(max_length=80, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class CashDrawer(models.Model):
    """Append-only cash movement log for a session — reconciled at day-closing."""

    class Type(models.TextChoices):
        OPENING = "opening"
        SALE = "sale"
        REFUND = "refund"
        PAY_IN = "pay_in"
        PAY_OUT = "pay_out"
        DROP = "drop"
        CLOSING = "closing"

    session = models.ForeignKey(
        POSSession, on_delete=models.CASCADE, related_name="cash_movements"
    )
    type = models.CharField(max_length=8, choices=Type.choices)
    amount = models.DecimalField(max_digits=12, decimal_places=2)  # signed
    note = models.CharField(max_length=200, blank=True)
    transaction = models.ForeignKey(
        POSTransaction, on_delete=models.SET_NULL, null=True, blank=True
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["created_at"]


class DayClosing(TimeStampedModel):
    """Cash-drawer reconciliation when a session is closed."""

    session = models.OneToOneField(
        POSSession, on_delete=models.CASCADE, related_name="day_closing"
    )
    opening_cash = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    cash_sales = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    cash_refunds = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    cash_in = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    cash_out = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    upi_sales = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    card_sales = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    credit_sales = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    expected_cash = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    counted_cash = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    variance = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    total_sales = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    transaction_count = models.PositiveIntegerField(default=0)
    notes = models.CharField(max_length=200, blank=True)
    closed_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    closed_at = models.DateTimeField(null=True, blank=True)


class HeldCart(TimeStampedModel):
    """A parked/held cart a cashier can resume later (server-side hold)."""

    session = models.ForeignKey(
        POSSession, on_delete=models.CASCADE, related_name="held_carts"
    )
    label = models.CharField(max_length=60, blank=True)
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    payload = models.JSONField(default=dict)  # {items:[{productId,variantId,qty}], ...}

    class Meta:
        ordering = ["-created_at"]
