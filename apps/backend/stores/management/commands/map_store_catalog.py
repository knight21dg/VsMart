"""Map products into a store's catalog so store-scoped visibility shows them.

When the ``zone_store_visibility`` flag is ON, a customer only sees the products
their serving store carries (StoreProduct rows, or — as a fallback — products with
stock in the store's warehouse). This command bulk-creates those StoreProduct rows
so a store has a real catalog before visibility is switched on.

Examples:
    python manage.py map_store_catalog --store STORE-BLR-01 --all
    python manage.py map_store_catalog --store 3 --in-stock
    python manage.py map_store_catalog --store STORE-BLR-01 --all --unavailable
"""
from django.core.management.base import BaseCommand, CommandError

from catalog.models import Product
from stores.models import Store, StoreProduct


class Command(BaseCommand):
    help = "Bulk-map products into a store's catalog (StoreProduct rows)."

    def add_arguments(self, parser):
        parser.add_argument("--store", required=True, help="Store code or numeric id.")
        scope = parser.add_mutually_exclusive_group()
        scope.add_argument("--all", action="store_true",
                           help="Map ALL active products into the store.")
        scope.add_argument("--in-stock", action="store_true",
                           help="Map only products with stock in the store warehouse (default).")
        parser.add_argument("--unavailable", action="store_true",
                            help="Create the rows as is_available=False (hidden) instead of available.")

    def handle(self, *args, **o):
        ident = o["store"]
        store = Store.objects.filter(code=ident).first()
        if store is None and str(ident).isdigit():
            store = Store.objects.filter(pk=int(ident)).first()
        if store is None:
            raise CommandError(f"No store with code/id '{ident}'.")

        available = not o["unavailable"]
        if o["all"]:
            pids = list(Product.objects.filter(is_active=True).values_list("id", flat=True))
        else:
            if not store.warehouse_id:
                raise CommandError(
                    f"Store {store.code} has no warehouse — use --all or attach a warehouse first."
                )
            from inventory.models import StockItem

            pids = list(
                StockItem.objects.filter(warehouse_id=store.warehouse_id, quantity__gt=0)
                .values_list("product_id", flat=True)
            )

        created = updated = 0
        for pid in set(pids):
            _, was_created = StoreProduct.objects.update_or_create(
                store=store, product_id=pid, defaults={"is_available": available}
            )
            created += int(was_created)
            updated += int(not was_created)

        self.stdout.write(self.style.SUCCESS(
            f"Mapped {len(set(pids))} product(s) into {store.code} "
            f"(available={available}; {created} new, {updated} updated)."
        ))
