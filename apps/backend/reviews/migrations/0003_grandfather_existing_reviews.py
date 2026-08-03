"""Grandfather reviews that were already public.

`status` defaults to PENDING, which would retroactively hide every review ever
posted — they were live before moderation existed, and silently pulling them
would drop products' ratings overnight. Existing rows are marked APPROVED, and
`is_verified_purchase` is backfilled where a delivered order can be found.
"""
from django.db import migrations


def grandfather(apps, schema_editor):
    Review = apps.get_model("reviews", "Review")
    Order = apps.get_model("orders", "Order")

    Review.objects.update(status="approved")

    # Backfill the verified badge. Done per-review rather than in bulk because
    # the match is (user, product) against delivered order lines.
    for review in Review.objects.all().iterator():
        order = (
            Order.objects.filter(
                user_id=review.user_id,
                status="delivered",
                items__product_id=review.product_id,
            )
            .order_by("-id")
            .first()
        )
        if order is not None:
            review.order_id = order.id
            review.is_verified_purchase = True
            review.save(update_fields=["order_id", "is_verified_purchase"])


def unapply(apps, schema_editor):
    # Nothing to undo: the columns go away with the schema migration.
    pass


class Migration(migrations.Migration):

    dependencies = [
        ("reviews", "0002_review_is_verified_purchase_review_moderated_at_and_more"),
        ("orders", "0001_initial"),
    ]

    operations = [
        migrations.RunPython(grandfather, unapply),
    ]
