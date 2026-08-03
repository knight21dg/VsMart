from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class Review(TimeStampedModel):
    """A product review, subject to moderation.

    Reviews used to publish instantly with no approval state and no link to a
    purchase — anyone could review any product they had never bought, and there
    was no way to take a review down. Now a review that comes with a **verified
    purchase** auto-approves (the common, honest case), everything else waits in
    a moderation queue, and only approved reviews are public or counted in the
    product's rating.
    """

    class Status(models.TextChoices):
        PENDING = "pending"      # awaiting moderation
        APPROVED = "approved"    # public
        REJECTED = "rejected"    # hidden; kept for audit, not deleted

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="reviews"
    )
    product = models.ForeignKey(
        "catalog.Product", on_delete=models.CASCADE, related_name="reviews"
    )
    rating = models.PositiveSmallIntegerField()
    title = models.CharField(max_length=200, blank=True)
    body = models.TextField(blank=True)

    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.PENDING, db_index=True
    )
    # The delivered order that proves this customer actually bought the product.
    # NULL = unverified (still allowed, but it doesn't skip moderation).
    order = models.ForeignKey(
        "orders.Order", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="product_reviews",
    )
    # Denormalized from `order` so the public feed can badge and filter without
    # a join, and so the badge survives the order being deleted.
    is_verified_purchase = models.BooleanField(default=False)

    moderated_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="reviews_moderated",
    )
    moderated_at = models.DateTimeField(null=True, blank=True)
    # Internal note for the moderator. Not shown to the customer.
    moderation_reason = models.CharField(max_length=300, blank=True)

    class Meta:
        unique_together = ("user", "product")
        ordering = ["-created_at"]
        indexes = [
            # The public product feed and the moderation queue are the two hot reads.
            models.Index(fields=["product", "status"]),
            models.Index(fields=["status", "created_at"]),
        ]

    def __str__(self):
        return f"Review({self.user_id}->{self.product_id}) {self.rating}"
