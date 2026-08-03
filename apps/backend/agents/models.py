from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class AgentIncentive(TimeStampedModel):
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="incentives",
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    reason = models.CharField(max_length=200)
    period = models.CharField(max_length=40, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Incentive {self.amount} for {self.agent_id}"


class AgentAttendance(TimeStampedModel):
    """One row per agent per day — check-in/out times drive on-duty status for the
    Live Operations feed (spec: agent attendance, M16)."""

    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="attendances"
    )
    date = models.DateField()
    check_in_at = models.DateTimeField(null=True, blank=True)
    check_out_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ("agent", "date")
        ordering = ["-date"]

    def __str__(self):
        return f"Attendance {self.agent_id} {self.date}"

    @property
    def on_duty(self) -> bool:
        return self.check_in_at is not None and self.check_out_at is None
