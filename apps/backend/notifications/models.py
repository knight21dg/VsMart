from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class Notification(TimeStampedModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notifications",
    )
    type = models.CharField(max_length=40)
    title = models.CharField(max_length=160)
    body = models.TextField(blank=True)
    data = models.JSONField(null=True, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "read_at"])]


class NotificationPreference(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notification_pref",
    )
    push = models.BooleanField(default=True)
    sms = models.BooleanField(default=False)
    whatsapp = models.BooleanField(default=True)
    email = models.BooleanField(default=False)
    reminder_time = models.TimeField(null=True, blank=True)
    # Payment-reminder scheduling.
    reminder_enabled = models.BooleanField(default=True)
    reminder_offset_days = models.PositiveSmallIntegerField(default=3)
    # Free-form per-category toggle map (order/payment/credit/promo events), so the
    # client's granular notification switches persist without a column per toggle.
    categories = models.JSONField(default=dict, blank=True)
