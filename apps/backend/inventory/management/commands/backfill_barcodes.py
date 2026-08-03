"""Give every product (and variant) a scannable barcode.

Barcodes were only ever minted on the store panel's create/edit path, so the
seeded/company catalog has none — those products cannot be scanned at the POS at
all. This backfills them idempotently.

    python manage.py backfill_barcodes --dry-run
    python manage.py backfill_barcodes
"""
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count

from catalog.models import Product, ProductVariant
from inventory.barcodes import ensure_barcode, generated_code
from inventory.models import Barcode


class Command(BaseCommand):
    help = "Generate in-store barcodes for products/variants that have none."

    def add_arguments(self, parser):
        parser.add_argument("--dry-run", action="store_true",
                            help="Report what WOULD be generated; write nothing.")

    @transaction.atomic
    def handle(self, *args, **o):
        dry = o["dry_run"]

        missing = list(Product.objects.annotate(n=Count("barcodes")).filter(n=0))
        # A variant is its own sellable unit, so it needs its own code.
        var_missing = [
            v for v in ProductVariant.objects.select_related("product")
            if not Barcode.objects.filter(product=v.product, variant=v).exists()
        ]

        for p in missing:
            self.stdout.write(f"  product {p.id:>4}  {p.name[:34]:34} -> {generated_code(p)}")
            if not dry:
                ensure_barcode(p)
        for v in var_missing:
            self.stdout.write(f"  variant {v.id:>4}  {v.product.name[:24]} · {v.label[:8]:8} -> {generated_code(v.product, v)}")
            if not dry:
                ensure_barcode(v.product, v)

        verb = "would generate" if dry else "generated"
        self.stdout.write(self.style.SUCCESS(
            f"{verb} {len(missing)} product + {len(var_missing)} variant barcode(s)."
        ))
        if dry:
            self.stdout.write("(dry run — nothing written)")
