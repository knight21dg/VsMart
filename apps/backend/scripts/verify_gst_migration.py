"""Pre/post-flight verification for the GST migrations.

Run this against the TARGET database immediately BEFORE applying the migrations
and again immediately AFTER, then diff the two outputs. It is deliberately
read-only — it never writes — so it is safe to run against production.

    python scripts/verify_gst_migration.py > gst_before.txt
    # ... apply migrations ...
    python scripts/verify_gst_migration.py > gst_after.txt
    diff gst_before.txt gst_after.txt

Run it as a plain script, NOT piped into ``manage.py shell`` — the interactive
console treats each blank line as end-of-block and mangles every loop in here.
Set ``DJANGO_SETTINGS_MODULE`` for the environment you are checking
(``config.settings.prod`` on the server).

What to expect in the diff:

  * ``products.fraction_like`` and ``order_items.fraction_like`` drop to **0**.
  * The per-value histograms shift from 0.0x to the matching whole percentages.
  * **Every other line must be identical** — row counts, NULL counts, zero
    counts, money totals, and the checksum over the columns the migration must
    not touch. Any change there means something went wrong; restore the snapshot.
"""
import os
import sys
from decimal import Decimal
from pathlib import Path

import django

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

# Pure-ASCII output, and force the encoding: a Windows console defaults to
# cp1252 and would crash on any non-ASCII byte mid-report.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

from django.db.models import Count, Sum  # noqa: E402

from catalog.models import Product  # noqa: E402
from core.pricing import GST_SLABS, gst_fraction_to_pct  # noqa: E402
from orders.models import Order, OrderItem  # noqa: E402
from siteconfig.models import PlatformConfig  # noqa: E402

ONE = Decimal("1")


def histogram(model, field):
    rows = (
        model.objects.values(field)
        .annotate(n=Count("id"))
        .order_by(field)
    )
    return [(str(r[field]), r["n"]) for r in rows]


def section(title):
    print()
    print(f"-- {title} " + "-" * max(0, 60 - len(title)))


print("VS MART - GST MIGRATION VERIFICATION (read-only)")

# -- products --
section("catalog.Product")
print(f"total_rows           : {Product.objects.count()}")
print(f"gst_null             : {Product.objects.filter(gst_rate__isnull=True).count()}")
print(f"gst_zero             : {Product.objects.filter(gst_rate=0).count()}")
print(
    f"fraction_like        : "
    f"{Product.objects.filter(gst_rate__gt=0, gst_rate__lt=ONE).count()}"
    "   <-- must be 0 AFTER"
)
print(f"gte_one              : {Product.objects.filter(gst_rate__gte=ONE).count()}")
print("histogram            :")
for value, n in histogram(Product, "gst_rate"):
    print(f"    {value:>10}  x{n}")

# Columns the migration must NOT touch. If any of these move, stop.
section("catalog.Product - untouched-column control totals")
agg = Product.objects.aggregate(
    price=Sum("price"), mrp=Sum("mrp"), credit=Sum("credit_price"),
    stock=Sum("stock_count"),
)
for key, value in sorted(agg.items()):
    print(f"sum_{key:<16}: {value}")
print(f"active_count         : {Product.objects.filter(is_active=True).count()}")
print(f"distinct_categories  : {Product.objects.values('category_id').distinct().count()}")

# -- order lines --
section("orders.OrderItem")
print(f"total_rows           : {OrderItem.objects.count()}")
print(f"gst_zero             : {OrderItem.objects.filter(gst_rate=0).count()}")
print(
    f"fraction_like        : "
    f"{OrderItem.objects.filter(gst_rate__gt=0, gst_rate__lt=ONE).count()}"
    "   <-- must be 0 AFTER"
)
print(f"gte_one              : {OrderItem.objects.filter(gst_rate__gte=ONE).count()}")
print("histogram            :")
for value, n in histogram(OrderItem, "gst_rate"):
    print(f"    {value:>10}  x{n}")

section("orders - MONEY control totals (must be IDENTICAL)")
money = Order.objects.aggregate(
    subtotal=Sum("subtotal"), gst=Sum("gst"), total=Sum("total"),
    discount=Sum("discount"),
)
for key, value in sorted(money.items()):
    print(f"orders_sum_{key:<10}: {value}")
line_money = OrderItem.objects.aggregate(price=Sum("price"), qty=Sum("quantity"))
for key, value in sorted(line_money.items()):
    print(f"lines_sum_{key:<11}: {value}")
print(f"orders_total_rows    : {Order.objects.count()}")

# -- platform config --
section("siteconfig.PlatformConfig")
cfg = PlatformConfig.load()
print(f"stored gst_rate      : {cfg.gst_rate}   (stays a FRACTION — not migrated)")
print(f"API would report     : {gst_fraction_to_pct(cfg.gst_rate)} %")

# -- slab conformance --
section("slab conformance (post-migration expectation)")
off_slab = [
    (p.id, p.name, p.gst_rate)
    for p in Product.objects.exclude(gst_rate__isnull=True)
    if p.gst_rate not in GST_SLABS
]
print(f"products_off_slab    : {len(off_slab)}   <-- should be 0 AFTER")
for pid, name, rate in off_slab[:20]:
    print(f"    #{pid} {name!r} -> {rate}")

print()
print("END")
