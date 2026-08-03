from django.conf import settings
from django.db import models

from catalog.models import Product


class AnalyticsEvent(models.Model):
    """Lightweight append-only event stream — the seam for realtime push + analytics.
    Apps/POS poll `/pos/events?since=<id>` until a websocket transport is added."""

    class Type(models.TextChoices):
        STOCK_MOVED = "stock_moved"
        LOW_STOCK = "low_stock"
        SALE_COMPLETED = "sale_completed"
        DAY_CLOSED = "day_closed"

    type = models.CharField(max_length=20, choices=Type.choices, db_index=True)
    payload = models.JSONField(default=dict)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-id"]
        indexes = [models.Index(fields=["type", "id"])]


class StockAdjustment(models.Model):
    """Audit trail for every inventory change made from the admin panel."""

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="adjustments"
    )
    delta = models.IntegerField()  # signed change applied
    new_count = models.IntegerField()
    reason = models.CharField(max_length=200, blank=True)
    by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True
    )
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at"]
