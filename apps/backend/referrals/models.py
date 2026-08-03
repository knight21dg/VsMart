from decimal import Decimal

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel

DEFAULT_REWARD = Decimal("100")


class Referral(TimeStampedModel):
    class Status(models.TextChoices):
        PENDING = "pending"
        COMPLETED = "completed"
        EXPIRED = "expired"

    referrer = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="referrals_made",
    )
    referee = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="referred_by",
    )
    code = models.CharField(max_length=20, unique=True)
    reward = models.DecimalField(max_digits=12, decimal_places=2, default=DEFAULT_REWARD)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING
    )

    def __str__(self):
        return f"Referral({self.code}) {self.referrer_id}->{self.referee_id}"
