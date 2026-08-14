# Contributing to VS Mart

## Financial and business metrics — read this before adding a number

Three consecutive audits found the same root cause: the dashboard, accounting, the
store panel, CRM, the agent app and the report builders had each grown their own
arithmetic for the same word. Every one returned a plausible number, so nothing ever
looked broken — revenue was overstated 5.9×, margin displayed a confident 100%, and
agent pay had two competing formulas.

The rule that prevents a fourth audit:

> **One business definition → one authoritative implementation → every surface
> consumes it.**

### Before you add or change a financial metric

1. **Read [`FINANCIAL_DEFINITIONS.md`](FINANCIAL_DEFINITIONS.md).** It is the canonical
   definition of Revenue, COGS, Gross Profit, Agent Earnings, Cash Recovered,
   Inventory Value, GST, Delivery Fee and the rest.
2. **If the metric is already defined, reuse its implementation.** Check
   [`FINANCIAL_CONSISTENCY_MATRIX.md`](FINANCIAL_CONSISTENCY_MATRIX.md) for which
   module owns it. Do not write the aggregate a second time.
3. **If it isn't defined, define it there first**, then implement it once — normally
   in `core/financials.py` — and consume it from every surface.
4. **Add a regression test that would fail against a duplicate implementation.**

### This is enforced, not just documented

`core/test_financial_duplication.py` runs on every CI build. It fails when a money
aggregate appears outside an authoritative module and isn't classified.

```bash
cd apps/backend
python scripts/check_financial_duplication.py          # report
python scripts/check_financial_duplication.py --list   # every site, with its class
```

If it fails on your change, you have two options — and only two:

1. **Call the canonical implementation.** This is almost always the right answer.
2. **Classify the site** in `CLASSIFIED` in `scripts/check_financial_duplication.py`,
   **with a reason**, if it is genuinely a different metric (a per-module ledger sum,
   a domain-specific total, presentation-only). The reason is the review conversation
   that was missing the first three times; a bare entry is rejected by the test.

Current state: **95 aggregates across 21 files, all classified, zero unexplained
duplicates.** The checker is self-guarding — separate tests assert that it still fires
on a real duplicate, that every classification names an existing file, and that no
classification shadows an authoritative module.

### Where the definitions live

| Module | Owns |
|---|---|
| `core/financials.py` | Revenue, order book, POS net, refunds, cash recovered, inventory valuation, customer lifetime revenue |
| `agents/earnings.py` | Agent earnings — delivery pay, collection pay, incentives, accrual vs payout |
| `core/pricing.py` | Cart/order bill — GST, delivery fee, platform fee, discount, minimum order |
| `inventory/services.py` | Weighted-average cost, stock valuation |
| `payments/cashbook_services.py` | Cash in hand, deposits, handover verification |

### Four rules that have each been violated in production

**1. Never infer business meaning from a field name.** `DeliveryEarnings.released`
reads like "paid". It is written `True` at the moment of delivery and never written
`False` — it means *accrued*. Treating it as a payout flag made "agent payable" report
₹0 forever. Before using any boolean or status as business state, trace **who writes
it, when, and what real-world event causes it to change.**

**2. Never convert unknown into zero.** `₹0` asserts a measured absence; `—` asserts we
don't know. They are different claims:

| Situation | Correct | Wrong |
|---|---|---|
| No costed stock for sold units | COGS `null`, margin `—` | `₹0`, `0%`, `100%` |
| No payout ledger | `paid`/`payable` `null` | `₹0` |
| Genuinely no sales | `₹0` | `—` |

**3. Never let a fallback change business meaning.** `weighted_average_cost()` falls
back to `Product.price` when nothing costed was received. Fine for valuing stock;
catastrophic as a cost basis, where it makes cost equal the selling price and reports a
0% margin. When a fallback is unavoidable, publish the coverage next to the value —
`inventory_valuation()` returns `costedPct` for exactly this reason.

**4. Clients display; they do not decide.** Money is computed server-side. Client-side
arithmetic is acceptable only as an explicitly-flagged estimate (`isEstimate`) that a
server value replaces before anything is committed. Do not hardcode a business rate in
a client — a hardcoded "₹45" delivery fee advertised a saving no zone actually offered.

### Business policy is not a bug

Some things look wrong and are correct. Do not "fix" them without the business asking:

- **Negative net revenue** is valid when refunds exceed recognised revenue in a period.
- **Platform-wide GST** vs per-item statutory slabs is a compliance decision.
- **`—` instead of a number** is the honest answer when the data cannot support one.

Both are documented in [`BUSINESS_TRUTH_AUDIT.md`](BUSINESS_TRUTH_AUDIT.md).
