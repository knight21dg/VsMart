"""Inventory stock operations. The one rule: **never update stock directly.**

Every movement goes through `InventoryService.post_movement` (the sole writer),
which appends a signed row to the `InventoryLedger` and updates the `StockItem`
cache inside one DB transaction. On-hand for a product×variant×warehouse is
Σ ledger.qty; `available = on_hand − reserved`. `reconcile()` rebuilds the cache
from the ledger as the integrity check. Mirrors the credit ledger
(`credit/services.py`).

**Variants are separate stock.** A 1kg pack and a 500g pack are counted apart, so
every bucket is product×variant×warehouse. Because `variant=None` is a legitimate
bucket (the unallocated pool, and the only bucket a product without variants has),
it cannot double as "any variant" — the two mean different things. Reads therefore
default to the `ANY_VARIANT` sentinel (sum every bucket = the product total, which
is what all the pre-variant callers meant and still get), while writes take
`variant=None` literally.
"""
import logging
from decimal import Decimal

from django.db import transaction
from django.db.models import F, Sum
from django.utils import timezone

from catalog.models import Product
from core.events import record_event

logger = logging.getLogger(__name__)

from .models import (
    GRN,
    InventoryLedger,
    LowStockAlert,
    PurchaseOrder,
    StockBatch,
    StockItem,
    Warehouse,
)

ZERO = Decimal("0.00")
Type = InventoryLedger.Type


class InventoryError(Exception):
    pass


class _AnyVariant:
    """Sentinel: 'every variant bucket', as distinct from `None` = 'the bucket with
    no variant'. Needed because None is a real bucket, so it can't also mean 'any'."""

    def __bool__(self):
        return False  # falsy, so `if variant:` still reads as "a specific pack"

    def __repr__(self):
        return "<ANY_VARIANT>"


ANY_VARIANT = _AnyVariant()


def _scope_variant(qs, variant):
    """Narrow a StockItem/StockBatch/InventoryLedger queryset to a variant bucket.
    `ANY_VARIANT` → untouched (all buckets); `None` → the unallocated/no-variant
    bucket only; a variant → that bucket."""
    if isinstance(variant, _AnyVariant):
        return qs
    if variant is None:
        return qs.filter(variant__isnull=True)
    return qs.filter(variant=variant)


def has_variants(product) -> bool:
    return product.variants.exists()


def default_warehouse() -> Warehouse:
    """The store's primary warehouse. Resolves the `is_default` flag, else the
    oldest active warehouse, creating a "Main Store" if none exist yet."""
    wh = (
        Warehouse.objects.filter(is_default=True).order_by("created_at").first()
        or Warehouse.objects.filter(is_active=True).order_by("created_at").first()
    )
    if wh is None:
        wh = Warehouse.objects.create(name="Main Store", code="MAIN", is_default=True)
    return wh


# ── Calculation ──────────────────────────────────────────
class StockCalculationService:
    """Derived stock values — always computed from the ledger / cache, never stored
    as an independent mutable number."""

    @staticmethod
    def on_hand(product, warehouse=None, variant=ANY_VARIANT) -> int:
        """On-hand from the `StockItem` cache (== Σ ledger.qty by invariant; rebuilt by
        `reconcile`). Reading the cache is O(buckets), not O(ledger rows).

        Default `variant=ANY_VARIANT` sums every pack — the product total, which is
        what listings, reports and low-stock have always meant by "how many"."""
        qs = StockItem.objects.filter(product=product)
        if warehouse is not None:
            qs = qs.filter(warehouse=warehouse)
        return _scope_variant(qs, variant).aggregate(s=Sum("quantity"))["s"] or 0

    @staticmethod
    def ledger_balance(product, warehouse=None, variant=ANY_VARIANT) -> int:
        """True Σ ledger.qty straight from the ledger — the integrity reference that
        `reconcile` checks the cache against."""
        qs = InventoryLedger.objects.filter(product=product)
        if warehouse is not None:
            qs = qs.filter(warehouse=warehouse)
        return _scope_variant(qs, variant).aggregate(s=Sum("quantity"))["s"] or 0

    @staticmethod
    def reserved(product, warehouse=None, variant=ANY_VARIANT) -> int:
        qs = StockItem.objects.filter(product=product)
        if warehouse is not None:
            qs = qs.filter(warehouse=warehouse)
        return _scope_variant(qs, variant).aggregate(s=Sum("reserved"))["s"] or 0

    @staticmethod
    def available(product, warehouse=None, variant=ANY_VARIANT) -> int:
        return (
            StockCalculationService.on_hand(product, warehouse, variant)
            - StockCalculationService.reserved(product, warehouse, variant)
        )

    @staticmethod
    def by_variant(product, warehouse=None) -> dict:
        """`{variant_id or None: {onHand, reserved, available}}` for every bucket that
        exists — one query, for the per-pack stock rows the panels render."""
        qs = StockItem.objects.filter(product=product)
        if warehouse is not None:
            qs = qs.filter(warehouse=warehouse)
        out = {}
        for row in qs.values("variant_id").annotate(
            on_hand=Sum("quantity"), res=Sum("reserved")
        ):
            on_hand, res = row["on_hand"] or 0, row["res"] or 0
            out[row["variant_id"]] = {
                "onHand": on_hand, "reserved": res, "available": on_hand - res,
            }
        return out

    @staticmethod
    def by_variant_bulk(product_ids, warehouse=None) -> dict:
        """Same shape as `by_variant`, for MANY products in one query:
        `{product_id: {variant_id or None: {onHand, reserved, available}}}`.

        For a listing page of N products, calling `by_variant` once per card is
        N extra queries — this is the batched form, so a product grid/rail costs
        exactly one. Used to give listing cards the SAME per-pack stock truth the
        product detail page already has, instead of a flat product-level
        `in_stock` that's true the moment ANY pack has stock (correct for "is this
        buyable at all", wrong for "is the specific pack a card/add-to-cart
        represents actually the one in stock").
        """
        if not product_ids:
            return {}
        qs = StockItem.objects.filter(product_id__in=product_ids)
        if warehouse is not None:
            qs = qs.filter(warehouse=warehouse)
        out: dict = {}
        for row in qs.values("product_id", "variant_id").annotate(
            on_hand=Sum("quantity"), res=Sum("reserved")
        ):
            on_hand, res = row["on_hand"] or 0, row["res"] or 0
            out.setdefault(row["product_id"], {})[row["variant_id"]] = {
                "onHand": on_hand, "reserved": res, "available": on_hand - res,
            }
        return out

    @staticmethod
    def fefo_batches(product, warehouse, variant=ANY_VARIANT):
        """Batches with stock, first-expiry-first-out. Scoped to one pack when given:
        a 1kg sale must not consume the 500g lot that happens to expire sooner."""
        qs = StockBatch.objects.filter(
            product=product, warehouse=warehouse, quantity__gt=0
        )
        return _scope_variant(qs, variant).order_by("expiry_date", "created_at")


# ── The sole writer ──────────────────────────────────────
class InventoryService:
    @staticmethod
    @transaction.atomic
    def post_movement(
        *,
        product,
        type,
        quantity,
        warehouse=None,
        variant=None,
        batch=None,
        expiry_date=None,
        unit_cost=None,
        ref_type="",
        ref_id="",
        note="",
        created_by=None,
        allow_negative=False,
        allow_unallocated=False,
    ) -> InventoryLedger:
        """Append one signed ledger row and update the StockItem cache atomically.

        `quantity` is signed (positive = stock in, negative = stock out). This is the
        ONLY place StockItem.quantity is mutated. Raises InventoryError if the move
        would drive the bucket below zero (unless `allow_negative`).

        `variant` selects the stock bucket and is taken literally — `None` is the
        product's own bucket, not "any". Moving a variant-carrying product without
        naming the pack raises, because such stock is unsellable: no variant can
        draw on it, so it would sit in the total looking available while every pack
        reads zero. `allow_unallocated` exempts the two callers that legitimately
        touch that pool — the legacy opening adoption and the allocate flow that
        drains it.
        """
        quantity = int(quantity)
        if quantity == 0:
            raise InventoryError("Movement quantity cannot be zero.")
        warehouse = warehouse or default_warehouse()
        if variant is not None and variant.product_id != product.id:
            raise InventoryError(
                f"Variant '{variant.label}' does not belong to {product}."
            )
        if variant is None and not allow_unallocated and has_variants(product):
            raise InventoryError(
                f"{product} is sold by pack — name a variant for this movement "
                f"({', '.join(v.label for v in product.variants.all())})."
            )

        # Adopt any legacy on-hand (Product.stock_count / pre-ledger StockItems)
        # the first time this product is touched, so cache == ledger from row one.
        InventoryService._ensure_opening(product, created_by)

        item, _ = StockItem.objects.select_for_update().get_or_create(
            product=product, variant=variant, warehouse=warehouse,
            defaults={"quantity": 0},
        )
        new_on_hand = item.quantity + quantity
        if new_on_hand < 0 and not allow_negative:
            label = f" · {variant.label}" if variant else ""
            raise InventoryError(
                f"Insufficient stock for {product}{label}: {item.quantity} on hand, "
                f"move {quantity:+d}."
            )

        entry = InventoryLedger.objects.create(
            product=product,
            variant=variant,
            warehouse=warehouse,
            type=type,
            quantity=quantity,
            balance_after=new_on_hand,
            batch=batch,
            expiry_date=expiry_date,
            unit_cost=unit_cost,
            ref_type=ref_type,
            ref_id=str(ref_id) if ref_id else "",
            note=note,
            created_by=created_by,
        )
        item.quantity = new_on_hand
        update_fields = ["quantity", "updated_at"]
        # Track the segregated damaged/expired bucket for the store-inventory view.
        if type in (InventoryLedger.Type.DAMAGE, InventoryLedger.Type.EXPIRY):
            item.damaged = (item.damaged or 0) + abs(quantity)
            update_fields.append("damaged")
        item.save(update_fields=update_fields)

        if batch is not None:
            StockBatch.objects.filter(pk=batch.pk).update(
                quantity=F("quantity") + quantity
            )

        StockSyncService.broadcast(product, warehouse)
        # Realtime/analytics feed — fire only after the movement actually commits.
        payload = {
            "product": product.id, "warehouse": warehouse.id, "type": str(type),
            "variant": variant.id if variant else None,
            "qty": quantity, "balanceAfter": new_on_hand,
        }
        transaction.on_commit(
            lambda: record_event("stock_moved", payload, actor=created_by)
        )
        return entry

    @staticmethod
    def _ensure_opening(product, created_by=None):
        """Idempotent: if the product has no ledger history yet, seed `opening` rows
        adopting whatever legacy on-hand it had (existing StockItem caches, else
        Product.stock_count into the default warehouse). No-op once any row exists."""
        if InventoryLedger.objects.filter(product=product).exists():
            return
        seeded = False
        for item in StockItem.objects.select_for_update().filter(
            product=product, quantity__gt=0
        ):
            InventoryLedger.objects.create(
                product=product,
                # Adopt each bucket as it stands, including the variant it sits in —
                # dropping it here would move pre-existing per-pack stock into the
                # unallocated pool and make it unsellable.
                variant=item.variant,
                warehouse=item.warehouse,
                type=Type.OPENING,
                quantity=item.quantity,
                balance_after=item.quantity,
                note="Opening (adopted existing stock)",
                created_by=created_by,
            )
            seeded = True
        if seeded:
            return
        legacy = product.stock_count
        if legacy:
            wh = default_warehouse()
            item, _ = StockItem.objects.select_for_update().get_or_create(
                product=product, warehouse=wh, defaults={"quantity": 0}
            )
            InventoryLedger.objects.create(
                product=product,
                warehouse=wh,
                type=Type.OPENING,
                quantity=int(legacy),
                balance_after=int(legacy),
                note="Opening (adopted legacy stock_count)",
                created_by=created_by,
            )
            item.quantity = int(legacy)
            item.save(update_fields=["quantity", "updated_at"])

    @staticmethod
    @transaction.atomic
    def reserve(product, *, quantity, warehouse=None, variant=None, created_by=None):
        """Hold stock for a pending order: bump `StockItem.reserved` under lock so two
        checkouts can't both claim the last unit. On-hand is unchanged until fulfilment.

        Reserves the named pack's bucket — holding "2 rice" against the product total
        would let two customers reserve the same 1kg while the 500g shelf covers the
        arithmetic."""
        warehouse = warehouse or default_warehouse()
        quantity = int(quantity)
        if quantity <= 0:
            raise InventoryError("Reservation quantity must be positive.")
        if variant is None and has_variants(product):
            raise InventoryError(f"{product} is sold by pack — name a variant to reserve.")
        InventoryService._ensure_opening(product, created_by)
        item, _ = StockItem.objects.select_for_update().get_or_create(
            product=product, variant=variant, warehouse=warehouse,
            defaults={"quantity": 0},
        )
        available = item.quantity - item.reserved
        if quantity > available:
            label = f" · {variant.label}" if variant else ""
            raise InventoryError(
                f"Only {available} of {product.name}{label} available to reserve."
            )
        item.reserved += quantity
        item.save(update_fields=["reserved", "updated_at"])
        StockSyncService.broadcast(product, warehouse)
        return item

    @staticmethod
    @transaction.atomic
    def release(product, *, quantity, warehouse=None, variant=None):
        """Release a prior reservation (order cancelled or being fulfilled)."""
        warehouse = warehouse or default_warehouse()
        item = (
            _scope_variant(
                StockItem.objects.select_for_update().filter(
                    product=product, warehouse=warehouse
                ),
                variant,
            ).first()
        )
        if item is None:
            return
        wanted = int(quantity)
        if wanted > item.reserved:
            # Clamped rather than raised, so an unwind never fails half-way — but
            # LOUD, because silently absorbing it is what made reserved-count drift
            # undetectable in production. Reaching here means a double-release or a
            # release of a hold that was never taken (e.g. a product's stock_count
            # was cleared between reserve and release, flipping the predicate those
            # two paths are gated on).
            logger.warning(
                "Reserve underflow releasing %s of product=%s variant=%s "
                "warehouse=%s: only %s reserved. Clamping to 0.",
                wanted, product.pk, getattr(variant, "pk", None),
                warehouse.pk, item.reserved,
            )
        item.reserved = max(0, item.reserved - wanted)
        item.save(update_fields=["reserved", "updated_at"])
        StockSyncService.broadcast(product, warehouse)

    @staticmethod
    @transaction.atomic
    def transfer(product, *, from_warehouse, to_warehouse, quantity, variant=None,
                 created_by=None, note=""):
        """Move stock between warehouses as two conserving ledger rows. The pack moves
        as itself — sending 10 units of a variant product means 10 of *that* pack."""
        if from_warehouse == to_warehouse:
            raise InventoryError("Source and destination warehouses must differ.")
        out = InventoryService.post_movement(
            product=product, variant=variant, warehouse=from_warehouse,
            type=Type.TRANSFER_OUT, quantity=-abs(int(quantity)),
            ref_type="transfer", note=note, created_by=created_by,
        )
        InventoryService.post_movement(
            product=product, variant=variant, warehouse=to_warehouse,
            type=Type.TRANSFER_IN, quantity=abs(int(quantity)),
            ref_type="transfer", note=note, created_by=created_by,
        )
        return out

    @staticmethod
    @transaction.atomic
    def allocate(product, *, variant, quantity, warehouse=None, created_by=None,
                 note=""):
        """Move units out of the unallocated pool (`variant=NULL`) into a real pack.

        Stock received before a product had variants can't be sold — no pack can draw
        on it. Rather than guess which pack those units are, the pool is surfaced in
        the panels and the store says. Two conserving adjustment rows, so the total
        never changes and the move is auditable.
        """
        if variant is None:
            raise InventoryError("Allocate needs a target variant.")
        warehouse = warehouse or default_warehouse()
        quantity = abs(int(quantity))
        pool = StockCalculationService.on_hand(product, warehouse, variant=None)
        if quantity > pool:
            raise InventoryError(f"Only {pool} unallocated unit(s) to assign.")
        note = note or f"Allocated to {variant.label}"
        InventoryService.post_movement(
            product=product, variant=None, warehouse=warehouse,
            type=Type.ADJUSTMENT, quantity=-quantity, ref_type="allocate",
            note=note, created_by=created_by, allow_unallocated=True,
        )
        return InventoryService.post_movement(
            product=product, variant=variant, warehouse=warehouse,
            type=Type.ADJUSTMENT, quantity=quantity, ref_type="allocate",
            note=note, created_by=created_by,
        )

    @staticmethod
    @transaction.atomic
    def adjust(product, *, set=None, delta=None, warehouse=None, variant=None,
               reason="", created_by=None):
        """Manual correction routed through the ledger. `set` targets an absolute
        on-hand; `delta` applies a signed change. On-hand is clamped at zero
        (physical stock can't go negative). Returns the new on-hand.

        Adjusts ONE bucket. A count is a count of a shelf: "50 of the 1kg" says
        nothing about the 500g, so both the read and the write are scoped to the
        named pack rather than the product total.

        ATOMIC + ROW-LOCKED: this is a read-modify-write (read on-hand → post the
        difference as a delta), so the read MUST hold the same lock the write takes.
        Unlocked, a concurrent sale between the read and the post silently corrupts
        the result: shelf 30, cashier sells 5, you "set" 50 → +20 lands on 25 → 45.
        Counting a shelf while the till is live is exactly when this is used.
        """
        warehouse = warehouse or default_warehouse()
        if variant is None and has_variants(product):
            raise InventoryError(f"{product} is sold by pack — name a variant to adjust.")
        InventoryService._ensure_opening(product, created_by)
        # Take the StockItem lock BEFORE reading, so `current` can't move under us.
        # post_movement re-locks the same row (re-entrant within this transaction).
        _scope_variant(
            StockItem.objects.select_for_update().filter(
                product=product, warehouse=warehouse
            ),
            variant,
        ).first()
        current = StockCalculationService.on_hand(product, warehouse, variant)
        if set is not None:
            # An explicit physical count is REJECTED when negative rather than
            # clamped: silently turning "-5" into 0 wipes real stock and reports a
            # variance that never happened. A *derived* target (from `delta`) still
            # clamps — that's the documented "stock can't go negative" rule.
            try:
                target = int(set)
            except (TypeError, ValueError):
                raise InventoryError("Counted quantity must be a whole number.")
            if target < 0:
                raise InventoryError("Counted quantity cannot be negative.")
        else:
            try:
                step = int(delta or 0)
            except (TypeError, ValueError):
                raise InventoryError("Adjustment must be a whole number.")
            target = max(0, current + step)
        change = target - current
        if change != 0:
            InventoryService.post_movement(
                product=product, variant=variant, warehouse=warehouse,
                type=Type.ADJUSTMENT, quantity=change, ref_type="adjustment",
                note=reason, created_by=created_by, allow_negative=True,
            )
        else:
            # Still ensure the product caches are synced even on a no-op.
            StockSyncService.broadcast(product, warehouse)
        return StockCalculationService.on_hand(product, warehouse, variant)


def consume_fefo(*, product, warehouse, quantity, type, variant=None, **kw):
    """Post an OUTBOUND movement, drawing from batches first-expiry-first-out.

    Why this exists: `fefo_batches` and `StockBatch` were built for exactly this
    and then never called — every sale posted an unbatched movement, so
    `StockBatch.quantity` only ever went UP (on receipt). Batch stock therefore
    drifted permanently above reality and the expiry/aging reports listed lots
    that had physically been sold.

    `quantity` is POSITIVE here (the amount leaving); this signs it. A sale
    spanning two lots posts one ledger row per lot, so the ledger says which
    physical stock left — that's the point of batch tracking.

    IMPORTANT — behaviour with no batches is byte-identical to the old code path:
    a product with no `StockBatch` rows (the common case, and every product today)
    falls through to a single unbatched movement exactly as before. Batch tracking
    only engages for stock that was actually received as a lot.

    Lots are drawn from the SOLD pack only: a 1kg sale must not consume a 500g lot
    just because it expires sooner. They're different physical stock.
    """
    qty = int(quantity)
    if qty <= 0:
        raise InventoryError("Consumed quantity must be positive.")

    batches = list(
        StockCalculationService.fefo_batches(product, warehouse, variant=variant)
    )
    if not batches:
        return [InventoryService.post_movement(
            product=product, variant=variant, warehouse=warehouse, type=type,
            quantity=-qty, **kw)]

    rows, left = [], qty
    for b in batches:
        if left <= 0:
            break
        take = min(int(b.quantity), left)
        if take <= 0:
            continue
        rows.append(InventoryService.post_movement(
            product=product, variant=variant, warehouse=warehouse, type=type,
            quantity=-take, batch=b, expiry_date=b.expiry_date, **kw))
        left -= take
    if left > 0:
        # More sold than the lots hold — the batches are behind the ledger (e.g.
        # stock adjusted in without a lot). Post the remainder unbatched rather
        # than refuse: the on-hand total is the source of truth, not the lots.
        rows.append(InventoryService.post_movement(
            product=product, variant=variant, warehouse=warehouse, type=type,
            quantity=-left, **kw))
    return rows


# ── Sync engine (cache + alerts + broadcast) ─────────────
class StockSyncService:
    """Called after every movement: recompute the Product-level cache the customer
    app/orders read, and raise/clear low-stock alerts. (Realtime push + analytics
    events are layered on here later.)"""

    @staticmethod
    def broadcast(product, warehouse=None):
        total = StockCalculationService.on_hand(product)
        available = total - StockCalculationService.reserved(product)
        # stock_count = physical on-hand; available_count = sellable (on-hand − reserved);
        # in_stock reflects what's actually sellable.
        Product.objects.filter(pk=product.pk).update(
            stock_count=max(total, 0),
            available_count=max(available, 0),
            in_stock=available > 0,
        )
        # Each variant's in_stock now comes from its OWN bucket, across warehouses.
        # Previously every variant simply inherited the product's availability,
        # because there was nowhere to hold per-pack stock — so a shop with 40×500g
        # and 0×1kg advertised both as buyable, and the 1kg only failed at checkout.
        from catalog.models import ProductVariant

        buckets = StockCalculationService.by_variant(product)
        for v in ProductVariant.objects.filter(product=product):
            sellable = (buckets.get(v.id) or {}).get("available", 0) > 0
            if v.in_stock != sellable:
                ProductVariant.objects.filter(pk=v.pk).update(in_stock=sellable)
        if warehouse is not None:
            StockSyncService._refresh_alert(product, warehouse)

    @staticmethod
    def _refresh_alert(product, warehouse):
        """Raise/clear one alert per stock bucket in this warehouse."""
        for item in StockItem.objects.filter(product=product, warehouse=warehouse):
            StockSyncService._refresh_bucket_alert(product, warehouse, item)

    @staticmethod
    def _refresh_bucket_alert(product, warehouse, item):
        active = _scope_variant(
            LowStockAlert.objects.filter(
                product=product, warehouse=warehouse,
                status=LowStockAlert.Status.ACTIVE,
            ),
            item.variant,
        ).first()
        # `<=`, matching what the panels render as "Low" (storeops/views.py
        # `is_low = available <= threshold`). With `<` here, stock sitting EXACTLY
        # on the threshold showed a red Low badge in the table while no alert was
        # ever raised — the two surfaces contradicted each other at the boundary.
        if item.available <= item.low_stock_threshold:
            if active is None:
                LowStockAlert.objects.create(
                    product=product,
                    variant=item.variant,
                    warehouse=warehouse,
                    threshold=item.low_stock_threshold,
                    available_at_raise=item.available,
                )
                payload = {
                    "product": product.id, "warehouse": warehouse.id,
                    "variant": item.variant_id,
                    "available": item.available, "threshold": item.low_stock_threshold,
                }
                transaction.on_commit(lambda: record_event("low_stock", payload))
        elif active is not None:
            active.status = LowStockAlert.Status.CLEARED
            active.cleared_at = timezone.now()
            active.save(update_fields=["status", "cleared_at", "updated_at"])


# ── Integrity ────────────────────────────────────────────
def set_reorder_level(product, *, threshold, warehouse=None, variant=None):
    """Set a low-stock reorder threshold for one bucket and refresh its alert.

    Per pack, because reorder points are: you might want 20 of the 500g on the shelf
    but only 5 of the 5kg. `variant=None` on a product with variants sets the
    unallocated pool's threshold, which is harmless but rarely what's meant — the
    panels always pass a variant for a variant product."""
    warehouse = warehouse or default_warehouse()
    item, _ = StockItem.objects.get_or_create(
        product=product, variant=variant, warehouse=warehouse,
        defaults={"quantity": 0},
    )
    item.low_stock_threshold = max(0, int(threshold))
    item.save(update_fields=["low_stock_threshold", "updated_at"])
    StockSyncService._refresh_bucket_alert(product, warehouse, item)
    return item


def reconcile(product=None, warehouse=None):
    """Rebuild StockItem.quantity from the ledger — enforces the invariant
    Σ ledger.qty == StockItem.quantity. Returns the list of corrected rows."""
    items = StockItem.objects.all()
    if product is not None:
        items = items.filter(product=product)
    if warehouse is not None:
        items = items.filter(warehouse=warehouse)
    fixes = []
    with transaction.atomic():
        for item in items.select_for_update():
            # Per BUCKET, not per product×warehouse: summing the whole product's
            # ledger into each of its variant rows would write the product total
            # into every pack and multiply the shop's stock by its variant count.
            truth = (
                _scope_variant(
                    InventoryLedger.objects.filter(
                        product=item.product, warehouse=item.warehouse
                    ),
                    item.variant,
                ).aggregate(s=Sum("quantity"))["s"]
                or 0
            )
            if item.quantity != truth:
                fixes.append(
                    {"stock_item": item.pk, "was": item.quantity, "now": truth}
                )
                item.quantity = truth
                item.save(update_fields=["quantity", "updated_at"])
    return fixes


@transaction.atomic
def post_grn(grn: GRN, by=None) -> GRN:
    """Receive a draft GRN: one `grn` ledger row per line (creating batches when a
    batch_no/expiry is given), then mark the GRN posted and the PO received."""
    if grn.status == GRN.Status.POSTED:
        raise InventoryError("This GRN has already been posted.")
    total = ZERO
    for item in grn.items.select_related("product").all():
        batch = None
        if item.batch_no or item.expiry_date:
            batch, _ = StockBatch.objects.get_or_create(
                product=item.product,
                # The pack is part of the lot's identity too — 40×1kg and 40×500g
                # off one delivery note are different physical lots.
                variant=item.variant,
                warehouse=grn.warehouse,
                batch_no=item.batch_no or f"GRN{grn.pk}",
                # expiry is part of the lot's IDENTITY, not a default: the same
                # batch_no received with a different expiry is a different physical
                # lot. With expiry in `defaults` it was silently DISCARDED on a
                # re-used batch_no, merging new stock into the old lot's date —
                # which then drives FEFO picking and the expiry report wrong.
                expiry_date=item.expiry_date,
                defaults={"unit_cost": item.unit_cost},
            )
        InventoryService.post_movement(
            product=item.product,
            warehouse=grn.warehouse,
            type=Type.GRN,
            quantity=int(item.quantity),
            variant=item.variant,
            batch=batch,
            expiry_date=item.expiry_date,
            unit_cost=item.unit_cost,
            ref_type="grn",
            ref_id=grn.pk,
            note=f"GRN {grn.pk}",
            created_by=by,
        )
        total += Decimal(item.quantity) * item.unit_cost
    grn.status = GRN.Status.POSTED
    grn.total_cost = total
    grn.posted_at = timezone.now()
    grn.save(update_fields=["status", "total_cost", "posted_at", "updated_at"])

    if grn.purchase_order_id:
        po = grn.purchase_order
        # Roll received quantities up onto the PO lines (best-effort by product).
        for item in grn.items.all():
            line = po.items.filter(product=item.product).first()
            if line:
                line.received_quantity = F("received_quantity") + item.quantity
                line.save(update_fields=["received_quantity"])
        po.refresh_from_db()
        fully = all(li.received_quantity >= li.quantity for li in po.items.all())
        po.status = (
            PurchaseOrder.Status.RECEIVED if fully else PurchaseOrder.Status.PARTIAL
        )
        po.received_at = timezone.now()
        po.save(update_fields=["status", "received_at", "updated_at"])
    return grn


def write_off(product, *, type, quantity, warehouse=None, variant=None, batch=None,
              reason="", created_by=None) -> InventoryLedger:
    """Damage/expiry write-off → a negative ledger row of the given type. Scrapping
    is per pack: five crushed 1kg bags don't come off the 500g shelf. If a batch is
    given, its variant wins — the lot already knows which pack it is."""
    if type not in (Type.DAMAGE, Type.EXPIRY):
        raise InventoryError("write_off only handles damage/expiry.")
    if batch is not None and variant is None:
        variant = batch.variant
    return InventoryService.post_movement(
        product=product, variant=variant, warehouse=warehouse, type=type,
        quantity=-abs(int(quantity)), batch=batch, ref_type=type, note=reason,
        created_by=created_by,
    )


def weighted_average_cost(product, warehouse, variant=ANY_VARIANT) -> Decimal:
    """Weighted-average cost = Σ(incoming qty × unit_cost) / Σ(incoming qty) over costed
    inbound movements (purchase/grn/opening). Falls back to Product.price.

    Pass a variant to cost one pack. Blending a 5kg's cost with a 500g's produces a
    number that values neither, so valuation always scopes to the bucket."""
    rows = _scope_variant(
        InventoryLedger.objects.filter(
            product=product, warehouse=warehouse, unit_cost__isnull=False,
            quantity__gt=0,
        ),
        variant,
    ).values_list("quantity", "unit_cost")
    total_qty, total_cost = 0, ZERO
    for qty, cost in rows:
        total_qty += qty
        total_cost += Decimal(qty) * cost
    if total_qty > 0:
        return (total_cost / total_qty).quantize(Decimal("0.01"))
    return product.price


def stock_valuation(warehouse=None):
    """Inventory valuation = Σ on_hand × weighted-average cost, per product×warehouse."""
    rows = []
    items = StockItem.objects.select_related("product", "variant", "warehouse").filter(
        quantity__gt=0
    )
    if warehouse is not None:
        items = items.filter(warehouse=warehouse)
    for item in items:
        # One row per bucket, each costed at its own pack's average.
        unit_cost = weighted_average_cost(item.product, item.warehouse, item.variant)
        label = f" · {item.variant.label}" if item.variant_id else ""
        rows.append(
            {
                "product_id": str(item.product_id),
                "variant_id": str(item.variant_id) if item.variant_id else None,
                "name": f"{item.product.name}{label}",
                "warehouse_id": str(item.warehouse_id),
                "warehouse_name": item.warehouse.name,
                "quantity": item.quantity,
                "unit_cost": unit_cost,
                "value": (Decimal(item.quantity) * unit_cost).quantize(Decimal("0.01")),
            }
        )
    return rows
