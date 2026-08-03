"""Turn zone enforcement + store-scoped catalog visibility on/off — safely.

These two flags are what make the platform behave zone-by-zone:

  * ``zone_store_visibility`` — a customer sees only their serving store's catalog.
  * ``zone_enforcement``      — checkout is rejected outside every serviceable zone,
                                and orders/stock are bound to the serving store.

Enabling them while a serviceable zone has no store (or an empty store) would show
customers an empty storefront, so ``--on`` runs a pre-flight check and refuses unless
every active zone routes to an active store that carries at least one product. Map a
store's catalog first with ``manage.py map_store_catalog`` (pass ``--force`` to override).

    python manage.py zone_mode --status
    python manage.py zone_mode --on
    python manage.py zone_mode --off
"""
from django.core.management.base import BaseCommand

from stores.services import ENFORCEMENT_FLAG, VISIBILITY_FLAG, visible_product_ids
from system.models import FeatureFlag
from zones.models import Zone

FLAGS = (VISIBILITY_FLAG, ENFORCEMENT_FLAG)


class Command(BaseCommand):
    help = "Enable/disable zone enforcement + store-scoped visibility (with a safety check)."

    def add_arguments(self, parser):
        g = parser.add_mutually_exclusive_group(required=True)
        g.add_argument("--on", action="store_true", help="Enable both flags (after a safety check).")
        g.add_argument("--off", action="store_true", help="Disable both flags (global catalog).")
        g.add_argument("--status", action="store_true", help="Print current flag state and exit.")
        parser.add_argument("--force", action="store_true",
                            help="Enable even if some serviceable zones have empty/missing stores.")

    def _set(self, enabled):
        for key in FLAGS:
            FeatureFlag.objects.update_or_create(
                key=key, defaults={"enabled": enabled, "description": "Zone serviceability mode"}
            )

    def handle(self, *args, **o):
        if o["status"]:
            for key in FLAGS:
                ff = FeatureFlag.objects.filter(key=key).first()
                self.stdout.write(f"{key} = {'on' if (ff and ff.enabled) else 'off'}")
            return

        if o["off"]:
            self._set(False)
            self.stdout.write(self.style.SUCCESS(
                "Zone enforcement + visibility DISABLED — global catalog, no checkout geo-gate."
            ))
            return

        # --on : pre-flight — every active zone must route to an active, non-empty store.
        problems = []
        zones = list(Zone.objects.filter(is_active=True).select_related("store"))
        if not zones:
            problems.append("there are no active zones at all")
        for z in zones:
            store = z.store
            if store is None:
                problems.append(f"zone '{z.name}' has NO store assigned")
            elif store.status != "active":
                problems.append(f"zone '{z.name}' -> store '{store.code}' is inactive")
            elif not visible_product_ids(store):
                problems.append(
                    f"zone '{z.name}' -> store '{store.code}' carries 0 products "
                    f"(customers would see an empty storefront)"
                )

        if problems and not o["force"]:
            self.stderr.write(self.style.ERROR("Refusing to enable — fix these first (or pass --force):"))
            for p in problems:
                self.stderr.write(f"  - {p}")
            self.stderr.write(
                "Tip: map a store's catalog with "
                "`manage.py map_store_catalog --store <code> --all`."
            )
            return

        self._set(True)
        msg = "Zone enforcement + store-scoped visibility ENABLED."
        if problems:
            msg += f"  (forced past {len(problems)} warning(s))"
        self.stdout.write(self.style.SUCCESS(msg))
