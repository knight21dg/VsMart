import uuid

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class MediaAsset(TimeStampedModel):
    """A self-hosted media asset: one logical image stored as several WebP
    variants (thumb / medium / original) under a sharded, UUID-named key.

    The model is storage-backend-agnostic — variants are written through Django's
    storage API (filesystem on the VPS today; MinIO/S3 by swapping ``STORAGES``).
    ``visibility`` decides how the bytes are served: ``public`` assets are open
    (the unguessable UUID is the privacy boundary, CDN-cacheable); ``private``
    assets are gated behind an ownership/staff check.
    """

    class Visibility(models.TextChoices):
        PUBLIC = "public"
        PRIVATE = "private"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="media_assets",
    )
    # Logical bucket: products / categories / banners / kyc / pod / profile / temp …
    category = models.CharField(max_length=32, default="misc")
    visibility = models.CharField(
        max_length=8, choices=Visibility.choices, default=Visibility.PRIVATE
    )
    content_type = models.CharField(max_length=40, default="image/webp")
    size_bytes = models.PositiveIntegerField(default=0)  # original variant size
    width = models.PositiveIntegerField(default=0)
    height = models.PositiveIntegerField(default=0)
    original_name = models.CharField(max_length=200, blank=True)
    checksum = models.CharField(max_length=64, blank=True)  # sha256 of the source

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["owner", "category"]),
            models.Index(fields=["category", "created_at"]),
        ]

    def __str__(self):
        return f"MediaAsset({self.id} {self.category}/{self.visibility})"

    @property
    def base_key(self) -> str:
        """Sharded storage prefix `<visibility>/<aa>/<bb>/<uuid>` — the two-byte
        fan-out keeps any one directory from collecting millions of files."""
        h = self.id.hex
        return f"{self.visibility}/{h[:2]}/{h[2:4]}/{h}"

    def variant_key(self, variant: str) -> str:
        """Storage key for one rendered variant (always WebP)."""
        return f"{self.base_key}_{variant}.webp"
