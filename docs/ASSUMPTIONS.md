# Engineering Assumptions

Decisions made autonomously where a business rule was unclear. Each records the
**safest production default** chosen so work could continue. Flagged ones change
production behaviour if revisited — confirm with the business owner before release.

| # | Area | Question | Default chosen (safest) | Revisit impact |
|---|------|----------|-------------------------|----------------|
| A-1 | Orders | Should a **`packed`** order be customer-cancellable? | **No** — the app mirrors the backend `cancel_order` guard (pending\|confirmed only). The app previously showed a Cancel button on packed orders that the server rejected (`ORDER_NOT_CANCELLABLE`); aligned the app to the backend. | If "yes", needs a backend `cancel_order` change + inventory-release-on-packed handling. ⚠️ business decision. |
| A-2 | Coupons | Is a coupon redemption **restored** when the order is cancelled/returned? | **No** — redemptions are not restored (anti-abuse default). | If "yes", add a redemption-reversal on cancel/return. ⚠️ business decision. |
| A-3 | KYC / Credit | Does VS Mart verify Aadhaar/PAN itself, or via the NBFC partner? | Marketplace identity = PAN (frictionless); credit-grade Aadhaar eKYC = the regulated **NBFC/LSP partner** (RBI model). API verification informs the reviewer; it does **not** auto-grant credit. | Changing the lending KYC owner is a regulatory/legal decision. ⚠️ |
| A-4 | App ↔ backend | When app behaviour and backend behaviour disagree, which wins? | **Backend is the source of truth.** The app is aligned to the backend's enforced contract (don't offer actions the server rejects). | None — this is a standing engineering rule, not a business rule. |

_Update this file whenever a new assumption is made during autonomous work._
