# VS Mart — Project Status

Top-level engineering status. Per-test-case detail lives in [docs/QA_TRACKER.md](docs/QA_TRACKER.md);
the full picture is in [HANDOFF.md](HANDOFF.md); change-by-change history in
[CHANGELOG.md](CHANGELOG.md).

**Last updated: 2026-08-07.**

## Production

**LIVE.** One VPS (`187.127.153.152`, Ubuntu 24.04) running Docker Compose behind Caddy with
automatic HTTPS. Four hostnames serving: `thevsmart.com`, `admin.`, `store.`, `api.`. Services:
`db` (Postgres 16), `redis`, `backend`, `scheduler`, `admin`, `store-admin`, `landing`, `caddy`.

Both Android apps are built and distributed from stable short links — `/userapp` and `/agentapp`,
served off disk by Caddy so the URL survives a filename change.

> Deploy checklist: back up the database *before* migrations, then
> `docker compose up -d --build`, then `docker compose up -d scheduler` — the scheduler is the only
> thing running periodic jobs and is easy to forget.

## Verified test results (run 2026-08-07)

| Suite | Result |
|---|---|
| Backend — `manage.py test` | **1,229 tests, all passing** (~19 s with `--parallel 4`) |
| `user_app` — `flutter test` | **165 tests passing**; `flutter analyze` clean |
| `agent_app` — `flutter test` | **76 tests passing**; `flutter analyze` clean |
| `apps/admin`, `apps/store-admin` | No automated tests — a real gap |

## Module readiness

| Module | Status | Notes |
|---|---|---|
| Commerce core (catalog, cart, checkout, orders) | 🟢 | Per-variant stock; idempotent checkout; reservations + TTL sweep |
| Inventory / POS | 🟢 | Append-only ledger; offline-capable POS with idempotent sync |
| Credit (BNPL) | 🟢 | Application→review→grant; append-only ledger; 2026-07-22 sweep fixed money-losing repayment |
| Cash collections | 🟢 | State machine, OTP, partial collection, disputes, dunning |
| Cash book → General Ledger | 🟢 | Deposit → finance verification → double-entry GL |
| Delivery operations | 🟢 | Geofence, OTP, mandatory POD photo, reattempt/return |
| Dispatch engine | 🟡 | Phases 1–2 deployed (batching, routing, store dashboard); Phases 3–4 not built |
| Zones / serviceability | 🟢 | Z1–Z6 complete; polygon routing; store-scoped catalog |
| Store panel (`store-admin`) | 🟢 | Store-scoped RBAC; POS, purchase entry, verification, collections, returns, reports |
| Super-admin console (`admin`) | 🟢 | 52 pages; no automated tests |
| Customer app | 🟢 | Fully backend-driven; en/te/hi localization |
| Agent app | 🟢 | Field-hardened 2026-08-04; **no Firebase/push integration** |
| Marketing site | 🟢 | Customer OTP sign-in + `/account` added 2026-08-04 |
| Media (`mediastore`) | 🟡 | Engine + all consumers done; prod ops pending (see below) |
| Realtime (WebSockets) | 🟢 | Channels dispatch board + order tracking, with poll fallback |
| SMS | 🟢 | **Live** via smslogin.co since 2026-08-05 (sender `VSMRTS`, per-purpose DLT templates) |
| Push (FCM) | 🟡 | Works end-to-end in `user_app`; needs prod Firebase credentials |
| Payments (Razorpay) | 🟡 | Code complete; runs in mock mode until live keys are set |
| KYC verification | 🟡 | Signzy/Setu/Cashfree adapters code-complete; needs live keys |
| CIBIL score | 🔴 | Blocked — Payon returns "Permission denied for this service"; host and key now correct |
| Deep links | 🟡 | Implemented; blocked on Play SHA-256 + Apple Team ID |
| Catalog content localization | 🟡 | Engine works; per-language columns are empty, so it reads as untranslated |

## Blocked on someone outside engineering

| Blocker | Needed from |
|---|---|
| Razorpay live keys | Business / payment provider |
| Prod Firebase service account | Business |
| Payon must enable credit-score on the account | Payon support |
| Signzy KYC credentials | Business / Signzy |
| Google Maps API key | Business |
| Play SHA-256 fingerprint + Apple Team ID | Play Console / Apple Developer |
| RBI NBFC/LSP lending agreement | Commercial track — VS Mart cannot lend on its own books |
| Physical handsets | QA — integration, performance, battery and FPS passes |

## Open engineering work

**Operational (no code):**
- `rehost_catalog_images` has never run in production.
- Prod Caddy still needs the X-Accel block; `media_cleanup` cron not scheduled.
- Catalog localization columns need translated content loaded.

**Cleanup:**
- `subscriptions` was removed (write-only table); the `DeleteModel` migration shipped — delete the
  app folder and the `INSTALLED_APPS` line once it is applied everywhere.
- `geography` app and `orders.DeliveryAssignment` are flagged legacy-dead.

**Code:**
- Dispatch engine Phases 3–4.
- Commerce audit items still open: cancel-without-refund, a formal order state machine, payment
  callback verification, reconciliation.
- Invoice numbering is not yet a compliant GST series.
- `agent_app` has no Firebase/push integration.
- No automated tests for either Next.js console.

## Release-blocking checklist (commerce)

- [x] Order idempotency (DB-constrained)
- [x] Payment settle-once
- [x] Inventory oversell guard
- [x] Coupon limits + concurrency
- [x] Credit limit + append-only ledger
- [x] Cancel / return reversal
- [x] Backend tests green (1,229)
- [x] `flutter analyze` clean on both apps
- [x] Release gate green (`scripts/release_gate.sh`)
- [ ] Live gateway refunds (blocked on Razorpay keys)
- [ ] Device integration tests (blocked on handsets)
- [ ] Performance / security device passes
