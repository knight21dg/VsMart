from django.db import models

from core.models import TimeStampedModel


class Store(TimeStampedModel):
    """A VS Mart store (single-tenant — every store is company-owned). The store is
    the routing target for orders/deliveries/collections in a zone, and its stock is
    held in the linked inventory Warehouse (store inventory = that warehouse's stock)."""

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        INACTIVE = "inactive", "Inactive"

    code = models.CharField(max_length=40, unique=True)
    name = models.CharField(max_length=120)
    address = models.CharField(max_length=300, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    phone = models.CharField(max_length=15, blank=True)
    # GST registration for tax invoices; falls back to the company default when blank.
    gstin = models.CharField(max_length=20, blank=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ACTIVE)

    # ── Operating window & capacity (checkout gates) ─────────
    # Manual kill-switch the store admin can flip to stop taking orders right now.
    accepting_orders = models.BooleanField(default=True)
    # Business hours. Both null = always open. closes_at < opens_at = overnight window.
    opens_at = models.TimeField(null=True, blank=True)
    closes_at = models.TimeField(null=True, blank=True)
    # Max orders the store fulfils per day (null = unlimited).
    daily_order_capacity = models.PositiveIntegerField(null=True, blank=True)

    # Store inventory lives in this warehouse. One warehouse ↔ one store (the store's
    # stock-on-hand is the StockItem rows for this warehouse).
    warehouse = models.OneToOneField(
        "inventory.Warehouse",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="store",
    )

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.code})"

    @property
    def is_serviceable(self) -> bool:
        return self.status == self.Status.ACTIVE

    def is_open_now(self, now=None) -> bool:
        """Whether the store is accepting orders right now: active + not manually
        paused + within business hours (always-open when no hours are set)."""
        if self.status != self.Status.ACTIVE or not self.accepting_orders:
            return False
        if self.opens_at is None or self.closes_at is None:
            return True
        from django.utils import timezone

        t = (now or timezone.localtime()).time()
        if self.opens_at <= self.closes_at:
            return self.opens_at <= t <= self.closes_at
        # Overnight window (e.g. 22:00 → 06:00).
        return t >= self.opens_at or t <= self.closes_at

    def orders_today(self) -> int:
        """Live (non-cancelled) orders routed to this store today."""
        from django.utils import timezone

        from orders.models import Order

        return (
            Order.objects.filter(store=self, placed_at__date=timezone.localdate())
            .exclude(status__in=["cancelled", "rejected"])
            .count()
        )

    def capacity_reached(self) -> bool:
        """True once today's order count hits the store's daily capacity (if set)."""
        cap = self.daily_order_capacity
        return cap is not None and self.orders_today() >= cap


class StoreProduct(TimeStampedModel):
    """A store's catalog entry for a product — the store-centric model: per-store
    availability + selling price. An ABSENT row means the product falls back to the
    global ``Product.price``/``mrp`` and (when mapping is enforced via the
    ``zone_store_visibility`` flag) is not carried by the store. A NULL price field
    also falls back to the global product value. Per-store reorder level is kept on
    the inventory ``StockItem.low_stock_threshold`` (single source of truth)."""

    store = models.ForeignKey(
        Store, on_delete=models.CASCADE, related_name="store_products"
    )
    product = models.ForeignKey(
        "catalog.Product", on_delete=models.CASCADE, related_name="store_entries"
    )
    is_available = models.BooleanField(default=True)
    selling_price = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    mrp = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    # Per-store DISPLAY overrides. A store may re-badge a shared catalog product for
    # its own storefront/POS (different name, brand, description, photo) without
    # touching the global product or any other store. Blank/NULL = fall back to the
    # global ``Product`` value.
    name = models.CharField(max_length=160, blank=True)
    brand = models.CharField(max_length=80, blank=True)
    description = models.TextField(blank=True)
    image_url = models.URLField(blank=True, null=True)

    class Meta:
        unique_together = ("store", "product")
        ordering = ["product__name"]
        indexes = [models.Index(fields=["store", "is_available"])]

    def __str__(self):
        return f"{self.store.code} · {self.product_id}"
