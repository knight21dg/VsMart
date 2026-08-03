"""Backfill v1.0 banner fields on existing Offer rows.

- state:   is_active=True  -> ACTIVE,  is_active=False -> ARCHIVED
- action:  product set     -> PRODUCT  {"product_id": ...}
           category set     -> CATEGORY {"category_id": ...}
           otherwise        -> NONE
Idempotent: only touches rows still on the defaults.
"""
from django.db import migrations


def forwards(apps, schema_editor):
    Offer = apps.get_model("offers", "Offer")
    for offer in Offer.objects.all().iterator():
        changed = False

        # state <- is_active (only if still on the model default "draft")
        if offer.state == "draft":
            offer.state = "active" if offer.is_active else "archived"
            changed = True

        # action/payload <- existing FK links (only if still NONE)
        if offer.action == "none":
            if offer.product_id:
                offer.action = "product"
                offer.payload = {"product_id": offer.product_id}
                changed = True
            elif offer.category_id:
                offer.action = "category"
                offer.payload = {"category_id": offer.category_id}
                changed = True

        if changed:
            offer.save(update_fields=["state", "action", "payload"])


def backwards(apps, schema_editor):
    # Non-destructive: nothing to undo (new columns are dropped by 0004's reverse).
    pass


class Migration(migrations.Migration):
    dependencies = [
        ("offers", "0004_alter_offer_options_offer_action_offer_approved_at_and_more"),
    ]
    operations = [migrations.RunPython(forwards, backwards)]
