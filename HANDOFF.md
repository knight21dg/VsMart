# VS Mart — Full-System Handoff

Single bootstrap doc to resume in a fresh conversation. Read this + the auto-memory
(`C:\Users\PARDHU\.claude\projects\C--knight21-VSMart\memory\`, which auto-loads) and you have
full context. Supersedes the older backend-only `apps/backend/docs/HANDOFF.md`.

Date of this snapshot: **2026-06-21**.

---

## 1. What VS Mart is
A grocery commerce + **BNPL credit** platform (fintech). Surfaces: Customer app (Flutter), Agent
app (collections/delivery), Admin + Super-Admin consoles, and a **POS**. Single-tenant (VS Mart
owns all stores — no marketplace). Owner: Knight21 Digi Hub.

## 2. Repo layout (Windows; NOT a git repo)
```
C:\knight21\VSMart\
  apps\user_app\   # Flutter customer app (Flutter 3.32 / Dart 3.8) — FULLY wired to the backend
  apps\backend\    # Django 5 + DRF backend (dev SQLite, venv at .venv)
  VS Mart Design\  # 63 client PNG mockups (authoritative for app screens)
  HANDOFF.md       # this file
```
Use the **Bash tool (Git Bash)** for POSIX shell, **PowerShell** for Windows-specific ops.

---

## 3. STATUS — what's done

### Backend (`apps/backend`) — Django 5 + DRF, ~27 apps, dev SQLite
- **All phases + Phase 5 (Inventory ERP + POS)** built & verified: append-only `InventoryLedger`
  (stock is never written directly; `InventoryService.post_movement` is the sole writer; available
  = Σledger − reserved), masters/GRN/PO/transfer/damage/expiry, POS sessions/billing/split-tender/
  returns/day-closing/cash-drawer, `StockSyncService`.
- **Hardening (Tier 1–2)**: idempotency on `/checkout` + `/pos/checkout` (Idempotency-Key);
  **reservations** (online checkout reserves, fulfilment posts the `order` ledger movement, cancel
  releases); platform-wide throttling; append-only `.save()/.delete()` guards on ledgers;
  credit **KYC gate** (`credit.services.assert_credit_eligible`); weighted-average valuation;
  `on_hand` reads the StockItem cache; cursor pagination (ledger + search); RFC 9457 error fields
  (additive); reservation-TTL sweep (`orders.services.release_expired_reservations` +
  `manage.py release_expired_reservations`); JWT `token_blacklist` + revocable logout + rotating
  refresh; prod `SECRET_KEY` required + Sentry seam.
- **Tier-3 code-ready (activate with creds/infra)**:
  - **Razorpay** — `payments/gateway.py`: `RazorpayGateway.create_order` implemented;
    `get_gateway()` auto-selects it when `RAZORPAY_KEY_ID`/`_SECRET` set (else mock). Webhook HMAC
    verify already correct. Dev mock **auto-captures** non-cash payments so repay settles instantly.
  - **MSG91 SMS** — `accounts/otp.py:_send_via_msg91`, active when `SMS_PROVIDER=msg91`.
  - **FCM push** — `notifications/services.notify()` writes the inbox row + pushes via FCM when
    `FCM_SERVER_KEY` set; wired into order placement + status changes.
  - **Dynamic fees** — `PlatformConfig.{small_cart_fee,small_cart_threshold,handling_fee,surge_fee,
    surge_active}` (default 0); `core/pricing.compute_bill` folds them into `platform_fee`.
  - **Search ranking** — `catalog.ProductSearchView` relevance-ranks (exact>prefix>contains>brand)
    + popularity tiebreak.
- **App-wiring pass (2026-06-21)** — closed the gaps where app screens faked data:
  - **Coupons now apply server-side**: `offers/services.resolve_coupon` is the single source;
    `CouponValidateView` + `orders.CheckoutView` both use it, so the previewed discount == the
    charged discount (was a `coupon_discount=0` no-op before).
  - **Credit dashboard** returns `purchasesThisMonth` / `paymentsThisMonth` (current-month ledger).
  - **NotificationPreference** extended (migration `notifications.0002`): `reminderEnabled`,
    `reminderOffsetDays`, and a free-form `categories` JSON map for per-event toggles.
- **Tests/contract**: 36 unit tests (`manage.py test inventory pos orders`) + 8 smoke suites
  (`scripts/smoke_*.py`, incl. new `smoke_wiring.py` asserting the app-wiring contract) all green.
  API frozen via drf-spectacular (`docs/api/*`).
- **Seed**: `manage.py seed_demo` → 6 categories, 26 grocery products (CDN images), offers
  (banners/deals/coupons), FAQs, coupons VS100/FRESH15. `scripts/setup_local.py` →
  superadmin/admin/customer + warehouse + stock + barcodes + prints JWTs.

### Flutter app (`apps/user_app`) — FULLY backend-driven (no fixtures/DummyJSON/mock auth)
Every customer flow hits the backend `/api/v1` via the **cache-mirror** pattern (server
authoritative; Hive cache for sync reads; hydrate on build) or clean **datasource swaps**:
- auth (OTP), profile, **catalog/search/categories**, **cart→checkout→orders** (server cart synced
  at checkout, `POST /checkout` with Idempotency-Key, stock reserved), **order tracking** (12s
  poll), **credit** (dashboard/score/ledger/repay), **billing** (statements/invoices/payment-
  history/collections), **addresses**, **offers**, **wishlist**, **notifications** (real inbox),
  **KYC**, **support** (FAQ + tickets list/create/detail/reply).
- **Login redesigned** + uses the real app icon (`assets/images/vsmartlogo.png`).
- **Data-leak fixed**: logout wipes all 21 user Hive boxes (`HiveService.clearAll`) AND invalidates
  in-memory user-scoped providers (`SessionController.clearLocalSession`) — no cross-account bleed.
- **Mock-data sweep (2026-06-21)**: every remaining screen that faked data is now backend-driven —
  Refer&Earn (`/referrals`), Family Info (`/credit/family`), KYC dashboard (`/kyc/status`),
  Support conversation (real ticket thread; first message opens a ticket), Notification settings +
  Payment reminders (`/notifications/preferences`), account Recent Payments (`/payments/history`),
  checkout coupon preview (`/coupons/validate`), credit monthly figures. No-backend screens
  (Language, Security) now persist real local prefs (`localeProvider`, `securityPrefsProvider`) and
  the fabricated device/login-history lists were removed. Dead datasources deleted (`dummyjson_*`,
  `order_data_source`, and the unused `*FixtureDataSource` classes → interface-only files).
- **Enterprise states — Phase 1 (global gates, 2026-06-21):** new `lib/features/system/` reads
  `GET /api/v1/app-config` (`appStatusProvider`, fail-open) and a `_BootstrapGate` in `app/app.dart`
  blocks the whole app with **Force-Update** (installed `AppConstants.appVersion` < backend
  `minAppVersion`) or **Maintenance** (backend `maintenance` flag) screens; reusable `NoInternetView`;
  `featureFlagProvider` exposes backend flags; **session-expired** notice on login (`sessionExpiredProvider`
  set on 401-forced logout). Toggle maintenance via a `system.FeatureFlag(key="maintenance")` row.
  REMAINING enterprise work is a roadmap (see §7): Phase 2 = state-completeness on existing screens;
  Phase 3 = new customer modules (reviews, returns/refunds, loyalty, subscriptions, CMS) — need
  backends; Phase 4 = Agent/Admin/Super-Admin apps (backends exist, no Flutter UI yet).
- **Enterprise states — Phase 2 (state completeness, 2026-06-21, partial):** app-wide **offline strip**
  in `app/app.dart` (`_OfflineWrap` watches `connectivityStatusProvider`, animates a top bar in when
  offline — universal offline awareness, no per-screen wiring). Checkout now surfaces the **specific**
  backend error (out-of-stock / credit-ineligible) instead of a generic message. Fixed an
  infinite-loader bug on `outstanding_due_screen` (now has a real error+retry state). **Pull-to-refresh**
  added to 7 list screens: billing invoices/statements/payment-history/collections/outstanding, plus
  today's-deals and coupons-wallet. STILL TODO in Phase 2 (low priority): pull-to-refresh on
  categories/faq/search; per-form inline error polish (auth screens already snackbar on failure).
- **Phase 3 — NEW customer modules (2026-06-21, BUILT & VERIFIED green):** 5 new Django apps +
  5 new Flutter feature modules, end-to-end:
  - **content** (CMS): `Page` model + public `/content/pages[/<slug>]`; `seed_content` cmd seeds
    about/contact/careers/terms/privacy. App: `ContentPageScreen(slug)` → Contact/Careers routes
    (+ reachable from the Account menu; About/Terms/Privacy still use the static screens).
  - **reviews**: `/products/<id>/reviews` (public GET incl. summary+distribution, auth POST
    update_or_create + writes back `Product.rating`/`review_count`), `/reviews/mine`. App:
    `ProductReviewsSection` embedded in product detail (summary, write-review sheet, list).
  - **returns**: `/orders/<code>/returns` (POST, delivered-only), `/returns[/<code>]`. App: My-Returns
    list + Request-Return form; entry from Order Details (delivered) + Account menu.
  - **loyalty**: APPEND-ONLY `PointsLedgerEntry`; `/loyalty`, `/loyalty/ledger`, `/loyalty/redeem`;
    earns on delivery via `orders.services.advance_status` hook (fail-soft). App: Rewards screen.
  - **subscriptions**: `Subscription` model; `/subscriptions` CRUD (+pause/resume/cancel). App:
    Subscriptions screen + "Subscribe & Save" sheet on product detail.
  - Verified: `manage.py check` clean, migrations applied, **36 unit tests + 9 smoke suites green**
    (new `scripts/smoke_phase3.py`), `flutter analyze` clean, APK builds. (Phone was disconnected at
    the end — `adb install -r` the freshly-built APK when it's reconnected.)
- **Phase 4 — IN PROGRESS:** a new **`apps/agent_app`** Flutter app (Riverpod+Dio+go_router, no
  Firebase) was scaffolded with: OTP login (agent-role check via `/agents/me`), Dashboard
  (`/agents/me|performance|earnings`), Deliveries (`/agent/deliveries` + status update), and KYC
  review (`/agent/kyc/queue` + per-step `/agent/kyc/<id>/review`). Backend `KycApplicationSerializer`
  now exposes `id` (needed for the review action). **PAUSED before its `flutter analyze`/build** at the
  user's request to fix user-app issues first. Admin + Super-Admin consoles still not started.
- **Live-test fixes (2026-06-21):** device was running a STALE APK (Phase 3, before the auth-fix
  batch) → the logged 401-storm (no `/auth/refresh`) and address-400 were already fixed in code; the
  current build was rebuilt + installed. Verified token refresh works end-to-end (refresh_token is
  parsed/stored; `/auth/refresh` rotates 200). Hardened `register._saveAddress` to skip POSTing an
  incomplete address (empty line1). JWT access lifetime is 30 min, refresh 30 days.
  NOTE: an old stale session may require ONE more login on first open of the new build (then refresh
  keeps it alive). The Agent app needs an `agent`-role user to log in (create via admin/seed).
- **UX/auth fixes batch (2026-06-21):**
  - **KYC is now OPTIONAL** (was a hard gate that looped users back to `/kyc`): `route_guards.dart`
    `authGuardProvider` returns `approved` for any authenticated+registered user, so they land on
    Home and browse/order freely. KYC is reachable on demand and gated only inside the Credit tab.
  - **Credit tab gating**: `BillingDashboardScreen` shows Apply-for-Credit / Under-Review / Re-apply
    (off `user.kycStatus`) until verified, then the full dashboard.
  - **KYC now persists to backend**: `verification_backend_data_source.submit` sends the real draft
    (masked aadhaar/pan + selfie/residence docs) instead of an empty list — backend `kyc.submit`
    stores them + sets `user.kyc_status=pending`. (Approval still needs agent+admin; that's expected.)
  - **Session survives restarts**: `AuthInterceptor` now REFRESHES the access token on 401 via the
    rotating `/auth/refresh` (concurrency-deduped) and retries, instead of logging out. This fixes
    "reopen → login". Login screen also shows a session-expired notice when a refresh ultimately fails.
  - **Back navigation**: sub-categories moved from the Categories tab branch to a ROOT-level route, so
    back returns to the opener (home rail / categories) instead of exiting/jumping.
  - **Delivery tracking**: order tracking now fetches the real `/orders/<code>/tracking` (agent name,
    ETA, lat/lng) and shows a live "out for delivery" banner (animated pulse) + agent card when an
    agent is assigned (no fabricated agent — needs the Agent app to populate live data).
  - **Splash** is now animated (staggered logo scale/fade → text slide-up → loader).
  - Verified: `flutter analyze` clean, backend check/tests/9 smoke green, APK builds. (Phone was
    disconnected — `adb install -r` the new APK + on-device test the KYC/login/back flows when back.)

---

## 4. RUN

### Backend (dev — SQLite, no Docker) from `C:\knight21\VSMart\apps\backend`
```bash
export DJANGO_SETTINGS_MODULE=config.settings.dev            # bash
.venv/Scripts/python.exe manage.py migrate
.venv/Scripts/python.exe manage.py seed_demo
.venv/Scripts/python.exe scripts/setup_local.py             # test users + stock + prints JWT tokens
.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000   # 0.0.0.0 so a phone can reach it
# verify (all green):
.venv/Scripts/python.exe manage.py test inventory pos orders
for s in smoke_test smoke_money smoke_full smoke_admin smoke_modules smoke_final smoke_pos; do \
  .venv/Scripts/python.exe scripts/$s.py; done
```
Dev master OTP code = **`123456`** (any phone). Always run `manage.py check` after backend edits.

### App on a physical Android phone over USB (the verified path)
```bash
adb reverse tcp:8000 tcp:8000                                # phone 127.0.0.1:8000 → PC backend
cd C:/knight21/VSMart/apps/user_app
flutter build apk --release --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
adb install -r build/app/outputs/flutter-apk/app-release.apk
flutter analyze                                              # must be clean
```
Login with any number + **`123456`**. Keep the phone on USB (connectivity rides the `adb reverse`
tunnel). To stop/restart the server: kill the process on port 8000, then `runserver` again.

---

## 5. CONVENTIONS (match these)
- **Envelope**: every response `{success, message, data, meta?}`; errors `{success:false, message,
  error:{code,message,fields}, type,title,status,detail,instance}` (RFC 9457 members additive).
- **Casing**: auth/user endpoints (`/auth/*`, `/users/me`) snake_case (Flutter models need it);
  everything else camelCase. Don't "fix" auth to camelCase.
- **App data layer**: keep the sync repo interface; new backend datasource (`*BackendDataSource` /
  `*RemoteDataSource`) + **cache-mirror** repo + provider swap. Reads serve the Hive cache; writes
  hit the backend then refresh; hydrate on build. Minimal ripple (no async-ing sync callers).
- **Money/ledgers** append-only, derived+cached+reconciled (`credit/services.py`,
  `inventory/services.py` are the templates). Never UPDATE/DELETE ledger rows.
- **Contract is authoritative**: never rename existing endpoints (Flutter depends on them); add new.
- Don't name an app `collections` (stdlib clash → use `cashcollections`).

## 6. GOTCHAS
- **Android cleartext**: `android/app/src/main/res/xml/network_security_config.xml` permits HTTP to
  dev hosts (127.0.0.1/10.0.2.2/192.168.*). Prod stays HTTPS-only. Build with the `--dart-define`.
- `AppConfig` always inits `AppFlavor.dev`; `AuthController._acceptAnyCredentials=false` (real OTP).
- Windows Firewall blocks inbound 8000 → the USB `adb reverse` tunnel sidesteps it (don't rely on
  the LAN IP unless you opened the firewall as admin).
- Smoke scripts print to cp1252 — keep labels ASCII or set `PYTHONIOENCODING=utf-8`.
- Each app change = `flutter analyze` clean → rebuild APK → `adb install -r`. Re-assert
  `adb reverse` after a reconnect.

## 7. WHAT'S LEFT — infra/credentials only (no more code to write)
- **Credentials you provide**: Razorpay (`RAZORPAY_KEY_ID/_SECRET/RAZORPAY_WEBHOOK_SECRET`), MSG91
  (`SMS_PROVIDER=msg91` + `MSG91_AUTH_KEY` + `MSG91_OTP_TEMPLATE_ID`), FCM (`FCM_SERVER_KEY`). All
  code-ready — setting the env vars activates them.
- **Infra (optional)**: WebSocket/ASGI (Channels + Redis) to replace the 12s tracking poll; a real
  LAN/prod host (Postgres via `DATABASE_URL`, Caddy/HTTPS) instead of the USB tunnel; Celery beat to
  schedule `release_expired_reservations` + statement/reminder jobs; backups, Sentry DSN, monitoring.
- **Minor**: a fully server-authoritative cart *summary* (the app cart summary is computed
  client-side, reconciled to the server at checkout — order totals are already server-authoritative).
  Full app **i18n** (the Language screen persists the chosen locale but translation `.arb` assets
  aren't wired, so UI strings stay English). Server-side **security** (password/2FA/session list)
  is intentionally absent — VS Mart is OTP-only; the Security screen exposes only real local prefs.

## 8. KEY DOCS
`apps/backend/docs/` (00-overview … 11-pos-inventory, api/ generated OpenAPI/Swagger/Postman) and
the auto-memory files (vsmart-backend, vsmart-screen-build-workflow, vsmart-android-build-config).
