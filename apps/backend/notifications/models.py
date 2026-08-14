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

    #: Identity of the *event*, not of this row: "<event>:<reference>", e.g.
    #: ``delivery_assigned:task:412`` or ``order_status:VSORD1007:delivered``.
    #:
    #: Nothing deduplicated notifications before, so every retry of an operation
    #: minted a fresh inbox row and a fresh device push: an agent re-notified
    #: "New delivery assigned" each time dispatch touched their task, a customer
    #: re-notified for a status they had already been told about. When a key is
    #: supplied, `notify()` becomes get-or-create and a repeat sends nothing.
    #:
    #: Blank means "not deduplicated" — a genuinely repeatable message (a
    #: marketing blast, a re-sent OTP) must still be able to arrive twice, which
    #: is why the constraint below is partial rather than covering every row.
    dedupe_key = models.CharField(max_length=140, blank=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["user", "read_at"])]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "dedupe_key"],
                condition=~models.Q(dedupe_key=""),
                name="uniq_notification_user_dedupe_key",
            )
        ]


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
