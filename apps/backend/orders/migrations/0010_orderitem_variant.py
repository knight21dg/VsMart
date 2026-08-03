"""Record which pack an order line is for, so fulfilment decrements that variant's
stock bucket instead of the product pool. Existing lines keep NULL — they were
placed when stock was pooled, and their composed name is the only record of the
pack; nothing is inferred from it here.
"""

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("orders", "0009_order_uniq_order_idempotency"),
        ("catalog", "0006_productvariant_image_url"),
    ]

    operations = [
        migrations.AddField(
            model_name="orderitem",
            name="variant",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                to="catalog.productvariant",
            ),
        ),
    ]
