"""Store `Product.gst_rate` as a percentage (18), not a fraction (0.18).

The column was fed from an admin form labelled "GST rate (0–1)", so operators
typed 0.18 for 18%. That value was then snapshotted verbatim into
`OrderItem.gst_rate` — a column whose own docstring calls it "GST rate (%)" —
recording every line at 0.18% instead of 18%. Nothing read the snapshot yet, so
no invoice was wrong, but the data was, and a GST return built from it would
have been.

`core.pricing` now owns the single conversion rule (API and storage speak
percentages; only the pricing maths uses fractions). This brings existing rows
in line with it.
"""
from decimal import Decimal

from django.db import migrations, models


def to_percentage(apps, schema_editor):
    """Multiply the legacy fractions up to percentages.

    A real GST rate is never between 0 and 1 exclusive (the lowest non-zero slab
    is 0.25%, which as a fraction would be 0.0025), so `0 < value < 1` reliably
    identifies a fraction that needs scaling. Values already >= 1 were entered
    as percentages and are left untouched, which also makes this migration safe
    to re-run against a partially corrected table.
    """
    Product = apps.get_model("catalog", "Product")
    for product in Product.objects.exclude(gst_rate__isnull=True).exclude(gst_rate=0):
        rate = Decimal(product.gst_rate)
        if Decimal("0") < rate < Decimal("1"):
            product.gst_rate = (rate * Decimal("100")).quantize(Decimal("0.01"))
            product.save(update_fields=["gst_rate"])


def to_fraction(apps, schema_editor):
    """Reverse: percentages back down to fractions."""
    Product = apps.get_model("catalog", "Product")
    for product in Product.objects.exclude(gst_rate__isnull=True).exclude(gst_rate=0):
        rate = Decimal(product.gst_rate)
        if rate >= Decimal("1"):
            product.gst_rate = (rate / Decimal("100")).quantize(Decimal("0.01"))
            product.save(update_fields=["gst_rate"])


class Migration(migrations.Migration):

    dependencies = [("catalog", "0009_product_search_keywords")]

    operations = [
        # 4 digits capped the column at 99.99; 5 leaves room and matches
        # OrderItem.gst_rate, which the value is copied into.
        migrations.AlterField(
            model_name="product",
            name="gst_rate",
            field=models.DecimalField(
                blank=True, decimal_places=2, max_digits=5, null=True
            ),
        ),
        migrations.RunPython(to_percentage, to_fraction),
    ]
