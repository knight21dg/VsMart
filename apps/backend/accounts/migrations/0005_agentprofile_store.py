from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    """Agents become STORE-OWNED: a store hires and manages its own riders and
    only ever sees its own roster (the super-admin still oversees duty,
    performance and zone routing across all of them).

    Nullable + SET_NULL on purpose: existing agents have no store yet, and an
    agent must survive their store being deleted rather than being cascaded away.
    """

    dependencies = [
        ("stores", "0005_storeproduct_brand_storeproduct_description_and_more"),
        ("accounts", "0004_agentprofile_bag_capacity_agentprofile_cash_capacity_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="agentprofile",
            name="store",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="agents",
                to="stores.store",
            ),
        ),
    ]
