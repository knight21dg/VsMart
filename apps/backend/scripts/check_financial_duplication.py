"""Static sweep for duplicate business-metric implementations.

Three audits in a row found the same root cause: the dashboard, accounting, the
store panel, CRM, the agent app and the report builders had each grown their own
arithmetic for a metric `FINANCIAL_DEFINITIONS.md` defines. Every one returned a
plausible number, so nothing looked broken until someone compared two screens.

Behavioural tests catch a *wrong* number. They cannot catch a *second* number that
happens to agree today and will drift tomorrow. This does — it makes a new duplicate
a code-review failure rather than something QA finds months later.

    python scripts/check_financial_duplication.py          # report
    python scripts/check_financial_duplication.py --list   # every site, classified

Exit code 1 when an unclassified financial aggregate appears outside an
authoritative module. Fix by one of:

  1. Call the canonical implementation instead (almost always right), or
  2. Add the site to CLASSIFIED below **with a reason** if it is genuinely a
     different metric, a per-module ledger sum, or presentation-only.

Run from `apps/backend`. Wired into the test suite as
`core.test_financial_duplication`, so CI enforces it.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# The classification reasons contain em-dashes; a cp1252 console would crash the
# checker on its own output rather than reporting the finding.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parent.parent

#: Modules that are ALLOWED to implement a metric — the source-of-truth layer named
#: in FINANCIAL_DEFINITIONS.md. Everything else should be calling into these.
AUTHORITATIVE = {
    "core/financials.py",          # revenue, order book, POS net, refunds, cash recovered, inventory value
    "core/pricing.py",             # cart/order bill: GST, delivery, platform fee, discount
    "agents/earnings.py",          # agent pay
    "inventory/services.py",       # weighted-average cost, stock valuation
    "payments/cashbook_services.py",  # cash in hand, deposits, handover
}

#: Not application code — no business meaning to duplicate.
SKIP_DIRS = ("migrations", "__pycache__", ".venv", "docs")
SKIP_FILE_RE = re.compile(r"(^|/)(tests?|test_[^/]+|conftest)\.py$|(^|/)scripts/")

#: Money-ish aggregates. Deliberately broad — a false positive costs one line in
#: CLASSIFIED, a false negative costs another audit.
MONEY_FIELDS = (
    "total", "amount", "price", "cost", "subtotal", "gst", "tax", "discount",
    "collected_amount", "refund_amount", "outstanding", "credit_limit",
    "total_cost", "unit_cost", "platform_fee", "delivery_fee", "credit_used",
    "payments", "closing_balance", "verified_amount", "opening_cash",
)
AGG_RE = re.compile(
    r"\b(Sum|Avg|Max|Min)\(\s*[\"'](" + "|".join(MONEY_FIELDS) + r")\b"
)
#: `F("price") * F("quantity")`-style line maths.
EXPR_RE = re.compile(r'F\(\s*["\'](?:price|unit_price|quantity|cost|unit_cost)')

#: Every known site, with what it is. The point of this file is that adding a row
#: here requires stating WHY — which is the review conversation that was missing.
#:
#: A = authoritative (handled by module allowlist, never listed here)
#: B = presentation of an authoritative value
#: C = per-module ledger/domain sum — a different metric, not a platform KPI
#: D = duplicate  → must be fixed, never classified
CLASSIFIED: dict[str, str] = {
    # ── C: per-module ledger and domain sums ────────────────────────────────
    "accounting/posting.py": "C — double-entry journal lines; the GL is its own ledger",
    "accounting/services.py": "C — journal/trial-balance sums over JournalLine",
    "billing/services.py": "C — invoice/receipt line totals copied from the order",
    "cart/services.py": "C — cart line subtotal; the bill itself comes from core/pricing",
    "cashcollections/services.py": "C — collection state machine; writes collected_amount",
    "cashcollections/admin_views.py": "C — collections command-centre: due vs recovered are its own domain",
    "credit/services.py": "C — credit ledger entries (append-only) and statement balances",
    "credit/views.py": "C — credit account balance presentation",
    "delivery/services.py": "C — per-task earnings computation; agents/earnings AGGREGATES these",
    "delivery/views.py": "C — cash-in-hand via payments.cashbook_services.undeposited_collections",
    "inventory/ap_services.py": "C — accounts-payable: supplier invoice vs payments",
    "inventory/admin_analytics.py": "C — inventory analytics; costs via inventory/services helpers",
    "inventory/views.py": "C — stock quantity aggregates, not money",
    "inventory/serializers.py": "C — stock quantity presentation",
    "loyalty/services.py": "C — points ledger; POINTS_PER_RUPEE is the documented conversion",
    "offers/models.py": "C — coupon/offer value fields",
    "offers/admin_views.py": "C — banner/coupon analytics (impressions, redemptions)",
    "orders/services.py": "C — order creation; totals come from core/pricing.compute_bill",
    "orders/serializers.py": "C — order payment-applied sum for balance display",
    "pos/services.py": "C — POS session/day-closing ledger; owns till reconciliation",
    "pos/views.py": "C — POS transaction presentation",
    "payments/services.py": "C — payment settlement ledger",
    "payments/admin_views.py": "C — payments ledger module: sums Payment rows by status",
    "payments/pos_link_services.py": "C — gateway payment-link settlement",
    "referrals/services.py": "C — referral reward ledger",
    "storeops/pos_views.py": "C — store POS endpoints; delegate to pos/services",
    "storeops/extra_views.py": "C — store reports; order/product line sums scoped to one store",
    "storeops/dispatch_views.py": "C — dispatch batch metrics, not money",
    "storeops/catalog_views.py": "C — store catalog stock presentation",
    "support/views.py": "C — support metrics, not money",
    "zones/views.py": "C — zone order/revenue presentation for the zone detail page",
    "zones/services.py": "C — zone fee resolution feeding core/pricing",
    "system/views.py": "C — platform counters, not money",
    "crm/views.py": "C — CRM presentation of crm/services values",
    "ops/views.py": (
        "C — internal ops console. Its 'revenue' is deliberately the platform TAKE "
        "(platform_fee + delivery_fee), a different metric from GMV/net revenue; "
        "'gmv_today' is explicitly named GMV. Distinct names, distinct meanings."
    ),
    "orders/admin_service.py": "C — order-module aggregates (AOV, status mix) for the orders console",
    "agents/history_views.py": "C — agent's own collection history via collected_amount",
    "agents/services.py": "C — agent performance counters, not money",
    "credit/statement_services.py": (
        "C — monthly statement built from CreditLedgerEntry by entry TYPE "
        "(purchase/repayment/fee); the credit ledger is its own source of truth"
    ),
    "system/management/commands/reconcile_finance.py": (
        "C — invariant CHECKER, not a metric: re-derives credit.outstanding and "
        "StockItem.quantity from their ledgers to catch cache drift. Exactly the "
        "denormalisation safety net FINANCIAL_DEFINITIONS.md asks for."
    ),
    "reports/executive.py": "B — BI builders; revenue/collections/inventory now call core/financials",
    "reports/accounting_views.py": "B — accounting API; owns COGS, delegates the rest to core/financials",
    "reports/builders.py": "B — report builders; windowed sums for display, totals in `summary`",
    "crm/services.py": "B — customer 360; revenue/collections now call core/financials",
    "storeops/services.py": "B — store dashboard; revenue now calls core/financials.net_revenue",
    "agents/views.py": "B — agent earnings endpoint; delegates to agents/earnings.breakdown",
}


def iter_files():
    for path in sorted(ROOT.rglob("*.py")):
        rel = path.relative_to(ROOT).as_posix()
        if any(f"/{d}/" in f"/{rel}" for d in SKIP_DIRS):
            continue
        if SKIP_FILE_RE.search(rel):
            continue
        yield rel, path


def scan():
    hits: dict[str, list[tuple[int, str]]] = {}
    for rel, path in iter_files():
        if rel in AUTHORITATIVE:
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        found = [
            (n, ln.strip())
            for n, ln in enumerate(lines, 1)
            if AGG_RE.search(ln) or EXPR_RE.search(ln)
        ]
        if found:
            hits[rel] = found
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="print every site with its class")
    args = ap.parse_args()

    hits = scan()
    unclassified = {f: v for f, v in hits.items() if f not in CLASSIFIED}

    total = sum(len(v) for v in hits.values())
    print(f"{total} financial aggregate(s) across {len(hits)} file(s) "
          f"outside the {len(AUTHORITATIVE)} authoritative modules.")

    if args.list:
        for rel in sorted(hits):
            print(f"\n{rel}  [{CLASSIFIED.get(rel, 'UNCLASSIFIED')}]")
            for n, ln in hits[rel]:
                print(f"    {n}: {ln[:110]}")

    if unclassified:
        print(f"\n✗ {len(unclassified)} file(s) NOT classified:\n")
        for rel in sorted(unclassified):
            print(f"  {rel}")
            for n, ln in unclassified[rel][:3]:
                print(f"      {n}: {ln[:100]}")
        print(
            "\nEach must either call the canonical implementation "
            "(see FINANCIAL_DEFINITIONS.md) or be added to CLASSIFIED with a reason."
        )
        return 1

    print(f"OK: all {len(hits)} file(s) classified; no unexplained duplicate implementations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
