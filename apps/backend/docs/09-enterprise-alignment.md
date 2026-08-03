# 09 · Enterprise Alignment & Gap Map

Reconciles the **enterprise architecture doc** (20 modules, ~300 APIs) with what's
already built and verified, and locks the **single-tenant** simplifications.

## Direction (confirmed)
- **Modular monolith** on Django — already how this is structured (16 apps today).
- **Single-tenant** (VS Mart owns all stores, **no marketplace**):
  - ❌ **No Vendor Panel / vendor app** — "stores" become **internal warehouses**, not vendors.
  - ❌ **No Zone Admin / Area Manager geographic admin tiers** — they add complexity
    without payoff for a single operator. Roles stay **functional**, not geographic.
  - ✅ **Geography stays as data** (state→district→zone→area→village) for **mapping**
    customers/agents/warehouses and agent collection search (e.g. `BAL001`), not as panels.

## Module reconciliation (their 20 → current state)

| Target module | Status | Action |
|---|---|---|
| authentication | ✅ built (`accounts`) | add `resend-otp` |
| users | ✅ built (`accounts`+`addresses`) | add **employment/income** fields (currently only in KYC) |
| **geography** | ❌ missing | **build app** — hierarchy + village/area codes |
| kyc | ✅ built | add house-photo + GPS steps, `draft` state |
| credit | ✅ built | solid (account, **append-only ledger**, score, statements, family) |
| catalog | ✅ built | add `brands`, reviews, recommendation endpoints |
| **inventory** | 🟡 in `ops` | **promote to app** — reservations, transfers, purchase orders, low-stock |
| cart | ✅ built | — |
| orders | ✅ built | add `returned` state |
| payments | ✅ built | add UPI/QR/payment-link methods + `verify` |
| **billing** | 🟡 statements in `credit` | add **invoices + receipts** first-class |
| **collections** | 🟡 `CashCollection` in `payments` | **promote** — assignment, OTP, partial, receipts, agent search |
| **delivery** | 🟡 `DeliveryAssignment` in `orders` | **promote** — accept/reject/start/otp/photo/complete + GPS |
| **verification** | 🟡 in `kyc` | **build** — agent field tasks + photo/GPS evidence |
| **agents** | 🟡 `AgentProfile` | **expand** — agent types, performance, earnings, incentives |
| notifications | ✅ built | wire FCM/WhatsApp providers later |
| analytics | ✅ built (`ops`) | add credit/collection/agent analytics |
| **reports** | ❌ missing | **build** — sales/credit/collection/inventory/agent + Excel/CSV/PDF export |
| audit | 🟡 model in `accounts` | add **`/audit/logs` API** + filters |
| permissions / feature-flags | 🟡 role classes + Django groups | add **feature-flags + roles/permissions endpoints** |
| settings | ✅ built (`siteconfig`) | add `app-config`, `maintenance`, `version` |
| ~~vendor~~ | ❌ dropped | single-tenant → internal `warehouse` model instead |

**System endpoints to add:** `/version`, `/app-config`, `/maintenance-status`,
`/feature-flags`, `/uploads`, `/search/global`, `/feedback`. (`/health`, `/faq`,
`/support-tickets` already exist.)

## Decisions needed (they ripple across many files)

- **D-A · Response envelope.** Doc wants `{success, message, data, meta}`. Current is
  `{data, meta}` / `{error}`. **Recommended:** adopt — it's *additive* (keep `data`, so the
  Flutter app is unaffected) and errors become `{success:false, message, error}`.
- **D-B · API paths.** Doc groups as `/auth/send-otp`, `/customers/me`,
  `/catalog/products`. Current matches the **already-built Flutter app** contract
  (`/auth/otp/send`, `/users/me`, `/products`). **Recommended:** keep the app-compatible
  contract (re-pathing breaks the app for zero functional gain); add new modules under
  their own clean prefixes (`/geography/*`, `/collections/*`, `/delivery/*`, `/reports/*`).
- **D-C · Roles.** **Recommended (per single-tenant):** `superadmin · admin · agent ·
  customer` as core roles; **agent.type ∈ {collection, delivery, verification}**;
  functional managers (operations/credit/collection/inventory/support) modeled as
  **admins + Django permission groups**, not new roles. No Zone/Area admin tiers.

## Build plan to close the gap (single-tenant)

- **A — Field operations & ledgers:** `geography`, promote `inventory`/`collections`/
  `delivery`/`verification`/`agents` to full apps, `billing` (invoices/receipts).
- **B — Oversight & system:** `reports` (+export), `audit` API, feature-flags/app-config/
  version/maintenance, `uploads`, global search, feedback, warehouse/serviceability.
- **C — Conventions:** envelope upgrade (D-A), role expansion (D-C), agent sub-types.

DB estimate after expansion: today **41 tables → ~90–110** (matches the doc's 90–120),
minus the vendor/geographic-admin tables removed by single-tenant.
