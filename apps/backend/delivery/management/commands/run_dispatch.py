"""Periodic dispatch tick — run the assignment engine for every active store.

Schedule this every ~2 minutes (cron / systemd timer) so ready orders get batched
and assigned without a human clicking "Auto Assign":

    */2 * * * * python manage.py run_dispatch
"""
from django.core.management.base import BaseCommand

from delivery import assignment_engine as engine
from stores.models import Store


class Command(BaseCommand):
    help = "Run the delivery assignment engine for all active stores."

    def add_arguments(self, parser):
        parser.add_argument("--store", help="Limit to one store code.")

    def handle(self, *args, **opts):
        stores = Store.objects.filter(status="active")
        if opts.get("store"):
            stores = stores.filter(code=opts["store"])
        totals = {"batches": 0, "assigned": 0, "queued": 0, "reassigned": 0}
        for store in stores:
            # SLA guard first: reclaim batches stuck un-picked-up, then plan fresh.
            totals["reassigned"] += engine.sweep_stale_batches(store)
            r = engine.run_auto_assign(store)
            for k in ("batches", "assigned", "queued"):
                totals[k] += r.get(k, 0)
            if r.get("orders"):
                self.stdout.write(f"{store.code}: {r}")

        # Nothing used to retry work that found no agent when it was raised: a
        # collection or return pickup created while every agent was off duty
        # stayed unassigned forever, no matter how many came on duty later.
        # run_auto_assign can't cover it — it returns early when a store has no
        # ready delivery orders, and only merges collections within 1.5 km of a
        # delivery stop.
        from cashcollections.services import assign_orphan_collections
        from returns.pickup_services import assign_orphan_pickups

        totals["orphanCollections"] = assign_orphan_collections()
        totals["orphanReturnPickups"] = assign_orphan_pickups()
        self.stdout.write(self.style.SUCCESS(f"dispatch tick done: {totals}"))
