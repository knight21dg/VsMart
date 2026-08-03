"""Re-host external catalog images onto VS Mart's self-hosted media engine.

    python manage.py rehost_catalog_images [--model all] [--limit N] [--dry-run]

External catalog images today point at third-party CDNs (e.g. DummyJSON). This
command downloads each external image and funnels its bytes through
:func:`mediastore.pipeline.store_image` (validate → EXIF-strip → WebP →
thumb/medium/original), then rewrites the field to the self-hosted public URL
``/api/v1/media/public/<asset.id>/medium``.

Idempotent: rows whose URL already points at ``/api/v1/media/public/`` are
skipped, so re-running never produces duplicate assets. Per-item resilient: a
failed download or ingest logs a warning and the batch continues.

The network fetch is isolated in module-level :func:`_fetch` so tests can patch
it (``mock.patch("catalog.management.commands.rehost_catalog_images._fetch")``)
and never touch the network.
"""
import logging
import urllib.request

from django.core.management.base import BaseCommand

from catalog.models import Category, Product, ProductImage
from mediastore.pipeline import store_image

logger = logging.getLogger(__name__)

# Self-hosted public-media path prefix. A URL already starting with this has
# been rehosted; we skip it for idempotency.
LOCAL_PREFIX = "/api/v1/media/public/"
FETCH_TIMEOUT = 20  # seconds


def _fetch(url: str) -> bytes:
    """Download ``url`` and return the raw bytes.

    Isolated at module level so tests can ``mock.patch`` it (no real network).
    """
    req = urllib.request.Request(url, headers={"User-Agent": "VSMart-rehost/1.0"})
    with urllib.request.urlopen(req, timeout=FETCH_TIMEOUT) as resp:
        return resp.read()


def _is_external(url) -> bool:
    """True only for a real external http(s) URL that is not already local."""
    if not url:
        return False
    url = url.strip()
    if url.startswith(LOCAL_PREFIX):
        return False
    return url.startswith("http://") or url.startswith("https://")


# Each target: model, URL field name, and the mediastore category bucket.
TARGETS = {
    "product": (Product, "image_url", "catalog"),
    "category": (Category, "image_url", "category"),
    "productimage": (ProductImage, "url", "catalog"),
}


class Command(BaseCommand):
    help = "Re-host external catalog/category/product-image URLs onto the self-hosted media engine."

    def add_arguments(self, parser):
        parser.add_argument(
            "--model",
            choices=["product", "category", "productimage", "all"],
            default="all",
            help="Which model to process (default: all).",
        )
        parser.add_argument(
            "--limit",
            type=int,
            default=None,
            help="Cap the total number of rows processed (across all selected models).",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Report what would be rehosted without downloading or writing.",
        )

    def handle(self, *args, **options):
        model_opt = options["model"]
        limit = options["limit"]
        dry_run = options["dry_run"]

        which = list(TARGETS) if model_opt == "all" else [model_opt]

        processed = skipped = failed = 0

        for key in which:
            if limit is not None and processed >= limit:
                break
            model, field, category = TARGETS[key]
            qs = model.objects.all().order_by("pk")
            for obj in qs.iterator():
                if limit is not None and processed >= limit:
                    break
                url = getattr(obj, field)
                if not _is_external(url):
                    skipped += 1
                    continue

                if dry_run:
                    processed += 1
                    self.stdout.write(f"[dry-run] {key} #{obj.pk}: would rehost {url}")
                    continue

                try:
                    raw = _fetch(url.strip())
                    asset = store_image(
                        raw, category=category, visibility="public",
                        original_name=f"{key}-{obj.pk}",
                    )
                except Exception as exc:  # noqa: BLE001 — per-item resilience
                    failed += 1
                    logger.warning(
                        "rehost failed for %s #%s (%s): %s", key, obj.pk, url, exc
                    )
                    self.stderr.write(
                        self.style.WARNING(f"FAILED {key} #{obj.pk}: {exc}")
                    )
                    continue

                new_url = f"{LOCAL_PREFIX}{asset.id}/medium"
                setattr(obj, field, new_url)
                obj.save(update_fields=[field])
                processed += 1
                self.stdout.write(f"{key} #{obj.pk}: {url} -> {new_url}")

        summary = (
            f"Done ({'dry-run' if dry_run else 'live'}). "
            f"processed={processed} skipped={skipped} failed={failed}"
        )
        self.stdout.write(self.style.SUCCESS(summary))
