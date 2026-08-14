from decimal import Decimal

from django.conf import settings
from django.db import models


class PlatformConfig(models.Model):
    """Singleton (pk=1) holding every runtime money/platform knob the superadmin
    controls. Replaces the old env constants in pricing. `load()` returns the row,
    seeding defaults from settings on first use."""

    class FeeType(models.TextChoices):
        PERCENT = "percent", "Percent of order"
        FLAT = "flat", "Flat amount"

    # Taxes & delivery
    gst_rate = models.DecimalField(max_digits=5, decimal_places=4, default=Decimal("0.18"))
    delivery_fee = models.DecimalField(max_digits=10, decimal_places=2, default=45)
    free_delivery_threshold = models.DecimalField(max_digits=10, decimal_places=2, default=499)
    min_order = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    # Platform / commission fee
    platform_fee_type = models.CharField(
        max_length=8, choices=FeeType.choices, default=FeeType.FLAT
    )
    platform_fee_value = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    platform_fee_cap = models.DecimalField(
        max_digits=10, decimal_places=2, null=True, blank=True
    )

    # Credit
    credit_default_limit = models.DecimalField(max_digits=12, decimal_places=2, default=10000)
    late_fee_flat = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    late_fee_percent = models.DecimalField(max_digits=5, decimal_places=2, default=0)

    # Smallest cash amount a field agent may collect on a visit. Zero and
    # negative amounts were already refused, but there was no way to say "don't
    # send someone across town for ₹20" — the floor was hardcoded at "greater
    # than nothing". Default 0 keeps the previous behaviour until it is set.
    min_collection_amount = models.DecimalField(
        max_digits=10, decimal_places=2, default=0
    )

    # Dynamic fees (Blinkit-style; default 0 → no effect until the superadmin sets them)
    small_cart_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    small_cart_threshold = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    handling_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    surge_fee = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    surge_active = models.BooleanField(default=False)

    # Loyalty earning. Points granted per ₹100 of a DELIVERED order's total. The
    # default of 10 reproduces the previous hardcoded rule (1 point per ₹10 spent),
    # so existing earning is unchanged until someone edits this. A zone may override
    # it (``zones.Zone.loyalty_points_per_100``) to run a local promo.
    loyalty_points_per_100 = models.PositiveIntegerField(default=10)

    # POS / tax
    pos_price_tax_inclusive = models.BooleanField(default=False)  # MRP includes GST?

    # Store identity (printed on POS receipts)
    store_name = models.CharField(max_length=120, default="VS Mart")
    store_address = models.CharField(max_length=300, blank=True)
    store_gstin = models.CharField(max_length=20, blank=True)

    # Misc
    currency = models.CharField(max_length=8, default="INR")
    support_phone = models.CharField(max_length=20, blank=True)
    support_email = models.EmailField(blank=True)

    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Platform configuration"

    def __str__(self):
        return "Platform configuration"

    def save(self, *args, **kwargs):
        self.pk = 1  # enforce singleton
        super().save(*args, **kwargs)

    @classmethod
    def load(cls) -> "PlatformConfig":
        obj, created = cls.objects.get_or_create(
            pk=1,
            defaults={
                "gst_rate": Decimal(str(getattr(settings, "GST_RATE", 0.18))),
                "delivery_fee": getattr(settings, "DELIVERY_FEE", 45),
                "free_delivery_threshold": getattr(settings, "FREE_DELIVERY_THRESHOLD", 499),
            },
        )
        return obj
