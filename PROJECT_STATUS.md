# VS Mart — Project Status

_Top-level engineering status. Detailed per-test-case status lives in [docs/QA_TRACKER.md](docs/QA_TRACKER.md); ongoing-work context in the agent memory._

Last updated: 2026-06-28

## Production deployment

**LIVE** — backend redeployed 2026-06-28 to the VPS (`187.127.153.152`, Docker Compose + Caddy). DB backed up first (`/opt/vsmart/backup_predeploy_*.sql`); all pending migrations applied incl. this session's `uniq_order_idempotency`, `uniq_payment_idempotency`, KYC (Signzy/Setu/Cashfree) + system-settings fields — **0 unapplied**, `DEBUG=False`, `config.settings.prod`. All 5 endpoints HTTP 200 (api/admin/store/landing). Deploy = `.env`-safe `tar`-stream of `apps/backend` (rsync absent locally) + `docker compose up -d --build backend`. Web consoles unchanged this session (not rebuilt).

## Module readiness

| Module | Status | Notes |
|---|---|---|
| Backend commerce core | 🟢 ~98% | orders/payments/inventory/coupons/credit hardened + race-safe; 305 tests |
| Reconciliation (cancel/return/refund) | 🟢 ~95% | atomic + race-safe; `reconcile_finance` audit command |
| Real-time delivery / WS | 🟢 ~95% | dispatch board + tracking |
| Push notifications (FCM) | 🟡 ~90% | needs prod Firebase creds |
| KYC verification | 🟡 code-ready | Signzy/Setu/Cashfree adapters; needs live keys (Cashfree = PG-only, Secure ID not enabled) |
| Admin / Store-admin consoles | 🟡 ~90% | Next.js apps; not re-audited this phase |
| Customer App — cart/checkout | 🟢 done (automatable) | 32 Flutter tests; P0 double-submit guard locked |
| Customer App — other screens | 🟡 in progress | Sprint 2+ widget/logic tests |
| Flutter test coverage | 🟡 growing | infra built; 32 tests; expanding per sprint |
| CI release gate | 🟢 built | `scripts/release_gate.sh` (5 hard gates verified PASS) |

## Test counts (verified)

- Backend (Django): **312 tests** — `manage.py test` OK (incl. IDOR/object-ownership + upload-sanitization security tests)
- Flutter (user_app): **56 tests** — `flutter test` OK; `flutter analyze` clean
- Release gate: `scripts/release_gate.sh` → **PASS**

## Phase 2 — Customer App QA (sprint progress)

| Sprint | Status |
|---|---|
| 1 Cart & Checkout | ✅ automatable scope complete (logic + widget tests) |
| 2 Home | ✅ audited + skeleton/category widget tests |
| 3 Search | ✅ recent-searches logic tested |
| 4 Product | ✅ stock-status + add-to-cart mapping tested |
| 5 Orders | ✅ status classification tested + cancel-eligibility bug fixed |
| 9 Wishlist | ✅ controller (offline-optimistic toggle/remove/clear/persist) tested |
| 6 Live Tracking, 7 Notif, 8 Profile, 10–12 | ⚪ pending (mostly device/plugin-bound) |

## Known external blockers (cannot resolve without input)

- **Live payment gateway** (Razorpay/Cashfree prod) — needed for online-refund bookkeeping (RC-06) + payment cancel/retry device tests.
- **KYC provider keys** (Signzy sandbox, or Cashfree Secure ID activation).
- **Prod Firebase credentials** for FCM.
- **Device/emulator** for integration tests (U-17) + performance/battery/FPS.
- `vs-mart-engineering.skill` not present in Downloads (could not install).

## Release-blocking checklist (commerce)

- [x] Order idempotency · [x] Payment settle-once · [x] Inventory oversell guard
- [x] Coupon limits + concurrency · [x] Credit limit + ledger · [x] Cancel/return reversal
- [x] Backend tests green · [x] flutter analyze clean · [x] release gate green
- [ ] Live gateway refunds · [ ] Device integration tests · [ ] Perf/security device passes
