from decimal import Decimal

from django.conf import settings
from django.db import models
from django.db.models import Q

from core.models import TimeStampedModel


class Payment(TimeStampedModel):
    class Purpose(models.TextChoices):
        ORDER = "order"
        REPAYMENT = "repayment"
        REFUND = "refund"
        # An agent sending collected cash to their store digitally. Distinct from
        # REPAYMENT: the customer's debt was already cleared when the cash was
        # collected in the field — this only moves that money agent → store.
        HANDOVER = "handover"

    class Method(models.TextChoices):
        UPI = "upi"
        CARD = "card"
        NETBANKING = "netbanking"
        CASH = "cash"

    class Gateway(models.TextChoices):
        RAZORPAY = "razorpay"
        CASHFREE = "cashfree"
        MANUAL = "manual"

    class Status(models.TextChoices):
        CREATED = "created"
        PENDING = "pending"
        SUCCESS = "success"
        FAILED = "failed"
        REFUNDED = "refunded"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="payments"
    )
    purpose = models.CharField(max_length=10, choices=Purpose.choices)
    order = models.ForeignKey(
        "orders.Order", on_delete=models.SET_NULL, null=True, blank=True
    )
    statement = models.ForeignKey(
        "credit.Statement", on_delete=models.SET_NULL, null=True, blank=True
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    method = models.CharField(max_length=12, choices=Method.choices)
    gateway = models.CharField(max_length=10, choices=Gateway.choices, default=Gateway.MANUAL)
    gateway_order_id = models.CharField(max_length=80, blank=True)
    gateway_payment_id = models.CharField(max_length=80, blank=True)
    gateway_refund_id = models.CharField(max_length=80, blank=True)
    # For a refund Payment: the original Payment being reversed (for the audit chain).
    refund_of = models.ForeignKey(
        "self", on_delete=models.SET_NULL, null=True, blank=True, related_name="refunds"
    )
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.CREATED)
    idempotency_key = models.CharField(max_length=80, blank=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            # Race-safe payment idempotency: a concurrent double-submit with the same
            # key can't create two Payment rows (→ two gateway orders → possible double
            # charge). Mirrors orders.uniq_order_idempotency. Blank keys unconstrained.
            models.UniqueConstraint(
                fields=["user", "idempotency_key"],
                condition=~Q(idempotency_key=""),
                name="uniq_payment_idempotency",
            ),
        ]

    def __str__(self):
        return f"Payment({self.id}) {self.amount} {self.status}"


class PaymentEvent(models.Model):
    """Append-only audit trail of a payment's status transitions — created →
    pending → success/failed/refunded — with the gateway reference and actor at
    each step. Gives money operations a regulator-friendly paper trail alongside
    the append-only credit ledger."""

    payment = models.ForeignKey(Payment, on_delete=models.CASCADE, related_name="events")
    status = models.CharField(max_length=10, choices=Payment.Status.choices)
    note = models.CharField(max_length=200, blank=True)
    # The gateway id relevant to this transition (payment id on success, refund id
    # on a refund, etc.) — kept here so the trail is complete even if the Payment
    # row is later updated.
    gateway_ref = models.CharField(max_length=80, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at", "id"]

    def __str__(self):
        return f"PaymentEvent(payment={self.payment_id}, {self.status})"


class PaymentWebhookEvent(models.Model):
    gateway = models.CharField(max_length=20)
    event_id = models.CharField(max_length=120, unique=True)
    signature_ok = models.BooleanField(default=False)
    payload = models.JSONField()
    processed = models.BooleanField(default=False)
    received_at = models.DateTimeField(auto_now_add=True)


class CashCollection(TimeStampedModel):
    """A field cash-recovery task. The full production lifecycle + partial
    collection + dispute live in cashcollections.services."""

    class Status(models.TextChoices):
        REQUESTED = "requested"
        ASSIGNED = "assigned"
        ACCEPTED = "accepted"
        EN_ROUTE = "en_route"
        REACHED = "reached"
        COLLECTED = "collected"
        PARTIALLY_COLLECTED = "partially_collected"
        FAILED = "failed"
        DISPUTED = "disputed"
        CANCELLED = "cancelled"

    TERMINAL = {"collected", "partially_collected", "cancelled"}

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="cash_requests"
    )
    idempotency_key = models.CharField(max_length=64, blank=True, default="")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="cash_collections",
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)  # amount to recover
    collected_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.REQUESTED, db_index=True)
    is_priority = models.BooleanField(default=False)
    escalated = models.BooleanField(default=False)
    attempt_no = models.PositiveSmallIntegerField(default=1)
    otp_verified = models.BooleanField(default=False)
    manual_verification_required = models.BooleanField(default=False)
    failure_reason = models.CharField(max_length=40, blank=True)
    dispute_note = models.CharField(max_length=300, blank=True)
    statement = models.ForeignKey(
        "credit.Statement", on_delete=models.SET_NULL, null=True, blank=True
    )
    payment = models.ForeignKey(
        Payment, on_delete=models.SET_NULL, null=True, blank=True
    )
    # Which cash hand-over this collection was banked in. NULL = the agent is
    # still holding the money. This is what makes "collected but not yet
    # deposited" a queryable number instead of an unknown.
    deposit = models.ForeignKey(
        "payments.CashDeposit", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="collections",
    )
    # True when the customer paid the STORE directly (counter cash, UPI to the
    # store) rather than handing notes to a field agent. That money is already
    # at the store, so it must never count toward anyone's cash-in-hand — the
    # figure that means "physical notes someone still owes a hand-over for".
    collected_at_store = models.BooleanField(default=False)
    assigned_at = models.DateTimeField(null=True, blank=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    en_route_at = models.DateTimeField(null=True, blank=True)
    reached_at = models.DateTimeField(null=True, blank=True)
    failed_at = models.DateTimeField(null=True, blank=True)
    collected_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            # Race-safe pickup-request idempotency: a timed-out retry sending the
            # same Idempotency-Key can't create two cash-collection tasks. Mirrors
            # payments.uniq_payment_idempotency. Blank keys unconstrained (legacy).
            models.UniqueConstraint(
                fields=["user", "idempotency_key"],
                condition=~Q(idempotency_key=""),
                name="uniq_cashcollection_idempotency",
            ),
        ]

    @property
    def remaining(self):
        # `.objects.create(amount=<raw request value>)` doesn't coerce field
        # values on the in-memory instance (only on the SQL write) — a caller
        # that reads `.remaining` before a DB round-trip can still be holding
        # a raw str/int here. Decimal(str(x)) is a no-op for an already-Decimal
        # value and safe for the common numeric-ish types that reach this.
        amount = self.amount if isinstance(self.amount, Decimal) else Decimal(str(self.amount))
        collected = (
            self.collected_amount if isinstance(self.collected_amount, Decimal)
            else Decimal(str(self.collected_amount))
        )
        return max(amount - collected, Decimal("0"))


class CashDeposit(TimeStampedModel):
    """An agent handing collected cash over to the business (bank or office).

    This is the missing link in the cash chain. Field agents collected cash and
    the credit ledger was repaid, but nothing recorded what happened to the
    physical notes — there was no deposit record, so "collected" and "banked"
    could drift apart indefinitely with no way to see it. Every collection now
    belongs to exactly one deposit or to none (still in the agent's hands).

    `amount` is the agent's declared figure; `verified_amount` is what finance
    actually counted. A shortfall is a real, visible number rather than a
    silent difference.
    """

    class Method(models.TextChoices):
        BANK = "bank"          # paid into the bank account
        OFFICE = "office"      # handed to the store/office cash box
        UPI = "upi"            # transferred digitally

    class Status(models.TextChoices):
        # INITIATED is online-only: the agent raised a Razorpay hand-over link
        # and the money hasn't landed yet. The chosen collections are already
        # reserved onto this deposit so they leave "cash in hand", but nothing
        # is booked until the gateway confirms.
        INITIATED = "initiated"  # online link raised, awaiting the gateway
        PENDING = "pending"      # declared by the agent, not yet counted
        VERIFIED = "verified"    # counted / gateway-confirmed and matched
        SHORT = "short"          # counted, less than declared
        REJECTED = "rejected"    # not accepted (e.g. never arrived)
        CANCELLED = "cancelled"  # online link expired/cancelled; reservation freed

    #: Statuses that represent a real, standing hand-over of money. INITIATED and
    #: CANCELLED are excluded because no money has (respectively yet / ever)
    #: moved — reconciliation must not count them as declared.
    LIVE_STATUSES = (Status.PENDING, Status.VERIFIED, Status.SHORT)

    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT,
        related_name="cash_deposits",
    )
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="cash_deposits",
    )
    # Declared by the agent when handing the money over.
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    method = models.CharField(max_length=8, choices=Method.choices,
                              default=Method.BANK)
    deposited_on = models.DateField()
    reference = models.CharField(max_length=80, blank=True)  # slip / UTR / gateway id
    slip_key = models.CharField(max_length=200, blank=True)  # deposit-slip image
    # The Razorpay payment that funded an ONLINE hand-over. Null for physical
    # cash. This is what ties a digital deposit back to a verifiable gateway
    # transaction instead of a self-declared reference.
    payment = models.ForeignKey(
        "payments.Payment", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="funded_deposits",
    )

    status = models.CharField(max_length=10, choices=Status.choices,
                              default=Status.PENDING, db_index=True)
    # What finance actually counted. Null until verified.
    verified_amount = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    verified_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="cash_deposits_verified",
    )
    verified_at = models.DateTimeField(null=True, blank=True)
    notes = models.CharField(max_length=300, blank=True)

    class Meta:
        ordering = ["-deposited_on", "-id"]
        indexes = [models.Index(fields=["status", "deposited_on"])]

    @property
    def shortfall(self):
        """Declared minus counted. Zero while unverified — an uncounted deposit
        is not yet a shortfall."""
        if self.verified_amount is None:
            return Decimal("0.00")
        return max(self.amount - self.verified_amount, Decimal("0.00"))

    def __str__(self):
        return f"CashDeposit({self.agent_id}) {self.amount} {self.status}"
