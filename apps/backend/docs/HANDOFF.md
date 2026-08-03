# VS Mart — Project Handoff & Continuation

Single bootstrap doc for resuming in a fresh conversation. Read this + the auto-memory
(`C:\Users\PARDHU\.claude\projects\C--knight21-VSMart\memory\`) and you have full context.

---

## What VS Mart is
A grocery commerce + **BNPL credit** platform (fintech). Surfaces: Customer app, Agent app
(collections + delivery), Admin console, Super-Admin console, and an upcoming **POS**.
Owner: Knight21 Digi Hub. Single-tenant (VS Mart owns all stores — **no vendor/marketplace**).

## Repo layout
```
C:\knight21\VSMart\
  apps\user_app\        # Flutter customer app (built, ~95%)
  apps\backend\         # Django backend (this)
  VS Mart Design\       # 63 client PNG mockups (authoritative for app screens)
```
Not a git repo. Windows. Use the Bash tool (Git Bash) for shell.

---

## STATUS

### Flutter app (`apps/user_app`) — built & shippable
Flutter 3.32 / Dart 3.8. Release APK builds (~71MB): from `apps/user_app`,
`flutter build apk --release` (needs NDK 27 + minSdk 23 — already set). Catalog uses the
**live DummyJSON API** with real images; demo OTP login accepts any number/code
(`AuthController._acceptAnyCredentials=true`). Square product cards, today's-deals,
overlay cart pill w/ landing-ripple, etc. See memory `vsmart-screen-build-workflow`.
To point at the real backend: set `_acceptAnyCredentials=false` and `AppConfig.apiBaseUrl`.

### Backend (`apps/backend`) — 26 apps, all verified
Django 5 + DRF + (dev SQLite / prod Postgres) + Redis + Celery + MinIO design, JWT, Docker.
**Runs locally with zero infra** (SQLite). All work verified by **7 smoke suites + a Django
unit-test module** (`inventory/tests.py`) — see "Run". (`scripts/gen_api_docs.py` reports
217 live operations across 39 modules; regenerate after route changes.)

Modules built: accounts/auth · users · geography · kyc · verification · credit (**append-only
ledger**) · catalog · **inventory (full ledger-based ERP — Phase 5)** · cart/wishlist ·
addresses · orders · payments · billing · cashcollections · delivery · agents · notifications
· offers/coupons · referrals · support · siteconfig (platform config) · zones (delivery
radius + fee overrides) · ops (analytics/staff/customer-360/inventory-adjust/audit/
credit-controls) · reports (CSV/Excel/PDF) · system (version/app-config/maintenance/
feature-flags/uploads/search/feedback) · **pos (Point of Sale — Phase 5)**.

**API contract is FROZEN & documented** (drf-spectacular): live `/api/docs/` (Swagger),
`/api/redoc/`, `/api/schema/`; artifacts in `docs/api/` (openapi.yaml, swagger.json,
postman_collection.json, api-architecture.md, api-coverage-report.md).

### Phase 5 — Inventory ERP + POS — ✅ BUILT & VERIFIED (2026-06-20)
Design in **`docs/11-pos-inventory.md`**. The rule is enforced: **stock is never written
directly; every movement = a signed `InventoryLedger` row; on-hand = Σledger (cached on
`StockItem.quantity`), available = on-hand − reserved.** Sole writer is
`InventoryService.post_movement` (atomic), mirroring `credit/services.py`.

- **5A Inventory ERP** (`inventory/`): `InventoryLedger` (system of record) + `StockBatch`
  (FEFO) + masters (Brand/Unit/Supplier/Barcode, SKU/mrp/cost on `ProductVariant`) +
  `GRN/GRNItem` + `LowStockAlert`. Services: `InventoryService` (post_movement, transfer,
  adjust, _ensure_opening — lazily **adopts legacy `Product.stock_count` as an `opening`
  row** on first touch), `StockCalculationService` (on_hand/reserved/available/FEFO),
  `StockSyncService` (rewrites `Product.stock_count`/`in_stock` + raises/clears alerts),
  `reconcile`, `post_grn`, `write_off`, `stock_valuation`. The `ops` stock-adjust endpoint
  now routes through the ledger. APIs under `/api/v1/inventory/*` (49 ops). Unit tests:
  `inventory/tests.py` (16, incl. the Σledger==on_hand invariant) — `manage.py test inventory`.
- **5B POS** (`pos/` — new app): `POSSession/POSTransaction/POSTransactionItem/POSPayment/
  POSRefund/CashDrawer/DayClosing/HeldCart`. Services in `pos/services.py` (checkout, returns,
  refunds, day-closing reconciliation, cash drawer). APIs under `/api/v1/pos/*` (17 ops):
  session open/close, scan, search, customer-lookup, checkout (split tender; **credit tender
  debits the credit ledger by exactly what it bills**), transactions, return, refund,
  cash-drawer, day-closing, cart hold/resume. Permission: new `core.permissions.IsCashier`
  (admin/superadmin today; widen to a `cashier` Django group later).
- **5C Stock sync**: `orders.services.place_order` posts an `order` ledger row (was a direct
  `stock_count` decrement); `cancel_order` posts `order_cancel` (restores stock). POS sales
  post `sale`; returns post `return`.

Verified end-to-end by **`scripts/smoke_pos.py`** (PO→GRN→adjust→transfer→damage→sale→return,
split-tender credit invariant, zero-variance day-closing, online-order→ledger wiring, final
Σledger==Σcache). Swagger/OpenAPI/Postman regenerated. **Gotcha:** a store should have ONE
`Warehouse.is_default`; `default_warehouse()` picks the oldest if several exist.

### HARDENING PASS — ✅ DONE (2026-06-20, after an audit of Phase 5 + the platform)
Critical→low fixes, all with tests green (34 unit tests across `inventory`+`pos`, 7 smokes):
- **Idempotency** on `/checkout` and `/pos/checkout` via an `Idempotency-Key` header
  (Order/POSTransaction now carry `idempotency_key`) — a retry returns the existing txn.
- **Reservations**: online checkout now **reserves** stock (`StockItem.reserved`, atomic, the
  oversell guard) instead of decrementing; the `order` ledger movement is posted on
  **fulfilment** (`orders.services.fulfil_order`, hooked into delivery-complete + `advance_status`
  delivered); cancel releases. `Order.stock_state` ∈ none/reserved/fulfilled/released.
  `Product.in_stock` now reflects **available** (on-hand − reserved).
- **POS tender enforcement**: payments must cover the total (non-cash can't exceed it; cash
  over-tender returns `change_due`); only net cash hits the drawer.
- **Credit gate**: `credit.services.assert_credit_eligible` — credit tender (POS + online)
  requires `kyc_status=verified` + `credit_enabled` + active account.
- **Append-only enforced**: `InventoryLedger`/`CreditLedgerEntry` `.save()` on an existing row
  and `.delete()` raise.
- **Single default warehouse**: `Warehouse.save()` demotes other defaults.
- **on_hand reads the StockItem cache** (was re-summing the ledger); `ledger_balance()` is the
  reconcile reference. Valuation is now **weighted-average cost**.
- **Security**: `token_blacklist` app + revocable logout + rotating refresh (old refresh →
  401); platform-wide throttling (`AnonRateThrottle`+`UserRateThrottle`+scopes; dev rates are
  permissive so smokes never 429; OTP stays 5/min); prod `SECRET_KEY` required (no default) +
  optional Sentry seam; stronger password validators.
- **POS features**: thermal receipt payload w/ CGST/SGST split (`/pos/transactions/{id}/receipt`),
  **void** (`/…/void`), per-line discounts, day-closing tender breakdown (upi/card/credit) +
  terminal field, `AnalyticsEvent` stream (stock_moved/low_stock/sale_completed/day_closed) with
  a polling **events feed** (`/pos/events?since=`) as the realtime substitute, **POS reports**
  (`/pos/reports/{sales-by-cashier|day-closings|fast-movers|slow-movers|expiry}`), and an
  inventory **reorder-level** API (`/inventory/reorder-level`).
- **Tax-inclusive pricing** is configurable (`PlatformConfig.pos_price_tax_inclusive`; default
  off = tax-on-top, matching existing behavior — flip on for MRP-inclusive grocery).

### NEXT (Phase 6 candidates — what's still infra-bound, not code)
WebSocket transport for the events stream (Channels/ASGI/Redis) — the event model + polling feed
exist; real **payment gateway** (Razorpay) + **SMS** (MSG91) creds; server-side **PDF render** of
the receipt payload; a full **Store/terminal** model (only a `terminal` string today); ops:
backups, Sentry DSN, monitoring, scheduled Celery beat (statements/reminders).

---

## RUN (dev — SQLite, no Docker)
From `C:\knight21\VSMart\apps\backend` (venv already at `.venv`):
```bash
export DJANGO_SETTINGS_MODULE=config.settings.dev      # bash
.venv/Scripts/python.exe manage.py migrate
.venv/Scripts/python.exe manage.py seed_demo
.venv/Scripts/python.exe manage.py runserver           # /api/v1/ + /admin/ + /api/docs/
# verify everything (each prints "... PASSED"):
.venv/Scripts/python.exe scripts/smoke_test.py    # auth + catalog
.venv/Scripts/python.exe scripts/smoke_money.py   # address→cart→checkout→credit→repay→cash→ledger invariant
.venv/Scripts/python.exe scripts/smoke_full.py    # kyc/offers/notifications/support/referrals/ops + RBAC
.venv/Scripts/python.exe scripts/smoke_admin.py   # platform config/zones/fees/analytics/inventory/credit
.venv/Scripts/python.exe scripts/smoke_modules.py # geography/inventory/delivery/verification/billing
.venv/Scripts/python.exe scripts/smoke_final.py   # system/agents/collections/reports + RBAC
.venv/Scripts/python.exe scripts/smoke_pos.py     # Phase 5: inventory ledger + POS + order wiring
.venv/Scripts/python.exe manage.py test inventory # 16 unit tests incl. ledger invariant
```
Always run `manage.py check` after edits. OTP codes print to the server console in dev.
Phase-5 smoke prints to a cp1252 console — keep labels ASCII (no `→`/`Σ`) or set
`PYTHONIOENCODING=utf-8`.

---

## CONVENTIONS (match these)
- **Envelope:** every response `{success, message, data, meta?}`; errors `{success:false,
  message, error:{code,message,fields}}`. Centralized in `core/renderers.py` — views just
  `return Response(serializer.data)`.
- **Casing split:** auth/user endpoints (`/auth/*`, `/users/me`) are **snake_case**
  (access_token, kyc_status, `id` as string) via `SnakeEnvelopeJSONRenderer`; **everything
  else camelCase** (auto). Don't "fix" auth to camelCase — the Flutter models need snake.
- **Money:** `DecimalField(max_digits=12, decimal_places=2)`, rendered as JSON numbers
  (`COERCE_DECIMAL_TO_STRING=False`). Quantize via `core/pricing.py q()`.
- **Ledgers (credit, soon stock):** append-only rows, balances derived + cached +
  reconciled. Never UPDATE/DELETE ledger rows; corrections are new rows. See
  `credit/services.py` as the template.
- **New app skeleton:** `core.models.TimeStampedModel`; user FK via `settings.AUTH_USER_MODEL`;
  serializer `id = CharField(read_only=True)`; permissions from `core/permissions.py`
  (`IsCustomer/IsAgent/IsAdmin/IsSuperAdmin`); register in `INSTALLED_APPS` + `config/urls.py`;
  `makemigrations <app>`.
- **Roles:** superadmin/admin/agent/customer; agent.type ∈ collection/delivery/verification;
  functional managers = admins + Django groups. Money/config/zone *edits* are superadmin-only.
- **Contract is authoritative:** never rename existing endpoints (Flutter depends on them);
  add NEW endpoints for new features.

## GOTCHAS (cost time if forgotten)
1. **Never name an app `collections`** — shadows Python stdlib, breaks pip/Django. (Renamed
   to `cashcollections`; URL prefix stays `/collections/*`.)
2. **`?format=` is reserved by DRF** (content negotiation 404s). Reports export uses `?fmt=`.
3. **First `migrate` order:** accounts before admin (swapped user model). If
   `InconsistentMigrationHistory`, `rm db.sqlite3` and re-migrate. `makemigrations` needs
   explicit app names the first time.
4. **camelCase lib splits trailing digits** (`line1`→`line_1`) — fixed via
   `JSON_CAMEL_CASE={"JSON_UNDERSCOREIZE":{"no_underscore_before_number":True}}`.
5. **User FKs are `on_delete=PROTECT`** on Order/CreditAccount/Payment — can't hard-delete a
   user with financial records (intended). Smoke scripts use random phones, not delete.
6. **AuditLog JSONField can't store Decimals** — `record_audit` runs data through `_json_safe`.
7. **drf-spectacular** warns on hand-rolled APIViews (loose bodies) — non-fatal.

## PRODUCTION SEAMS (stubbed, each a localized swap)
Payment gateway = MockGateway (`payments/gateway.py` → Razorpay) · SMS = console
(`accounts/otp.py` → MSG91) · file uploads/KYC return placeholder keys (→ MinIO/S3) ·
Celery statement/reminder jobs not scheduled · dev SQLite → Postgres (`DATABASE_URL`).
Also pending pre-launch: rate limiting, refresh-token rotation/device sessions, backups,
Sentry, monitoring, pen-test.

## KEY DOCS (in `apps/backend/docs/`)
00-overview · 01-architecture · 02-data-model · 03-api-spec · 04-rbac · 05-deployment ·
06-roadmap · 07-decisions · 08-superadmin-control-plane · 09-enterprise-alignment ·
10-api-contract (Flutter-authoritative) · **11-pos-inventory (Phase 5 — build next)** ·
api/ (generated OpenAPI/Swagger/Postman).
