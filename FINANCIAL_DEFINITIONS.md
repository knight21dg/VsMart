# VS Mart — Authoritative Financial Definitions

Every definition below is **derived from the existing implementation and data model**,
not invented. Where the data cannot support a figure, that is stated rather than
approximated.

Canonical implementations live in:

- `apps/backend/reports/definitions.py` — revenue, cash recovered, inventory value
- `apps/backend/agents/earnings.py` — agent pay
- `apps/backend/core/pricing.py` — cart/order bill computation
- `apps/backend/inventory/services.py` — weighted-average cost, stock valuation

Any screen showing one of these numbers must call the canonical implementation. Two
screens computing the same word independently is how every defect in this audit began.

---

## Revenue

| Term | Definition | Source |
|---|---|---|
| **Gross Ordered (GMV)** | `Σ Order.total` for orders placed in the window, excluding `cancelled`. Includes orders not yet delivered. **Not revenue.** | `Order.placed_at`, `Order.total` |
| **Delivered Revenue** | `Σ Order.total` where `status = delivered`. | `Order.status` |
| **POS Net** | `Σ POSTransaction.total` where `type=sale` minus `type=return`, excluding `is_voided`. | `pos.POSTransaction` |
| **Refunds** | `Σ ReturnRequest.refund_amount` where `status = refunded`, by `resolved_at`. | `returns.ReturnRequest` |
| **Net Revenue** | `Delivered Revenue + POS Net − Refunds` | `definitions.net_revenue()` |

**Revenue is recognised on delivery, not on placement.** An order that is `pending`,
`confirmed`, `ready_for_dispatch`, `out_for_delivery` or any other non-terminal state
is *in flight* and contributes to the order book, never to revenue.

`returned` orders are excluded from revenue by status. Partial returns against orders
that *did* deliver are removed via the Refunds line, so the same money is never
deducted twice.

**Window semantics:** the window filters `placed_at` for orders and `created_at` for
POS, both inclusive at each end (`date_to` includes everything up to 23:59:59.999999
local time).

---

## Cost & margin

| Term | Definition | Source |
|---|---|---|
| **Weighted-Average Cost (WAC)** | `Σ(inbound qty × unit_cost) / Σ(inbound qty)` per `(product, variant)`, over costed inbound ledger rows only. | `InventoryLedger.unit_cost` |
| **COGS** | `Σ (delivered order line qty × WAC)` for lines whose `(product, variant)` has a real costed inbound. Uncosted lines are **excluded**, never estimated. | `definitions` + `OrderItem` |
| **COGS Coverage %** | `costed units / total delivered units × 100`. Published alongside COGS so a margin over a third of the basket is not read as a margin over all of it. | — |
| **Gross Profit** | `Net Revenue − COGS`, **only when coverage > 0**. Otherwise `null`. | — |
| **Gross Margin %** | `Gross Profit / Net Revenue × 100`, **only when coverage > 0 and Net Revenue ≠ 0**. Otherwise `null`. | — |
| **Purchasing / Procurement** | `Σ GRN.total_cost` where `status = posted`, by `posted_at`. **Cash out to suppliers — not COGS**, and never subtracted from gross profit. | `inventory.GRN` |

⚠️ **Never use `inventory.services.weighted_average_cost()` for COGS.** It falls back
to `Product.price` when nothing costed was received — correct for valuing stock, but
as a cost basis it makes cost equal the selling price and reports a confident **0%**
margin. Use the costed-rows-only index in `reports/accounting_views.py::_wac_index()`.

⚠️ **Never value inventory at `Product.price`.** Stock is valued at WAC. Valuing at the
selling price overstates the holding by the entire margin.

---

## Agent pay

| Term | Definition | Source |
|---|---|---|
| **Delivery Pay** | `Σ DeliveryEarnings.total` = `base + distance_bonus + heavy_bonus + peak_bonus`, computed per task by `delivery/services.py::compute_earnings` from `DELIVERY_BASE_FEE`, `DELIVERY_DISTANCE_BONUS_PER_KM`, `DELIVERY_HEAVY_BONUS`, `DELIVERY_PEAK_BONUS`. | `delivery.DeliveryEarnings` |
| **Collection Pay** | `completed collections × COLLECTION_BASE_FEE` (default ₹30). A **rate**, not a ledger — there is no per-collection earnings row. | `agents/earnings.py` |
| **Incentives** | `Σ AgentIncentive.amount` | `agents.AgentIncentive` |
| **Accrued Earnings** | `Delivery Pay + Collection Pay + Incentives` | `agents/earnings.breakdown()` |
| **Paid** | **NOT TRACKED.** No payout/disbursement record exists anywhere in the platform. | — |
| **Payable** | **NOT COMPUTABLE** while payouts are untracked. Reported as `null`. | — |

⚠️ **`DeliveryEarnings.released` does NOT mean "paid".** `compute_earnings` writes
`released=True, released_at=now()` at the moment of delivery, and nothing in the
codebase ever writes `False`. It marks an earning as *accrued and confirmed*. Reading
it as a paid flag makes "payable" structurally ₹0 — an unknown printed as a fact.

`released_at` is therefore **not** a cash event and must not appear in cash flow.

When a real payout ledger is added, flip `agents/earnings.PAYOUTS_ARE_TRACKED` and
`paid`/`payable` become computable in both the finance and agent views at once.

---

## Cash

| Term | Definition | Source |
|---|---|---|
| **Collection Due (target)** | `CashCollection.amount` — what we set out to recover. **Not money.** | `payments.CashCollection` |
| **Cash Recovered** | `Σ CashCollection.collected_amount` for `collected` **and** `partially_collected`. | `definitions.cash_recovered()` |
| **Cash Inflow** | Settled `Payment` rows with `purpose ∈ {order, repayment}`, **plus** recovered collections that have no linked successful `Payment`. | `AccountingCashflowView` |
| **Cash Outflow** | Posted `GRN.total_cost` + settled `Payment` rows with `purpose = refund`. | — |

⚠️ **`CashCollection` has a `payment` FK.** Recovering cash books a matching
`repayment` Payment, so summing settled payments *and* every collection counts the
same rupee twice. Collections only contribute where not already booked as a settled
payment.

⚠️ **`purpose = handover` is never inflow.** An agent depositing collected cash moves
money already counted from one pocket to another.

⚠️ **Placing an order is not cash.** Only settled payments are.

---

## Order book

Mutually exclusive buckets over orders placed in the window:

| Bucket | Definition |
|---|---|
| **Delivered** | `status = delivered` |
| **Returned** | `status = returned` |
| **Cancelled** | `status = cancelled` — excluded from Gross Ordered |
| **In Flight** | everything else (any non-terminal status) |

`Placed = Delivered + Returned + In Flight` (cancelled excluded). A newly added order
status defaults to **In Flight**, so it can never silently become revenue.

---

## Inventory

| Term | Definition | Source |
|---|---|---|
| **On Hand** | `StockItem.quantity` per `(product, variant, warehouse)` | `inventory.StockItem` |
| **Reserved** | `StockItem.reserved` | — |
| **Available** | `quantity − reserved` | — |
| **Inventory Value** | `Σ on-hand × WAC`, where stock with **no costed inbound falls back to `Product.price`** | `definitions.inventory_valuation()` |
| **Inventory Costed %** | share of that value genuinely backed by costed receipts | same |

⚠️ **Inventory value is only partly at cost.** `weighted_average_cost` falls back to
the selling price when a product×warehouse never received costed stock. That is
defensible for a valuation — some number is needed — but it is not cost, and left
unqualified it reintroduces the overstatement this audit removed. On prod today
**67%** of the holding is genuinely costed; the other ₹377,844 is priced at retail.
Always publish `costedPct` next to the value.

⚠️ **`Product.stock_count` is a denormalised, company-wide field.** It is not
warehouse-scoped and not variant-scoped. On a per-variant catalogue it is the stock of
nothing and must not be used for operational or financial reporting.

---

## Pricing (customer bill)

Computed server-side by `core/pricing.py::compute_bill`. The client never decides
money.

| Term | Definition |
|---|---|
| **GST** | `subtotal × PlatformConfig.gst_rate`. **One rate for the whole cart** — see limitation below. |
| **Delivery Fee** | `0` if `subtotal >= free_delivery_threshold`, else the zone's fee (zone overrides platform default). |
| **Platform Fee** | base (flat or capped %) + small-cart + handling + surge, folded into one figure. |
| **Discount** | Coupon value, applied **after** GST — GST is charged on the full subtotal. |
| **Total** | `subtotal + delivery + gst + platform_fee − discount`, floored at 0. |
| **Minimum Order** | `effective_fees(zone)["min_order"]`, compared against **subtotal**. |

**GST units — exactly one rule:** the API and the operator always speak **percentages**
(`18`); the pricing maths always uses **fractions** (`0.18`). Convert only via
`gst_pct_to_fraction` / `gst_fraction_to_pct`. Rates are restricted to the statutory
slabs (0, 0.25, 3, 5, 12, 18, 28) because an arbitrary rate is almost always a typo.

### Known limitation (not a defect introduced here)

`Product.gst_rate` / `OrderItem.gst_rate` store **per-item** slabs, but `compute_bill`
applies a single platform-wide `PlatformConfig.gst_rate` to the whole subtotal. A cart
mixing 0% staples with 18% goods is therefore taxed at one blended rate. Invoices copy
`Order.gst`, so invoice and order always agree — there is no internal contradiction —
but the split is not statutorily itemised. Moving to per-line GST is a business and
compliance decision, not a bug fix, and is flagged rather than changed.

---

## Unknown vs zero

A hard rule across the API and both consoles:

| Situation | Correct | Wrong |
|---|---|---|
| No costed stock for sold units | COGS `null`, margin `null`, UI `—` | `₹0`, `0%`, `100%` |
| No payout ledger | `paid`/`payable` `null`, UI `—` | `₹0` |
| No promise-to-pay records | `null` | `0%` |
| Genuinely no sales | `₹0` | `—` |

`₹0` asserts a measured absence. `—` asserts we do not know. They are different claims
and must not be interchanged.
