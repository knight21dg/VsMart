# VS Mart — Financial Consistency Matrix

Which implementation each surface uses for each metric defined in
`FINANCIAL_DEFINITIONS.md`.

**Legend** — `✅ shared` consumes the authoritative implementation · `📺 display`
renders a server-supplied value without recomputing · `—` not shown on that surface ·
`⚠️` intentional difference, explained.

Authoritative modules:

| Module | Owns |
|---|---|
| `core/financials.py` | Revenue, order book, POS net, refunds, cash recovered, inventory valuation, customer lifetime revenue |
| `agents/earnings.py` | Agent earnings (delivery pay, collection pay, incentives, accrual vs payout) |
| `core/pricing.py` | Cart/order bill — GST, delivery fee, platform fee, discount, minimum order |
| `inventory/services.py` | Weighted-average cost, stock valuation |
| `payments/cashbook_services.py` | Cash in hand, deposits, handover verification |

---

## Metric × surface

| Metric | Source of truth | Admin | Store | Customer | Agent | Accounting | Reports | Export | Status |
|---|---|---|---|---|---|---|---|---|---|
| **Net Revenue** | `financials.net_revenue()` | ✅ shared | ✅ shared | — | — | ✅ shared | ✅ shared | ✅ shared | Consolidated |
| **Delivered Revenue** | same | ✅ | ✅ | — | — | ✅ | ✅ | ✅ | Consolidated |
| **POS Revenue** | `financials.pos_net()` | ✅ | ✅ | — | — | ✅ | — | — | Consolidated |
| **Refunds** | `financials.refunds()` | ✅ | ✅ | 📺 | — | ✅ | — | — | Consolidated |
| **Order Book** (placed/delivered/in-flight/returned/cancelled) | `financials.order_book()` | ✅ | ✅ | — | — | ✅ | ✅ | ✅ | Consolidated |
| **Customer Lifetime Revenue** | `financials.customer_lifetime_revenue()` | ✅ (CRM) | — | — | — | — | ✅ | ✅ | Consolidated |
| **COGS** | `accounting_views._wac_index()` + `_cogs_for()` | — | — | — | — | ✅ | — | — | Single impl |
| **Gross Profit / Margin** | `AccountingSummaryView` | — | — | — | — | ✅ | — | — | Single impl |
| **Cash Recovered** | `financials.cash_recovered()` | ✅ | ✅ | — | — | ✅ | ✅ | ✅ | Consolidated |
| **Collection Due** | `CashCollection.amount` | ✅ | ✅ | 📺 | 📺 | — | ✅ | ✅ | Distinct field, never conflated |
| **Cash In Hand** | `cashbook_services.cash_in_hand()` | ✅ | ✅ | — | ✅ | — | — | — | Already consolidated |
| **Agent Earnings (accrued)** | `agents/earnings.breakdown()` | ✅ | ✅ | — | ✅ | ✅ | ✅ | ✅ | Consolidated |
| **Agent Paid / Payable** | *no payout ledger* | `null` | `null` | — | `null` | `null` | `null` | `null` | Honestly unavailable |
| **Inventory Value** | `financials.inventory_valuation()` | ✅ + `costedPct` | ⚠️ see note | — | — | — | ✅ | ✅ | Consolidated |
| **Available / Reserved Stock** | `inventory.StockItem` | ✅ | ✅ | 📺 | — | — | ✅ | ✅ | Single source |
| **Outstanding Credit** | `credit.CreditAccount.outstanding` | ✅ | ✅ | 📺 | — | ✅ | ✅ | ✅ | Single field |
| **GST** | `core/pricing.compute_bill` | 📺 | 📺 | 📺 | — | 📺 | 📺 | 📺 | Server-only |
| **Delivery Fee** | `core/pricing` + `zones.effective_fees` | 📺 | 📺 | 📺 | — | — | — | — | Server-only |
| **Discount / Coupon** | `core/pricing` + `offers` | 📺 | 📺 | 📺 | — | — | — | — | Server-only |
| **Minimum Order** | `zones.effective_fees` | 📺 | 📺 | 📺 | — | — | — | — | Server-only |
| **Invoice totals** | copied from `Order` | 📺 | 📺 | 📺 | — | 📺 | — | — | Never recomputed |

---

## Notes on the entries that aren't a plain ✅

**Store inventory value (⚠️)** — `reports/executive.py::store_performance` uses
`inventory_value_at_cost(warehouse=…)`, the value-only wrapper, so it does not carry
`costedPct` into its table row. The valuation itself is identical to the dashboard's;
only the coverage figure is absent. Adding a column to that report is cosmetic and was
left alone.

**Agent Paid / Payable** — reported as `null` on every surface, not as `0`.
`DeliveryEarnings.released` is written `True` at delivery and never written `False`,
so it means *accrued*, not *paid*, and no payout record exists anywhere.
`agents/earnings.PAYOUTS_ARE_TRACKED` is the single switch that makes these computable
once a real payout ledger lands.

**Collection Due vs Cash Recovered** — deliberately two different metrics from two
different fields (`amount` vs `collected_amount`). They must never be substituted for
one another; a partially-recovered case has a due and a recovery that differ.

**Customer surfaces** — the app is `📺` throughout for money. The only client-side
arithmetic is an explicitly-flagged offline cart estimate (`CartSummary.isEstimate`),
which is replaced by the server's `/cart/quote` bill before checkout.

---

## Duplicate implementations removed by this pass

| Was | Where | Now |
|---|---|---|
| `Σ Order.total EXCLUDE cancelled` as revenue | `reports/executive.py::dashboard` | `financials.net_revenue()` |
| `Σ Order.total EXCLUDE cancelled/rejected` + POS as revenue | `storeops/services.py::store_dashboard` | `financials.net_revenue(store=…, warehouse=…)` |
| `Σ Order.total EXCLUDE cancelled` as customer lifetime value | `crm/services.py::_health` | `financials.customer_lifetime_revenue()` |
| `Σ CashCollection.amount` as recovery | `executive.dashboard`, `recovery_performance` (×3), `crm/services` (×3) | `financials.cash_recovered()` / `Sum(collected_amount)` |
| `Σ quantity × Product.price` as inventory value | `executive.dashboard`, `executive.store_performance` | `financials.inventory_valuation()` |
| `deliveries × ₹20 + collections × ₹30` as agent pay | `reports/accounting_views` | `agents/earnings.breakdown_all()` |
| `DeliveryEarnings + collections × ₹30` as agent pay | `agents/views.py` | `agents/earnings.breakdown()` |
| Hardcoded `'45'` struck-through delivery fee | `user_app cart_widgets.dart` | server's `deliveryFeeWaived` |

---

## Rule for new metrics

1. Check `FINANCIAL_DEFINITIONS.md`. If the metric is there, use the named
   implementation — do not write the aggregate again.
2. If it isn't there, define it there **first**, then implement it once in
   `core/financials.py` (or the owning service) and consume it everywhere.
3. Clients display; they do not decide. Client-side arithmetic is acceptable only as
   an explicitly-flagged estimate that a server value replaces before anything is
   committed.
4. Never infer a business event from a field name. Trace who writes the field and
   what real-world event causes it to change before treating it as state.
