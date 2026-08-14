"""Repair `OrderItem.gst_rate` rows that recorded a fraction instead of a percentage.

Companion to `catalog.0010`, which fixed the source of the bug. This fixes the
rows it already produced.

`OrderItem.gst_rate` is documented as a percentage, but `place_order` copied
`PlatformConfig.gst_rate` — a *fraction* — into it whenever a product carried no
explicit rate. Every such line recorded **0.18**, i.e. 0.18 %, where 18 % was
charged.

This is a repair of a corrupted denormalised label, not a rewrite of history:
the money actually charged lives in `Order.gst` / `Order.total` and was always
computed correctly from the fraction. Only the per-line rate *label* is wrong,
and nothing reads it today — which is the only reason no invoice went out with
it. It is fixed now so that anything built on it later (a GST return, a line-level
tax breakdown) starts from honest data rather than a 100×-wrong rate.

SAFETY
------
* **Idempotent.** Only `0 < value < 1` is scaled. A real GST rate never falls in
  that open interval — the lowest non-zero slab is 0.25 %, which as a fraction
  would be 0.0025 — so a second run finds nothing to do.
* **`0` is left alone.** A zero rate is either genuinely zero-rated or a row that
  predates the snapshot; either way `0 < v` is false.
* **Reversible**, and the reverse is guarded the same way.
* Touches exactly one column. No schema change, no constraint, no index.

Deliberately a SEPARATE migration from `catalog.0010` so an operator who wants
to correct the product master but leave historical order lines untouched can
skip precisely this one.
"""
from decimal import Decimal

from django.db import migrations

ONE = Decimal("1")
HUNDRED = Decimal("100")
CENTS = Decimal("0.01")


def to_percentage(apps, schema_editor):
    OrderItem = apps.get_model("orders", "OrderItem")
    # Bulk-update in one pass; the affected set is small (only lines that fell
    # back to the platform default) and each row needs its own computed value.
    stale = OrderItem.objects.filter(gst_rate__gt=0, gst_rate__lt=ONE)
    rows = []
    for item in stale.only("id", "gst_rate").iterator(chunk_size=2000):
        item.gst_rate = (Decimal(item.gst_rate) * HUNDRED).quantize(CENTS)
        rows.append(item)
        if len(rows) >= 2000:
            OrderItem.objects.bulk_update(rows, ["gst_rate"])
            rows = []
    if rows:
        OrderItem.objects.bulk_update(rows, ["gst_rate"])


def to_fraction(apps, schema_editor):
    OrderItem = apps.get_model("orders", "OrderItem")
    stale = OrderItem.objects.filter(gst_rate__gte=ONE)
    rows = []
    for item in stale.only("id", "gst_rate").iterator(chunk_size=2000):
        item.gst_rate = (Decimal(item.gst_rate) / HUNDRED).quantize(CENTS)
        rows.append(item)
        if len(rows) >= 2000:
            OrderItem.objects.bulk_update(rows, ["gst_rate"])
            rows = []
    if rows:
        OrderItem.objects.bulk_update(rows, ["gst_rate"])


class Migration(migrations.Migration):

    dependencies = [
        ("orders", "0011_ordertracking_agent_contact"),
        # Ordered after the product-master fix so the two land together.
        ("catalog", "0010_product_gst_rate_as_percentage"),
    ]

    operations = [migrations.RunPython(to_percentage, to_fraction)]
