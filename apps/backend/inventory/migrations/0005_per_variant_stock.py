"""Per-variant stock: give StockItem and StockBatch a variant dimension.

Additive and back-compatible. Existing rows keep ``variant=NULL``, which stays the
real (and only) bucket for every product without variants — the overwhelming
majority — so their behaviour is unchanged. For a product that HAS variants, the
NULL bucket becomes the "unallocated pool": stock received before the pack sizes
existed, counted in the product total but not sellable as a specific pack until a
store allocates it. Nothing is reassigned to a guessed pack here.

The old ``unique_together = (product, warehouse)`` is replaced by two partial
constraints because SQL NULL != NULL: a plain three-column unique would not
constrain the NULL-variant rows at all.
"""

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("inventory", "0004_supplier_store"),
        ("catalog", "0006_productvariant_image_url"),
    ]

    operations = [
        # Drop the old constraint before adding the column it no longer describes.
        migrations.AlterUniqueTogether(name="stockitem", unique_together=set()),
        migrations.AddField(
            model_name="stockitem",
            name="variant",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="stock_items",
                to="catalog.productvariant",
            ),
        ),
        migrations.AddField(
            model_name="stockbatch",
            name="variant",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="batches",
                to="catalog.productvariant",
            ),
        ),
        migrations.AddField(
            model_name="lowstockalert",
            name="variant",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name="low_stock_alerts",
                to="catalog.productvariant",
            ),
        ),
        migrations.AddConstraint(
            model_name="stockitem",
            constraint=models.UniqueConstraint(
                condition=models.Q(("variant__isnull", True)),
                fields=("product", "warehouse"),
                name="uniq_stockitem_product_warehouse_novariant",
            ),
        ),
        migrations.AddConstraint(
            model_name="stockitem",
            constraint=models.UniqueConstraint(
                condition=models.Q(("variant__isnull", False)),
                fields=("product", "variant", "warehouse"),
                name="uniq_stockitem_product_variant_warehouse",
            ),
        ),
        migrations.AddIndex(
            model_name="stockbatch",
            index=models.Index(
                fields=["product", "variant", "warehouse", "expiry_date"],
                name="inv_batch_pvwe_idx",
            ),
        ),
        migrations.AddIndex(
            model_name="inventoryledger",
            index=models.Index(
                fields=["product", "variant", "warehouse", "created_at"],
                name="inv_ledger_pvwc_idx",
            ),
        ),
    ]
