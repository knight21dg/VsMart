from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class VerificationTask(TimeStampedModel):
    class Type(models.TextChoices):
        KYC = "kyc"
        RESIDENCE = "residence"
        CREDIT = "credit"

    class Status(models.TextChoices):
        PENDING = "pending"
        ASSIGNED = "assigned"
        IN_PROGRESS = "in_progress"
        SUBMITTED = "submitted"
        APPROVED = "approved"
        REJECTED = "rejected"

    class Recommendation(models.TextChoices):
        """The field agent's RECOMMENDATION — not the verdict. The store/admin KYC
        reviewer still makes the final approve/reject decision; the agent only
        reports what they found in the field."""

        APPROVE = "approve"
        REJECT = "reject"
        INCONCLUSIVE = "inconclusive"

    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="verification_tasks",
    )
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="assigned_verifications",
    )
    # The KYC application this field visit backs, so the agent's findings flow back
    # to the reviewer instead of dead-ending. NULL for standalone/legacy tasks.
    kyc_application = models.ForeignKey(
        "kyc.KycApplication",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="field_verifications",
    )
    type = models.CharField(max_length=12, choices=Type.choices, default=Type.KYC)
    status = models.CharField(
        max_length=12, choices=Status.choices, default=Status.PENDING
    )
    recommendation = models.CharField(
        max_length=12, choices=Recommendation.choices, blank=True
    )
    note = models.CharField(max_length=200, blank=True)
    submitted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]


class VerificationEvidence(TimeStampedModel):
    class Kind(models.TextChoices):
        PHOTO = "photo"
        GPS = "gps"
        DOCUMENT = "document"

    task = models.ForeignKey(
        VerificationTask, on_delete=models.CASCADE, related_name="evidence"
    )
    kind = models.CharField(max_length=12, choices=Kind.choices, default=Kind.PHOTO)
    photo_key = models.CharField(max_length=200, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True
    )
