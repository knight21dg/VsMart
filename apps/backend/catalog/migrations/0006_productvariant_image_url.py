from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("catalog", "0005_product_origin_store_and_more")]

    operations = [
        migrations.AddField(
            model_name="productvariant",
            name="image_url",
            field=models.URLField(blank=True, max_length=500),
        ),
    ]
