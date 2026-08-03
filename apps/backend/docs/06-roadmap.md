# 06 · Implementation Roadmap

Build in vertical slices that the Flutter app can adopt incrementally. Each phase ends
with the app able to flip one feature from demo/DummyJSON to the real server.

## Phase 0 — Project skeleton  *(prereq, ~0.5 day)*
- Django 5 project (`config` + split settings dev/prod), DRF, SimpleJWT, Celery wired.
- `docker-compose.yml` + `Caddyfile` + `.env`; `api`/`db`/`redis` running locally.
- `core` app: base model, response envelope renderer (camelCase), exception handler,
  pagination, permission classes, `health` endpoint.
- `accounts` app with custom `User` (phone-based) + `role`. `createsuperuser` works.
- **Exit:** `GET /api/v1/health` ok; Django admin login works.

## Phase 1 — Auth & identity  *(~1–2 days)*
- OTP send/verify (Redis store, SMS provider behind an interface — log to console in dev).
- JWT issue + refresh rotation; `/users/me`, `/auth/register`, logout, device-token.
- Audit log scaffolding.
- **App flip:** set `_acceptAnyCredentials=false`, point `AppConfig` at dev server → real login.

## Phase 2 — Catalog  *(~2 days)*
- Categories, products, variants, images, specs; search (`tsvector`).
- Public read endpoints matching the app contract; admin CRUD (Django admin).
- Seed command importing the current demo products (or a real catalog).
- **App flip:** swap `catalogRemoteDataSourceProvider` from DummyJSON to the real API.

## Phase 3 — Cart, wishlist, addresses, orders  *(~3 days)*
- Server cart with computed bill (GST 18%, delivery rule), wishlist, addresses.
- Checkout (atomic) for **cash/UPI** orders (no credit yet); order list/detail/timeline/tracking.
- Reorder, cancel.
- **App flip:** cart/checkout/orders use the server.

## Phase 4 — Credit core  *(~4–5 days, highest care)*
- `credit_account`, **append-only ledger**, derived balances + reconciliation job.
- Checkout on `credit` → atomic ledger debit; dashboard, score, ledger, outstanding.
- Statements (weekly/monthly) via Celery beat; due-date logic + freeze on overdue.
- Family/shared limit.
- **Tests first** for ledger math, limits, and statement generation. **App flip:** credit dashboard, statements, pay-later checkout.

## Phase 5 — Payments  *(~3 days)*
- Razorpay order creation; **webhook** (signature-verified, idempotent) finalizes payments
  and posts repayment ledger entries; payment history.
- Credit repayment flow; idempotency keys.
- **App flip:** real repayments + order payments.

## Phase 6 — KYC & agents  *(~3 days)*
- KYC submit (MinIO uploads), status; agent/admin review workflow → verify → enable credit.
- Agent: KYC queue, deliveries, **cash collection** → produces `cash` payment + ledger repayment.
- **App flip:** KYC flow + agent app surfaces.

## Phase 7 — Offers, notifications, support, referrals  *(~3 days)*
- Offers/banners/deals; coupons + validation/redemption.
- Notifications inbox + push (FCM); preferences; reminder jobs (due-date alerts).
- Support tickets + messages + FAQs. Referrals.
- **App flip:** remaining secondary screens.

## Phase 8 — Admin/ops & hardening  *(~3 days)*
- Admin dashboards (KPIs), customer-360, refunds, staff management (superadmin),
  global config (fees/cycle/gateway keys).
- Rate limiting, security pass (OWASP API top-10), audit coverage, backups verified,
  Sentry + uptime, load sanity test.
- **Exit:** staging → production cutover; app prod flavor points at `api.vsmart.app`.

---

## Sequencing notes
- **Money modules (4 & 5) get tests before features.** The ledger is the one place a bug
  costs real money — write reconciliation tests and an invariant check (`SUM(ledger)==outstanding`).
- Keep the **app contract** (`03-api-spec.md`) as the acceptance check for each phase:
  a phase is "done" when the corresponding app screen works against the server unchanged.
- Defer anything in "out of scope" (`00-overview.md`) — don't gold-plate before launch.

## First commit checklist (Phase 0)
- [ ] `config/` settings split + `.env` loading
- [ ] `core` (envelope, exceptions, permissions, pagination, health)
- [ ] `accounts.User` (phone login) + admin
- [ ] Docker Compose up (api/db/redis) + migrate + createsuperuser
- [ ] CI: lint + tests on push
