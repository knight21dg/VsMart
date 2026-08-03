"""Barcode generation — the one place a scannable code is minted.

Codes used to be generated only on the STORE panel's create/edit path, so any
product born anywhere else (the admin product master, the seeder, a fixture) had
no barcode at all and simply could not be scanned at a till. This module owns the
rule so every surface can call it.

In-store codes use the GS1 restricted prefix ``2`` (never issued to real
manufacturers, so they can't collide with a printed pack):
``20`` + product id for a base product, ``21`` + variant id per variant.
"""
from inventory.models import Barcode


def ean13(body12: str) -> str:
    """Append the EAN-13 check digit to a 12-digit body → a scannable 13-digit code."""
    s = sum((3 if i % 2 else 1) * int(d) for i, d in enumerate(body12))
    return body12 + str((10 - s % 10) % 10)


def generated_code(product, variant=None) -> str:
    """The deterministic in-store code for a product/variant."""
    return ean13(
        f"21{variant.id:010d}" if variant is not None else f"20{product.id:010d}"
    )


def ensure_barcode(product, variant=None):
    """Give this product/variant a scannable code if it has none. Idempotent.

    Never overwrites an existing code — a real scanned pack barcode must win over
    a generated one.
    """
    row = Barcode.objects.filter(product=product, variant=variant).first()
    if row is not None:
        return row
    return Barcode.objects.create(
        product=product,
        variant=variant,
        code=generated_code(product, variant),
        symbology="EAN13",
        is_primary=True,
    )


def ensure_product_barcodes(product):
    """Ensure the product AND each of its variants can be scanned."""
    from catalog.models import ProductVariant

    ensure_barcode(product)
    for v in ProductVariant.objects.filter(product=product):
        ensure_barcode(product, v)
