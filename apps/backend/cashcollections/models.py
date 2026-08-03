"""Collections reuses payments.CashCollection as the recovery task; this app adds
the production workflow entities on top: OTP (with lockout), attempts, receipts,
and an append-only assignment history."""
from django.conf import settings
from django.db import models

from core.models import TimeStampedModel
from payments.models import CashCollection


class CollectionOTP(TimeStampedModel):
    """Customer-facing OTP authorising the cash handover. 3-attempt lockout."""

    MAX_ATTEMPTS = 3

    collection = models.OneToOneField(
        CashCollection, on_delete=models.CASCADE, related_name="collection_otp")
    code = models.CharField(max_length=6)
    # The exact amount this OTP authorises — the customer confirms THIS amount
    # before sharing the code, so collect() can never settle a different figure.
    amount = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)
    verified = models.BooleanField(default=False)
    verified_at = models.DateTimeField(null=True, blank=True)
    locked = models.BooleanField(default=False)
    generated_at = models.DateTimeField(null=True, blank=True)


class CollectionAttempt(TimeStampedModel):
    """An attempt outcome (failed / disputed / partial / collected) with reason."""

    collection = models.ForeignKey(
        CashCollection, on_delete=models.CASCADE, related_name="attempts")
    attempt_no = models.PositiveSmallIntegerField(default=1)
    outcome = models.CharField(max_length=20)  # collected|partial|failed|disputed
    reason_code = models.CharField(max_length=40, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    note = models.TextField(blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+")


class CollectionReceipt(TimeStampedModel):
    """A receipt for cash collected (full or partial), linked to the credit payment."""

    collection = models.ForeignKey(
        CashCollection, on_delete=models.CASCADE, related_name="receipts")
    payment = models.ForeignKey(
        "payments.Payment", on_delete=models.SET_NULL, null=True, blank=True)
    receipt_no = models.CharField(max_length=24, unique=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    mode = models.CharField(max_length=12, default="cash")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+")
    issued_at = models.DateTimeField(null=True, blank=True)

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.receipt_no:
            type(self).objects.filter(pk=self.pk).update(receipt_no=f"RCPT{1000 + self.pk}")
            self.receipt_no = f"RCPT{1000 + self.pk}"


class CollectionAssignmentHistory(TimeStampedModel):
    """Append-only record of every assignment decision for a collection."""

    class Action(models.TextChoices):
        AUTO_ASSIGNED = "auto_assigned"
        MANUAL_ASSIGNED = "manual_assigned"
        REASSIGNED = "reassigned"
        ACCEPTED = "accepted"
        REJECTED = "rejected"

    collection = models.ForeignKey(
        CashCollection, on_delete=models.CASCADE, related_name="assignments")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name="+")
    action = models.CharField(max_length=20, choices=Action.choices)
    reason = models.CharField(max_length=200, blank=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+")
