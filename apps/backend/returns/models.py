from decimal import Decimal

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel

ZERO = Decimal("0.00")


class ReturnStatus(models.TextChoices):
    REQUESTED = "requested"
    APPROVED = "approved"
    REJECTED = "rejected"
    PICKED = "picked"
    REFUNDED = "refunded"


class ReturnRequest(TimeStampedModel):
    code = models.CharField(max_length=20, unique=True, blank=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="returns"
    )
    order = models.ForeignKey(
        "orders.Order", on_delete=models.PROTECT, related_name="returns"
    )
    reason = models.CharField(max_length=160)
    description = models.TextField(blank=True)
    status = models.CharField(
        max_length=20, choices=ReturnStatus.choices, default=ReturnStatus.REQUESTED
    )
    refund_amount = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    resolved_at = models.DateTimeField(null=True, blank=True)
    # Reviewer's note + actor captured when a return is approved/rejected/refunded.
    decision_note = models.TextField(blank=True, default="")
    decided_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="+",
    )

    class Meta:
        ordering = ["-created_at"]

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.code:
            self.code = f"RET{1000 + self.pk}"
            super().save(update_fields=["code"])

    def __str__(self):
        return self.code or f"ReturnRequest #{self.pk}"


class ReturnItem(TimeStampedModel):
    return_request = models.ForeignKey(
        ReturnRequest, on_delete=models.CASCADE, related_name="items"
    )
    product_name = models.CharField(max_length=160)
    quantity = models.PositiveIntegerField()
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    # Set by the field agent at the door when only part of a line is actually
    # returnable. NULL = not yet inspected; the requested quantity/amount stands.
    accepted_quantity = models.PositiveIntegerField(null=True, blank=True)
    accepted_amount = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )

    @property
    def settled_quantity(self) -> int:
        """Units the refund is actually computed on."""
        return self.quantity if self.accepted_quantity is None else self.accepted_quantity

    @property
    def settled_amount(self):
        return self.amount if self.accepted_amount is None else self.accepted_amount


class ReturnPickupTask(TimeStampedModel):
    """A field-agent doorstep visit to inspect and collect a return.

    Created (and auto-assigned) the moment a customer submits a return, so a
    return never sits waiting on a human to dispatch it. Mirrors
    delivery.DeliveryTask: a reassignment closes the prior task
    (status=reassigned) and opens a new one, preserving history.
    """

    class Status(models.TextChoices):
        ASSIGNED = "assigned"
        ACCEPTED = "accepted"          # agent took the job
        EN_ROUTE = "en_route"
        REACHED = "reached"
        COMPLETED = "completed"        # inspected OK, goods collected
        REJECTED = "rejected"          # inspected, refused at the door
        RESCHEDULED = "rescheduled"    # deferred — still open for a reattempt
        REASSIGNED = "reassigned"
        CANCELLED = "cancelled"

    # `rescheduled` is deliberately NOT terminal — the task stays on the agent's
    # list and is reattempted.
    TERMINAL = {"completed", "rejected", "reassigned", "cancelled"}

    class ReasonCode(models.TextChoices):
        ITEM_USED = "item_used"
        ITEM_DAMAGED_BY_CUSTOMER = "item_damaged_by_customer"
        WRONG_ITEM = "wrong_item"
        QUANTITY_MISMATCH = "quantity_mismatch"
        PACKAGING_MISSING = "packaging_missing"
        CUSTOMER_UNAVAILABLE = "customer_unavailable"
        CUSTOMER_CANCELLED = "customer_cancelled"
        OTHER = "other"

    return_request = models.ForeignKey(
        ReturnRequest, on_delete=models.CASCADE, related_name="pickup_tasks"
    )
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="return_pickup_tasks",
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ASSIGNED, db_index=True
    )
    attempt_no = models.PositiveSmallIntegerField(default=1)

    # Where the agent is going (copied off the order's delivery address).
    dest_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    dest_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    reason_code = models.CharField(
        max_length=40, choices=ReasonCode.choices, blank=True
    )
    note = models.TextField(blank=True)
    reschedule_at = models.DateTimeField(null=True, blank=True)

    # Timeline.
    assigned_at = models.DateTimeField(null=True, blank=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    en_route_at = models.DateTimeField(null=True, blank=True)
    reached_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["agent", "status"])]

    @property
    def is_terminal(self) -> bool:
        return self.status in self.TERMINAL

    def __str__(self):
        return f"Pickup {self.return_request_id} → {self.agent_id or 'unassigned'}"


class ReturnEvidence(TimeStampedModel):
    """Photos backing a return — the customer's proof at submission time and the
    agent's proof of the item's real condition at the door. `file_key` is a
    private mediastore MediaAsset UUID."""

    class Source(models.TextChoices):
        CUSTOMER = "customer"
        AGENT = "agent"

    return_request = models.ForeignKey(
        ReturnRequest, on_delete=models.CASCADE, related_name="evidence"
    )
    task = models.ForeignKey(
        ReturnPickupTask, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="evidence",
    )
    source = models.CharField(
        max_length=12, choices=Source.choices, default=Source.CUSTOMER
    )
    file_key = models.CharField(max_length=200)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    captured_at = models.DateTimeField(null=True, blank=True)
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )
    meta = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["created_at"]


class ReturnAssignmentHistory(TimeStampedModel):
    """Append-only record of every assignment decision for a pickup task."""

    class Action(models.TextChoices):
        AUTO_ASSIGNED = "auto_assigned"
        MANUAL_ASSIGNED = "manual_assigned"
        REASSIGNED = "reassigned"
        ACCEPTED = "accepted"
        REJECTED = "rejected"
        RESCHEDULED = "rescheduled"

    task = models.ForeignKey(
        ReturnPickupTask, on_delete=models.CASCADE, related_name="assignments"
    )
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+"
    )
    action = models.CharField(max_length=20, choices=Action.choices)
    reason = models.CharField(max_length=200, blank=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )
