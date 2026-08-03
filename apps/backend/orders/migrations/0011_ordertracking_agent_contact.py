"""Give OrderTracking the rider's phone + photo so the customer can call and see
who's delivering. Snapshotted at assignment; blank when unknown."""

from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("orders", "0010_orderitem_variant")]

    operations = [
        migrations.AddField(
            model_name="ordertracking",
            name="agent_phone",
            field=models.CharField(blank=True, max_length=20),
        ),
        migrations.AddField(
            model_name="ordertracking",
            name="agent_photo_url",
            field=models.CharField(blank=True, max_length=500),
        ),
    ]
