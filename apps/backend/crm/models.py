from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class CustomerNote(TimeStampedModel):
    """An ops/admin note attached to a customer. This is the ONLY data the CRM
    stores itself — it is net-new (notes have no home in any other module); every
    other Customer-360 field is aggregated live from the source-of-truth modules."""

    class Category(models.TextChoices):
        ADMIN = "admin"
        COLLECTION = "collection"
        DELIVERY = "delivery"
        VERIFICATION = "verification"

    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="crm_notes"
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="+",
    )
    category = models.CharField(
        max_length=14, choices=Category.choices, default=Category.ADMIN
    )
    body = models.TextField()

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Note on {self.customer_id} ({self.created_at:%Y-%m-%d})"
