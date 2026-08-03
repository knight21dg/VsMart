from django.conf import settings
from django.db import models


class PointsLedgerEntry(models.Model):
    """Append-only reward-points ledger. Never UPDATE/DELETE — corrections are
    new `adjust` rows. Mirrors credit.CreditLedgerEntry."""

    class Type(models.TextChoices):
        EARN = "earn"        # + points
        REDEEM = "redeem"    # - points
        ADJUST = "adjust"    # signed
        EXPIRE = "expire"    # - points

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.PROTECT,
        related_name="points_entries",
    )
    type = models.CharField(max_length=8, choices=Type.choices)
    points = models.IntegerField()  # signed: earn +, redeem -
    balance_after = models.IntegerField()
    note = models.CharField(max_length=200, blank=True)
    ref_type = models.CharField(max_length=40, blank=True)
    ref_id = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "created_at"])]

    def save(self, *args, **kwargs):
        # Append-only: rows are immutable; corrections are new `adjust` rows.
        if not self._state.adding:
            raise ValueError("PointsLedgerEntry is append-only and cannot be modified.")
        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise ValueError("PointsLedgerEntry is append-only and cannot be deleted.")

    def __str__(self):
        return f"Points({self.user_id}) {self.type} {self.points} -> {self.balance_after}"
