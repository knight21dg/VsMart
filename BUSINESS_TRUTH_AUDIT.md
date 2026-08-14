# VS Mart — Business Truth Audit

Hunt for numbers that are *technically valid but semantically wrong*. Follows the
accounting/reports rewrite; scope is everything that survived it.

Method: for each metric, trace `SOURCE → FILTER → TRANSFORMATION → AGGREGATION →
DISPLAY` and ask what business event makes the number true. Findings were confirmed
against **live prod data** by querying the production database directly, not inferred
from reading code.

Authoritative definitions: `FINANCIAL_DEFINITIONS.md`.

**8 defects found. 8 fixed. 1 limitation documented, not changed.**
One of the eight was introduced by the previous audit's own fix.

---

## Critical

### BT-001 — Admin dashboard booked revenue on order placement
- **Module:** `reports/executive.py::dashboard` — `revenueToday`, `revenueMtd`
- **Current formula:** `Σ Order.total WHERE status != cancelled`
- **Correct formula:** `delivered orders + POS net − refunds`
- **Root cause:** The accounting page was rewritten to recognise revenue on delivery;
  the dashboard was not. The two most-read screens on the platform then reported
  different revenue from the same data, and the dashboard's was the higher one. It
  also counted orders that later returned and omitted POS counter sales entirely.
- **Impact:** On prod's 30-day data the same defect in accounting overstated revenue
  **5.9×** (₹26,799.92 vs ₹4,561.00). The dashboard carried it unchanged.
- **Fix:** Both call `reports/definitions.py::net_revenue()`. One definition.
- **Test:** `DashboardConsistencyTests::test_dashboard_revenue_matches_accounting_revenue`,
  `::test_dashboard_does_not_book_in_flight_orders`, `::test_dashboard_revenue_includes_pos`
- **Status:** Fixed

### BT-002 — "Agent payable" was structurally always ₹0 *(introduced by the previous fix)*
- **Module:** `reports/accounting_views.py::AccountingSettlementsView`
- **Current formula:** `Σ DeliveryEarnings.total WHERE released = False`
- **Correct formula:** payable is **not computable** — report `null`
- **Root cause:** The previous audit replaced an invented flat rate with the real
  earnings ledger, reading `released` as a paid flag. It isn't.
  `delivery/services.py::compute_earnings` writes `released=True, released_at=now()`
  **at the moment of delivery**, and nothing in the codebase ever writes `False`.
  `released` means *accrued*, not *paid*. There is no payout ledger anywhere, so what
  has actually been handed to an agent is unknowable from the data.
- **Impact:** "Payable ₹0" on every agent forever — an unknown rendered as a
  reassuring fact, on the money the company owes its workers.
- **Fix:** Report `earned` (accrued, real). `paid` and `payable` are `null` with
  `payoutsTracked: false` and an explicit note. `PAYOUTS_ARE_TRACKED` in
  `agents/earnings.py` is the single switch when a payout ledger lands.
- **Test:** `SettlementTests::test_paid_and_payable_are_unavailable_not_zero`,
  `::test_released_flag_does_not_change_the_answer`
- **Status:** Fixed

### BT-003 — Agent pay computed two different ways
- **Module:** `agents/views.py::AgentEarningsView` vs `AccountingSettlementsView`
- **Current formula:** agent's own app: `DeliveryEarnings + collections × ₹30 +
  incentives`. Finance: `deliveries × ₹20 + collections × ₹30` (then, after the first
  fix, unreleased-only).
- **Correct formula:** one shared definition
- **Root cause:** Two independent formulas for the same money, in the earner's screen
  and the payer's screen. `PER_DELIVERY = 20` / `PER_COLLECTION = 30` were bare
  constants in a view — no config, no ledger, no business record.
- **Impact:** An agent and the person paying them could read different totals off the
  same data, with nothing in the system able to settle the disagreement.
- **Fix:** New `agents/earnings.py` is the single definition; both endpoints call it.
  The collection rate is preserved at ₹30 (removing it would silently cut agent-visible
  pay — a business decision, not mine) but is now a declared, overridable rate rather
  than a magic number.
- **Test:** `SettlementTests::test_finance_and_the_agent_app_report_the_same_total`
- **Status:** Fixed

---

## High

### BT-004 — Inventory valued at selling price
- **Module:** `reports/executive.py` — `dashboard.inventoryValue`, `store_performance`
- **Current formula:** `Σ quantity × Product.price`
- **Correct formula:** `Σ quantity × weighted-average cost`
- **Root cause:** Exactly the trap §5 of the brief names — `Product.price` silently
  becoming inventory cost. `inventory/services.py::stock_valuation` already values at
  WAC per variant; nothing used it.
- **Impact:** Overstates the inventory holding by the **entire margin**, on both the
  executive dashboard and every row of store performance. Feeds any balance-sheet
  reading of stock.
- **Fix:** Both call `definitions.inventory_valuation()`.
- **Caveat found while verifying the fix:** `weighted_average_cost` **falls back to
  `Product.price`** when a product×warehouse never received costed stock, so "value at
  cost" is only partly at cost. Measured on prod: **67% genuinely costed
  (₹766,200)**, 33% still priced at retail (₹377,844). Rather than let that ride as a
  silent overstatement, the valuation now returns `costedPct` alongside the value and
  the dashboard publishes `inventoryValueCostedPct`.
- **Test:** `DashboardConsistencyTests::test_inventory_is_valued_at_cost_not_selling_price`,
  `::test_store_performance_values_inventory_at_cost`,
  `InventoryValuationTests` (costed / uncosted / mixed coverage)
- **Status:** Fixed

### BT-005 — Agent earnings accrual counted as cash outflow *(introduced by the previous fix)*
- **Module:** `reports/accounting_views.py::AccountingCashflowView`
- **Current formula:** outflow included `DeliveryEarnings WHERE released=True` by `released_at`
- **Correct formula:** exclude entirely — no cash event exists
- **Root cause:** Same accrued/paid confusion as BT-002. `released_at` is stamped on
  delivery completion, so this booked money as leaving the business at the moment a
  parcel was handed over, when nothing moved.
- **Impact:** Overstated outflow and understated net cash every single day.
- **Fix:** Cash flow is now settled customer payments and recovered cash in; posted
  GRNs and paid refunds out. Agent earnings re-enter only when a payout ledger exists.
- **Test:** `CashflowTests` (existing legs) + the note asserted in the response
- **Status:** Fixed

### BT-006 — Collections reported the target, not the recovery
- **Module:** `reports/executive.py` — `dashboard.collectionsToday/Mtd`,
  `recovery_performance` summary, trend and agent ranking
- **Current formula:** `Σ CashCollection.amount WHERE status = 'collected'`
- **Correct formula:** `Σ collected_amount` over `collected` **and** `partially_collected`
- **Root cause:** `amount` is what we set out to recover; `collected_amount` is what
  came back. The same Due-vs-Recovered confusion fixed in the reports layer survived
  in five more places, which additionally dropped every partial collection by
  filtering `status='collected'`.
- **Impact:** A ₹1,000 case that recovered ₹400 reported as ₹1,000 — or as ₹0 if
  partially collected. **Latent on today's prod data** (no partial collections exist
  yet, and every collected row has `collected_amount == amount`), so it would have
  begun lying the day the first partial recovery happened.
- **Fix:** All five sites use `collected_amount` and include partials.
- **Test:** `DashboardConsistencyTests::test_dashboard_collections_report_recovery_not_target`,
  `::test_recovery_report_uses_recovered_amount`
- **Status:** Fixed

---

## Medium

### BT-007 — A test fixture encoded the wrong definition
- **Module:** `reports/tests.py::ReportsBaseData`
- **Root cause:** The fixture created a `collected` `CashCollection` with `amount=1500`
  and **no `collected_amount`**, then asserted recovery was ₹1,500. It passed only
  because the implementation summed the target. Fixing BT-006 made it fail — correctly.
- **Impact:** A green test actively defending a wrong business rule. Exactly the
  "tests too weak to fail" case in §34.
- **Fix:** Fixture now sets `collected_amount`, as the real collect service does.
  Verified against prod: all 5 collected rows have it populated (`null=False,
  default=0`), so no legacy-data fallback is needed.
- **Status:** Fixed

### BT-008 — Report row ceiling was invisible
- **Module:** `reports/builders.py`
- **Root cause:** The previous fix removed the silent `[:200]`/`[:500]` truncation but
  left the queries unbounded, trading a silent wrong answer for an unbounded scan.
- **Fix:** `MAX_ROWS = 20000` with `_capped()` / `_cap_note()` — when the ceiling is
  hit the report **says so in its title and summary**, which carries into the CSV,
  Excel and PDF export rather than handing over a silent prefix.
- **Test:** `ReportBuilderTests::test_hitting_the_row_ceiling_is_announced_not_hidden`,
  `::test_no_cap_notice_when_everything_fits`
- **Status:** Fixed

---

## Verified correct — checked, no defect

| Area | Checked | Result |
|---|---|---|
| **Cross-store isolation** | every `/store/*` view | Store scope comes from `request.store`, derived server-side from `StoreStaff` membership. **No storeops view reads a store id from the request**, so a client-supplied `store_id` cannot override authorization. |
| **GST units** | `core/pricing.py`, migrations, serializers | One documented rule — API/operator speak percentages, maths uses fractions, conversion only via the two helpers. Rates restricted to statutory slabs, with a "you meant a percentage" hint for `0 < r < 1`. No 18 → 1800/0.18/0.0018 path found. |
| **Invoice vs order GST** | `billing/` | Invoices copy `Order.gst`; totals cannot disagree. |
| **Money arithmetic** | pricing, POS, returns | `Decimal` throughout with a single `q()` quantizer (`ROUND_HALF_UP`, 2dp). No float money found in backend calculations. |
| **Client-side money** | checkout | Server-authoritative: `compute_bill` is the only source of order totals. |
| **Refund double-deduction** | accounting summary | Returned orders are excluded by `status`; partial refunds deducted via `ReturnRequest.refund_amount`. The same money cannot reduce revenue twice. |
| **Cash inflow double-count** | cash flow | `CashCollection.payment` FK means recovery books a `repayment` Payment; collections are excluded where already booked as settled. `handover` never counts as inflow. |
| **Report filters** | all six builders | `date_from`/`date_to`/`store` reach the queryset and change the result. Export sends the same params as the screen. |
| **POS revenue** | accounting, store dashboard | Sales less returns, voids excluded, counted once. The store dashboard already included POS (fixed earlier); accounting now does too. |

---

## Documented limitation — not changed

### BT-L1 — GST is applied at one platform-wide rate
`Product.gst_rate` / `OrderItem.gst_rate` hold **per-item** statutory slabs, but
`core/pricing.py::compute_bill` applies a single `PlatformConfig.gst_rate` to the whole
subtotal. A cart mixing 0% staples with 18% goods is taxed at one blended rate.

There is **no internal contradiction** — invoices copy `Order.gst`, so invoice and
order always agree — but the tax is not statutorily itemised per line.

Moving to per-line GST changes what customers are charged and what appears on a tax
invoice. That is a business and compliance decision, so it is flagged here rather than
changed unilaterally. The per-item column already exists, so the change is mechanical
once the business confirms it.

---

### BT-L2 — Net revenue can be negative in a period
A window containing refunds but no deliveries reports negative net revenue. Prod's
month-to-date reads **−₹808**: no delivered orders yet this month, one ₹808 refund
resolved. This is correct accrual behaviour — a refund lands in the period it is
resolved, and restating the closed period it originally sold in would be worse — but
it is surprising on a dashboard tile and worth knowing before someone reports it as a
bug.

---

## Remaining gaps

Stated plainly:

1. **No agent payout ledger exists.** Until one does, amounts owed to agents cannot be
   computed and are correctly reported as unknown. This is a missing feature, not a
   defect — but it means the platform currently has no record of paying anyone.
2. **COGS coverage on prod is 0%.** No delivered unit has a costed inbound movement, so
   margin is honestly unavailable. It becomes computable as soon as goods are received
   with unit costs recorded (posted GRNs).
3. **Per-line GST** — see BT-L1.
4. **`Product.stock_count` still exists** and is still written by some flows. It is no
   longer read by any financial or operational report audited here, but it was not
   removed — deleting an intentionally-maintained denormalisation is out of scope for
   an accuracy audit.
