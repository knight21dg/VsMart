"""Delete company-wide (global) products so every product belongs to a store.

A "global" product is one with ``origin_store IS NULL`` - the shared company
catalog that any store may carry. This command removes them.

**This is destructive and irreversible.** It is dry-run by default and prints the
full cascade before touching anything; ``--apply`` is required to execute.

Things worth understanding before you run it:

* ``InventoryLedger.product`` and ``POSTransactionItem.product`` are ``PROTECT``.
  A product that ever had a stock movement or was sold at a till CANNOT be
  deleted - Django raises ``ProtectedError`` and, in a single transaction, nothing
  at all would be removed. In practice the inventory ledger blocks the large
  majority. Those products are reported and skipped, or taken out of the catalog
  with ``--deactivate-protected``.
* ``StockItem``, ``StockBatch``, barcodes, gallery rows, variants, ``StoreProduct``
  links, reviews and cart lines all ``CASCADE`` - deleting a product destroys its
  stock records and their history.
* ``OrderItem.product`` is ``SET_NULL``. Past orders survive (name and price are
  snapshotted on the line) but lose their link back to the product.

Usage::

    python manage.py purge_global_products                    # dry run (default)
    python manage.py purge_global_products --deactivate-protected
    python manage.py purge_global_products --apply            # execute - irreversible
"""
from django.contrib.admin.utils import NestedObjects
from django.core.management.base import BaseCommand
from django.db import router, transaction

from catalog.models import Product


class Command(BaseCommand):
    help = "Delete global (origin_store IS NULL) products. Dry run unless --apply."

    def add_arguments(self, parser):
        parser.add_argument(
            "--apply", action="store_true",
            help="Actually delete. Without this the command only reports.",
        )
        parser.add_argument(
            "--deactivate-protected", action="store_true",
            help="Products that can't be deleted (protected by the inventory "
                 "ledger or a till sale) are set is_active=False instead, so they "
                 "leave the catalog without losing their history.",
        )

    def handle(self, *args, **options):
        apply = options["apply"]
        globals_qs = Product.objects.filter(origin_store__isnull=True)
        total = globals_qs.count()

        if not total:
            self.stdout.write(self.style.SUCCESS("No global products - nothing to do."))
            return

        self.stdout.write(f"Global products (origin_store IS NULL): {total}")

        # Django's own dependency collector: the authoritative answer on what a
        # delete would cascade to, and what blocks it.
        collector = NestedObjects(using=router.db_for_write(Product))
        collector.collect(list(globals_qs))

        # A PROTECT relation on any child blocks its parent product. Track WHICH
        # model does the blocking - the operator needs to know whether it's the
        # inventory ledger (by far the most common) or a till sale, because the
        # remedy differs.
        blocked_ids = {obj.pk for obj in collector.protected if isinstance(obj, Product)}
        blockers_by_model: dict[str, set] = {}
        for obj in collector.protected:
            product_id = getattr(obj, "product_id", None)
            if product_id is None:
                continue
            blocked_ids.add(product_id)
            blockers_by_model.setdefault(type(obj).__name__, set()).add(product_id)

        deletable = globals_qs.exclude(pk__in=blocked_ids)
        deletable_count = deletable.count()

        self.stdout.write("")
        self.stdout.write("Would DELETE, by model:")
        for model, instances in sorted(
            collector.data.items(), key=lambda kv: kv[0].__name__
        ):
            self.stdout.write(f"  {model.__name__:<28} {len(instances)}")

        if blocked_ids:
            self.stdout.write("")
            self.stdout.write(self.style.WARNING(
                f"BLOCKED by PROTECT: {len(blocked_ids)} product(s) CANNOT be deleted."
            ))
            for model_name, ids in sorted(blockers_by_model.items()):
                self.stdout.write(f"    {model_name:<22} blocks {len(ids)} product(s)")
            self.stdout.write(
                "    Those relations are PROTECT deliberately: InventoryLedger is the"
            )
            self.stdout.write(
                "    append-only stock audit record, POSTransactionItem is a real till"
            )
            self.stdout.write(
                "    sale. Deleting through them would destroy accounting history."
            )
            self.stdout.write(
                "    Use --deactivate-protected to remove them from the catalog"
            )
            self.stdout.write(
                "    (is_active=False) while keeping that history intact."
            )

        # Orders keep their line items (SET_NULL) but lose the product link.
        from orders.models import OrderItem

        affected_orders = (
            OrderItem.objects.filter(product__in=deletable)
            .values("order").distinct().count()
        )
        if affected_orders:
            self.stdout.write("")
            self.stdout.write(self.style.WARNING(
                f"{affected_orders} past order(s) will lose the product link on at "
                "least one line (the line itself survives - name/price are "
                "snapshotted)."
            ))

        remaining = Product.objects.exclude(pk__in=deletable.values("pk")).count()
        self.stdout.write("")
        self.stdout.write(
            f"Deletable now: {deletable_count} | Catalog left afterwards: {remaining} "
            f"product(s)"
        )

        if not apply:
            self.stdout.write("")
            self.stdout.write(self.style.NOTICE(
                "DRY RUN - nothing was changed. Re-run with --apply to execute."
            ))
            return

        with transaction.atomic():
            deactivated = 0
            if options["deactivate_protected"] and blocked_ids:
                deactivated = Product.objects.filter(
                    pk__in=blocked_ids, is_active=True
                ).update(is_active=False)
            # Re-evaluate inside the transaction; delete only what can go.
            deleted_count, per_model = Product.objects.filter(
                origin_store__isnull=True
            ).exclude(pk__in=blocked_ids).delete()

        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS(
            f"Deleted {per_model.get('catalog.Product', 0)} product(s) "
            f"({deleted_count} rows across all cascaded tables)."
        ))
        if deactivated:
            self.stdout.write(self.style.SUCCESS(
                f"Deactivated {deactivated} protected product(s) - they are out of "
                f"the catalog but their stock/POS history is intact."
            ))
        if blocked_ids and not options["deactivate_protected"]:
            self.stdout.write(self.style.WARNING(
                f"{len(blocked_ids)} product(s) remain because deleting them would "
                "destroy inventory-ledger or POS history. Re-run with "
                "--deactivate-protected to take them out of the catalog instead."
            ))
