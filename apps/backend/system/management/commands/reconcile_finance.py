"""Audit core financial invariants across the platform — an operational safety net.

    python manage.py reconcile_finance          # report only (PASS / ERROR list)
    python manage.py reconcile_finance --fix     # also repair credit + inventory caches

Checks (all derived-vs-cache or limit invariants the services enforce on write):
  • Credit:    account.outstanding == max(Σ ledger.amount, 0)
  • Inventory: StockItem.quantity  == Σ ledger.qty   (per product×warehouse)
  • Coupons:   redemptions         <= usage_limit
  • Orphans:   orders still RESERVED + pending beyond the reservation TTL

Exits non-zero on any mismatch so it can gate a release / run from cron. Output is
ASCII-only (Windows consoles are cp1252). Gateway/payment-vs-bank reconciliation is
out of scope until a live gateway is wired (see QA_TRACKER RC-06).
"""
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db.models import Sum
from django.utils import timezone

ZERO = Decimal("0.00")


class Command(BaseCommand):
    help = "Audit financial invariants (credit ledger, inventory ledger, coupon limits, orphans)."

    def add_arguments(self, parser):
        parser.add_argument("--fix", action="store_true",
                            help="Repair credit + inventory cache drift (re-derive from ledgers).")

    def handle(self, *args, **o):
        from credit.models import CreditAccount
        from inventory.models import InventoryLedger, StockItem
        from offers.models import Coupon
        from orders.models import Order

        errors = []

        # 1. Credit: outstanding == max(Σ ledger, 0)
        for acct in CreditAccount.objects.all():
            truth = max(acct.entries.aggregate(s=Sum("amount"))["s"] or ZERO, ZERO)
            if truth != acct.outstanding:
                errors.append(
                    f"Credit account user={acct.user_id}: outstanding {acct.outstanding} "
                    f"!= ledger {truth}")

        # 2. Inventory: StockItem.quantity == Sum(ledger.qty) PER BUCKET.
        #
        # Scoped by variant, like `inventory.services.reconcile` already is. Without
        # that this compares one variant's cache against the whole product's ledger,
        # so any product with variants reports a permanent false ERROR — and a check
        # that is always red is a check nobody reads. Prod showed exactly this:
        # variant 5 held 993/993 and the variant-NULL bucket 0/0, both correct, while
        # the command reported "cache 0 != ledger 993".
        from inventory.services import _scope_variant

        for item in StockItem.objects.select_related("product", "warehouse", "variant"):
            truth = _scope_variant(
                InventoryLedger.objects.filter(
                    product=item.product, warehouse=item.warehouse
                ),
                item.variant,
            ).aggregate(s=Sum("quantity"))["s"] or 0
            if truth != item.quantity:
                errors.append(
                    f"Stock product={item.product_id} variant={item.variant_id} "
                    f"wh={item.warehouse_id}: cache {item.quantity} != ledger {truth}")

        # 3. Coupons: redemptions <= usage_limit
        for c in Coupon.objects.filter(usage_limit__isnull=False):
            used = c.redemptions.count()
            if used > c.usage_limit:
                errors.append(
                    f"Coupon {c.code}: {used} redemptions > usage_limit {c.usage_limit}")

        # 4. Orphan reservations: RESERVED + pending well past the TTL (should be released)
        from django.conf import settings

        ttl = int(getattr(settings, "RESERVATION_TTL_MINUTES", 30))
        cutoff = timezone.now() - timezone.timedelta(minutes=ttl * 2)
        orphans = Order.objects.filter(
            stock_state="reserved", status="pending", placed_at__lt=cutoff
        ).count()
        if orphans:
            errors.append(
                f"{orphans} orphan reservation(s): RESERVED + pending older than "
                f"{ttl * 2}m (TTL sweep should have released them)")

        # ── report ──
        if errors:
            for e in errors:
                self.stderr.write(self.style.ERROR("ERROR  " + e))
            self.stderr.write(self.style.ERROR(f"\nFAIL - {len(errors)} issue(s) found."))
            if o["fix"]:
                self._fix()
            raise SystemExit(1)
        self.stdout.write(self.style.SUCCESS("PASS - all financial invariants hold."))

    def _fix(self):
        from credit.models import CreditAccount
        from credit.services import reconcile as credit_reconcile
        from inventory.services import reconcile as inventory_reconcile

        self.stdout.write("Repairing caches from ledgers...")
        for acct in CreditAccount.objects.all():
            credit_reconcile(acct)
        fixes = inventory_reconcile()
        self.stdout.write(self.style.SUCCESS(
            f"Repaired credit caches + {len(fixes)} inventory cache row(s)."))
