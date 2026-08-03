from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class Zone(TimeStampedModel):
    """A serviceable delivery area. Primary geometry is a GeoJSON polygon
    (``polygon_geojson``) resolved by the serviceability engine; the legacy
    circle (center + radius_km) / pincode list remain as a fallback during
    migration. Each zone is assigned to one Store, which becomes the routing
    target for orders/deliveries in that zone."""

    name = models.CharField(max_length=80)
    code = models.CharField(max_length=40, unique=True, null=True, blank=True)

    # ── Geometry ─────────────────────────────────────────
    # Authoritative: a GeoJSON Polygon/MultiPolygon (coords are [lng, lat]).
    polygon_geojson = models.JSONField(null=True, blank=True)
    # Legacy fallback (radius circle + pincodes).
    center_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    center_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    radius_km = models.DecimalField(max_digits=6, decimal_places=2, default=5)
    pincodes = models.JSONField(default=list, blank=True)

    # ── Assignment & policy ──────────────────────────────
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="zones",
    )
    is_active = models.BooleanField(default=True)
    credit_enabled = models.BooleanField(default=True)
    estimated_delivery_minutes = models.PositiveIntegerField(default=30)
    # Higher priority wins when a point falls inside overlapping zones.
    priority = models.IntegerField(default=0)

    # Per-zone fee overrides — null means fall back to PlatformConfig.
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    free_delivery_threshold = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    min_order = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)
    platform_fee_value = models.DecimalField(max_digits=10, decimal_places=2, null=True, blank=True)

    # Per-zone loyalty earn rate: points granted per ₹100 of a delivered order.
    # Null falls back to PlatformConfig, exactly like the fee overrides above — so a
    # zone only carries a value when it is deliberately running a different rate
    # (a launch promo in a new area, say).
    loyalty_points_per_100 = models.PositiveIntegerField(null=True, blank=True)

    class Meta:
        ordering = ["-priority", "name"]

    def __str__(self):
        return self.name


class ExpansionRequest(TimeStampedModel):
    """A request from a customer outside all serviceable polygons — captured so the
    business can prioritise where to expand next (spec §EXPANSION REQUEST ENTITY)."""

    name = models.CharField(max_length=120, blank=True)
    mobile = models.CharField(max_length=15, blank=True)
    village = models.CharField(max_length=120, blank=True)
    area = models.CharField(max_length=120, blank=True)
    pincode = models.CharField(max_length=6, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="expansion_requests",
    )

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.area or self.village or self.pincode} ({self.mobile})"


class ZoneAgent(models.Model):
    zone = models.ForeignKey(Zone, on_delete=models.CASCADE, related_name="agents")
    agent = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="zones"
    )

    class Meta:
        unique_together = ("zone", "agent")


class ZoneEvent(TimeStampedModel):
    """Append-only event log for the zone/serviceability domain (spec §EVENT DRIVEN
    ARCHITECTURE): zone_created/updated/activated/deactivated, store_assigned,
    order_routed, agent_assigned, etc. Consumed by analytics/reporting."""

    type = models.CharField(max_length=40)
    zone = models.ForeignKey(
        Zone, on_delete=models.SET_NULL, null=True, blank=True, related_name="events"
    )
    payload = models.JSONField(default=dict, blank=True)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["type", "created_at"])]

    def __str__(self):
        return f"{self.type} @ {self.created_at:%Y-%m-%d %H:%M}"
