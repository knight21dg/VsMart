# 07 · Locked Decisions (final confirmation)

These are the calls made to start implementation. Each is reversible early but expensive
later — change now or hold. Anything marked **(confirm with client)** is a business rule,
not a technical one.

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Framework | **Django 5 + DRF** | Free admin for staff management; safe for money. |
| D2 | Money type | **`Decimal(12,2)`** (Postgres `numeric`) | Exact (no float error), readable. Helpers round half-up. |
| D3 | JSON casing | **camelCase** (`djangorestframework-camel-case`) | App models are camelCase → **zero app changes**. |
| D4 | Response shape | `{ "data": … , "meta": … }` / `{ "error": {code,message,fields} }` | Matches app's `_data()` unwrapper. |
| D5 | Auth | **JWT** (simplejwt), access 30 min + refresh 30 d, rotation | Stateless, role claim in token. |
| D6 | User model | **single `User`, phone = username**, `role` enum | Simplest RBAC; `role` → Django `is_staff/is_superuser`. |
| D7 | OTP store | **Redis/cache**, 6-digit, TTL 5 min, 5 attempts | No OTP table; dev prints code to console. |
| D8 | Dev DB | **SQLite**; prod/Docker **PostgreSQL** via `DATABASE_URL` | Run + test with zero infra locally. |
| D9 | Files | store **object key** (`CharField`), serve **signed URLs** | No `ImageField`/Pillow coupling; private KYC docs. |
| D10 | API version | **`/api/v1`** | Matches app base URL. |
| D11 | IDs | BigAuto PK; **orders/tickets get a human code** (`VSORD…`) | Simple + shareable references. |
| D12 | Credit ledger | **append-only**; balances **derived + cached**, reconciled by job | One source of truth for money. |
| D13 | Idempotency | `Idempotency-Key` header on checkout/payments/repay | Prevent double-charge on retry. |

### Business rules **(confirm with client)**
- **D14 Credit cycle:** default **monthly** — purchases bill on the 1st, **due by the 5th**,
  no interest if paid on time; **late fee + account freeze** after due date. Weekly cycle
  supported as a per-account option. *(Assumed from app FAQ copy — verify amounts.)*
- **D15 GST:** flat **18%** at checkout (matches app). Per-category GST not modeled in v1.
- **D16 Delivery fee:** flat **₹45** below **₹499**, free above. (Configurable via env.)
- **D17 VS Score:** 0–900 internal score; starting value + factors **TBD** — stub now,
  formula later.

### Deferred (post-launch)
Real-time agent map tracking · multi-warehouse inventory · supplier/marketplace ·
web customer storefront · per-category GST · loyalty points.

---

## Definition of done (per phase)
A phase is complete when:
1. Models migrate cleanly + admin registers them.
2. Endpoints return the documented envelope and pass tests.
3. The **matching Flutter app screen works against the server unchanged** (the acceptance test).
4. Money-touching code has unit tests + an invariant check (`SUM(ledger)==outstanding`).

## Build order
Following [`06-roadmap.md`](06-roadmap.md): **Phase 0** (skeleton) → **1** (auth) →
**2** (catalog) → **3** (cart/orders) → **4** (credit) → **5** (payments) →
**6** (KYC/agents) → **7** (offers/notifications/support) → **8** (admin/hardening).
