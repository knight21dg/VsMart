from django.db import migrations, models

import catalog.models


def backfill_tokens(apps, schema_editor):
    """Give every existing product a unique share token before the unique
    constraint is added (a single default would collide across rows)."""
    Product = apps.get_model("catalog", "Product")
    used = set()
    for p in Product.objects.all().only("id", "share_token").iterator():
        tok = catalog.models.gen_share_token()
        while tok in used:
            tok = catalog.models.gen_share_token()
        used.add(tok)
        p.share_token = tok
        p.save(update_fields=["share_token"])


class Migration(migrations.Migration):

    dependencies = [
        ("catalog", "0006_productvariant_image_url"),
    ]

    operations = [
        # 1. Add non-unique first so existing rows can be backfilled.
        migrations.AddField(
            model_name="product",
            name="share_token",
            field=models.CharField(blank=True, default="", max_length=32),
        ),
        # 2. Fill a unique token per existing product.
        migrations.RunPython(backfill_tokens, migrations.RunPython.noop),
        # 3. Now enforce uniqueness + the generating default for new rows.
        migrations.AlterField(
            model_name="product",
            name="share_token",
            field=models.CharField(
                db_index=True, default=catalog.models.gen_share_token,
                editable=False, max_length=32, unique=True,
            ),
        ),
    ]
