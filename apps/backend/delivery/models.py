"""Delivery Operations data model — the controlled state machine + every entity
the production workflow needs: tasks, assignment history, location log, delivery
OTP, attempts, proof-of-delivery evidence, earnings and ratings.

Source of truth for an order's last-mile. Live agent coordinates are mirrored
onto orders.OrderTracking so the customer app's tracking endpoint stays in sync.
"""
from django.conf import settings
from django.db import models

from core.models import TimeStampedModel
from orders.models import Order


class DeliveryTask(TimeStampedModel):
    """One last-mile task per order assignment. A reassignment closes the prior
    task (status=reassigned) and opens a new one, so history is preserved."""

    class Status(models.TextChoices):
        ASSIGNED = "assigned"
        ACCEPTED = "accepted"
        REJECTED = "rejected"
        PICKED_UP = "picked_up"
        OUT_FOR_DELIVERY = "out_for_delivery"
        REACHED = "reached"
        DELIVERED = "delivered"
        FAILED = "failed"
        RESCHEDULED = "rescheduled"
        RETURN_INITIATED = "return_initiated"
        RETURNED_TO_STORE = "returned_to_store"
        REASSIGNED = "reassigned"
        CANCELLED = "cancelled"

    #: States the ORDER is finished in — nothing further will happen to this task.
    TERMINAL = {"delivered", "rejected", "returned_to_store", "reassigned", "cancelled"}

    #: States that have left the AGENT's hands. Terminal work, plus `failed`:
    #: a failed attempt is over as far as the agent is concerned (only the store
    #: can reschedule, reassign or return it), so it belongs in their history, not
    #: on their active list.
    #:
    #: These two sets are separate because three call sites each had their own
    #: idea of "done" and disagreed: the agent's queue excluded only TERMINAL, the
    #: assignment engine excluded `TERMINAL | {failed}`, and history included only
    #: TERMINAL. A failed delivery therefore sat on the agent's screen forever
    #: while appearing in no history at all — dead work they could not clear, and
    #: no record that they had attempted it. Anything asking "is this still the
    #: agent's problem?" must use CLOSED_FOR_AGENT.
    CLOSED_FOR_AGENT = TERMINAL | {"failed"}

    order = models.ForeignKey(
        Order, on_delete=models.CASCADE, related_name="delivery_tasks"
    )
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="delivery_tasks",
    )
    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.ASSIGNED, db_index=True
    )
    attempt_no = models.PositiveSmallIntegerField(default=1)

    # Routing / geofence.
    dest_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    dest_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    distance_km = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True)
    priority_score = models.DecimalField(max_digits=9, decimal_places=2, null=True, blank=True)

    # Batch this task belongs to (null = legacy single-task path; both coexist).
    batch = models.ForeignKey(
        "delivery.DeliveryBatch", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="tasks",
    )

    # Security gates.
    otp_verified = models.BooleanField(default=False)
    manual_verification_required = models.BooleanField(default=False)
    photo_key = models.CharField(max_length=200, blank=True)  # latest POD evidence key

    # Failure.
    failure_reason = models.CharField(max_length=40, blank=True)
    failure_note = models.TextField(blank=True)
    note = models.TextField(blank=True)

    # Timeline timestamps.
    assigned_at = models.DateTimeField(null=True, blank=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    picked_up_at = models.DateTimeField(null=True, blank=True)
    out_for_delivery_at = models.DateTimeField(null=True, blank=True)
    reached_at = models.DateTimeField(null=True, blank=True)
    delivered_at = models.DateTimeField(null=True, blank=True)
    failed_at = models.DateTimeField(null=True, blank=True)
    # legacy (kept for migration safety; new flow uses out_for_delivery_at + DeliveryOTP)
    started_at = models.DateTimeField(null=True, blank=True)
    otp = models.CharField(max_length=6, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["agent", "status"])]

    @property
    def is_terminal(self) -> bool:
        return self.status in self.TERMINAL

    @property
    def is_active(self) -> bool:
        return not self.is_terminal


class DeliveryBatch(TimeStampedModel):
    """A planned multi-stop trip for one agent — the unit the assignment engine
    produces. Holds an ordered set of BatchStops (deliveries + on-route
    collections), the optimized route geometry, and a live status. Single, unbatched
    DeliveryTasks still work (batch is nullable), so this is additive."""

    class Status(models.TextChoices):
        QUEUED = "queued"          # planned, not yet offered to an agent
        ASSIGNED = "assigned"      # offered to an agent, awaiting accept
        ACCEPTED = "accepted"      # agent accepted, heading to pickup
        PICKED_UP = "picked_up"    # bags handed over at store
        IN_PROGRESS = "in_progress"
        COMPLETED = "completed"
        FAILED = "failed"
        CANCELLED = "cancelled"

    TERMINAL = {"completed", "failed", "cancelled"}

    store = models.ForeignKey(
        "stores.Store", on_delete=models.CASCADE, related_name="delivery_batches"
    )
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="delivery_batches",
    )
    status = models.CharField(
        max_length=15, choices=Status.choices, default=Status.QUEUED, db_index=True
    )
    # Planning outputs.
    total_distance_km = models.DecimalField(max_digits=7, decimal_places=2, default=0)
    estimated_duration_secs = models.PositiveIntegerField(default=0)
    encoded_polyline = models.TextField(blank=True)   # route geometry for the map
    score = models.DecimalField(max_digits=9, decimal_places=2, null=True, blank=True)
    priority = models.CharField(max_length=12, blank=True)  # express|perishable|...
    # Pickup handoff.
    pickup_code = models.CharField(max_length=6, blank=True)  # store↔agent OTP
    # Timeline.
    assigned_at = models.DateTimeField(null=True, blank=True)
    accepted_at = models.DateTimeField(null=True, blank=True)
    picked_up_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["store", "status"]), models.Index(fields=["agent", "status"])]

    @property
    def is_terminal(self) -> bool:
        return self.status in self.TERMINAL


class BatchStop(TimeStampedModel):
    """One stop on a batch route — either a delivery (order) or a cash collection.
    `sequence` is the optimized visit order."""

    class Kind(models.TextChoices):
        DELIVERY = "delivery"
        COLLECTION = "collection"

    class Status(models.TextChoices):
        PENDING = "pending"
        REACHED = "reached"
        DONE = "done"
        FAILED = "failed"
        SKIPPED = "skipped"

    batch = models.ForeignKey(DeliveryBatch, on_delete=models.CASCADE, related_name="stops")
    sequence = models.PositiveSmallIntegerField(default=0)
    kind = models.CharField(max_length=12, choices=Kind.choices)
    # Exactly one of these is set depending on kind.
    task = models.ForeignKey(
        DeliveryTask, on_delete=models.SET_NULL, null=True, blank=True, related_name="batch_stops"
    )
    collection = models.ForeignKey(
        "payments.CashCollection", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="batch_stops",
    )
    label = models.CharField(max_length=160, blank=True)   # customer/area for display
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING)
    eta_secs = models.PositiveIntegerField(default=0)      # cumulative ETA from start
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)  # collect amt
    done_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["batch", "sequence"]


class DeliveryAssignmentHistory(TimeStampedModel):
    """Append-only record of every assignment decision for a task."""

    class Action(models.TextChoices):
        AUTO_ASSIGNED = "auto_assigned"
        MANUAL_ASSIGNED = "manual_assigned"
        REASSIGNED = "reassigned"
        ACCEPTED = "accepted"
        REJECTED = "rejected"

    task = models.ForeignKey(DeliveryTask, on_delete=models.CASCADE, related_name="assignments")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+"
    )
    action = models.CharField(max_length=20, choices=Action.choices)
    score = models.DecimalField(max_digits=9, decimal_places=2, null=True, blank=True)
    reason = models.CharField(max_length=200, blank=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )


class DeliveryLocation(models.Model):
    """Agent GPS ping (every ~15s while out for delivery)."""

    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="locations"
    )
    task = models.ForeignKey(
        DeliveryTask, on_delete=models.CASCADE, null=True, blank=True, related_name="locations"
    )
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    accuracy_m = models.DecimalField(max_digits=7, decimal_places=2, null=True, blank=True)
    at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-at"]


class DeliveryOTP(TimeStampedModel):
    """Customer-facing delivery OTP with attempt lockout. One per task."""

    MAX_ATTEMPTS = 3

    task = models.OneToOneField(DeliveryTask, on_delete=models.CASCADE, related_name="delivery_otp")
    code = models.CharField(max_length=6)
    attempts = models.PositiveSmallIntegerField(default=0)
    verified = models.BooleanField(default=False)
    verified_at = models.DateTimeField(null=True, blank=True)
    locked = models.BooleanField(default=False)
    generated_at = models.DateTimeField(null=True, blank=True)


class DeliveryAttempt(TimeStampedModel):
    """A delivery attempt outcome (failed / rescheduled), with reason + evidence."""

    task = models.ForeignKey(DeliveryTask, on_delete=models.CASCADE, related_name="attempts")
    attempt_no = models.PositiveSmallIntegerField(default=1)
    outcome = models.CharField(max_length=20)  # failed | rescheduled | returned
    reason_code = models.CharField(max_length=40, blank=True)
    note = models.TextField(blank=True)
    photo_key = models.CharField(max_length=200, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+"
    )


class DeliveryEvidence(TimeStampedModel):
    """Proof-of-delivery media (mandatory). Stores the file key + GPS metadata."""

    class Kind(models.TextChoices):
        PHOTO = "photo"
        SIGNATURE = "signature"

    task = models.ForeignKey(DeliveryTask, on_delete=models.CASCADE, related_name="evidence")
    kind = models.CharField(max_length=12, choices=Kind.choices, default=Kind.PHOTO)
    file_key = models.CharField(max_length=200)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    captured_at = models.DateTimeField(null=True, blank=True)
    meta = models.JSONField(default=dict, blank=True)


class DeliveryEarnings(TimeStampedModel):
    """Agent payout for a completed task (base + distance + heavy + peak bonuses)."""

    task = models.OneToOneField(DeliveryTask, on_delete=models.CASCADE, related_name="earnings")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="delivery_earnings"
    )
    base = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    distance_bonus = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    heavy_bonus = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    peak_bonus = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    total = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    released = models.BooleanField(default=False)
    released_at = models.DateTimeField(null=True, blank=True)


class DeliveryRating(TimeStampedModel):
    """Customer feedback request raised on completion; filled when the customer rates."""

    task = models.OneToOneField(DeliveryTask, on_delete=models.CASCADE, related_name="rating")
    order = models.ForeignKey(Order, on_delete=models.CASCADE, related_name="delivery_ratings")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="delivery_ratings"
    )
    rating = models.PositiveSmallIntegerField(null=True, blank=True)  # 1..5
    feedback = models.CharField(max_length=300, blank=True)
    requested_at = models.DateTimeField(null=True, blank=True)
    rated_at = models.DateTimeField(null=True, blank=True)
