# VS Mart — Full-System Handover

The single bootstrap document. Read this and you have enough context to pick up any part of the
platform. Everything else is a deep-dive linked from here.

**Snapshot date: 2026-08-07.** Supersedes the 2026-06-21 revision and the backend-only
`apps/backend/docs/HANDOFF.md`.

---

## 1. What VS Mart is

A grocery commerce platform with an embedded **BNPL credit** product, operating in India. Customers
browse and order groceries; approved customers buy on credit and repay against a statement. Field
agents deliver the orders and recover the cash.

It is **single-tenant** — VS Mart owns and operates every store. There are no third-party sellers,
so there is no marketplace payout logic, no seller onboarding, and no commission engine. Owner:
Knight21 Digi Hub.

Four human roles run through the system: **customer**, **field agent**, **store staff** (scoped to
one store), and **super-admin** (platform-wide).

---

## 2. Repo layout

```
C:\knight21\VSMart\                 (git: github.com/knight21dg/VsMart)
  apps/backend/          Django 5 + DRF — the whole API and business logic
  apps/user_app/         Flutter customer app
  apps/agent_app/        Flutter field-agent app
  apps/admin/            Next.js super-admin console
  apps/store-admin/      Next.js store panel (incl. POS)
  apps/vsmartlanding/    Next.js marketing site + customer web sign-in
  docs/                  Specs, QA tracker, PDF user guides
  scripts/release_gate.sh
  VS Mart Design/        63 client PNG mockups — authoritative for customer-app screens
  docker-compose.yml, Caddyfile, .env.example
```

`apps/user_app` and `apps/vsmartlanding` were standalone nested git repos until 2026-08-07. They are
now ordinary directories in this monorepo; their prior independent histories were dropped
deliberately. Their own `.gitignore` files still apply on top of the root one.

On Windows: use the **Bash tool (Git Bash)** for POSIX shell, **PowerShell** for Windows-specific
operations.

---

## 3. State at a glance

Test counts below were run on **2026-08-07** and are real, not estimates.

| Surface | Size | Tests | State |
|---|---|---|---|
| `apps/backend` | 41 Django apps · 124 migrations · ~573 routes | **1,229 green** | Production; the most complete surface |
| `apps/user_app` | 384 Dart files | **165 green**, analyze clean | Live on Android; fully backend-driven |
| `apps/agent_app` | 77 Dart files | **76 green**, analyze clean | Live on Android; field-hardened 2026-08-04 |
| `apps/admin` | 52 pages | — | Deployed; no automated tests |
| `apps/store-admin` | 29 pages | — | Deployed; offline-capable POS |
| `apps/vsmartlanding` | 34 components/routes | — | Deployed; customer sign-in added 2026-08-04 |

Production is **live** on a single VPS (`187.127.153.152`) behind Caddy with automatic HTTPS:
`thevsmart.com`, `admin.`, `store.`, `api.` — all serving.

---

## 4. What is built

### 4.1 Commerce core — mature
Catalog with **per-variant stock** (a variant is a separately-stocked SKU with its own stock, image,
MRP and barcode — not a label on a shared pool), cart, checkout, coupons, orders, returns, reviews,
loyalty points, referrals.

Hardened over several audit passes: order and payment **idempotency keys** with unique constraints,
stock **reservations** at checkout released by a TTL sweep, oversell guards, coupon concurrency
limits, and a `reconcile_finance` audit command. The order lifecycle, refunds and payment recovery
were reworked 2026-07-21.

The **inventory ledger is append-only** — stock is never written directly. `InventoryService.
post_movement` is the sole writer and available stock = Σledger − reserved. `.save()`/`.delete()`
guards enforce this at the model layer.

### 4.2 Credit (BNPL) — mature, but see the RBI constraint in §9
Application → review → grant, with an explicit limit. **KYC approval is decoupled from the credit
grant** — only an approved `CreditApplication` carrying an explicit limit sets `credit_enabled`. Do
not re-fuse these; they were deliberately separated.

Append-only credit ledger, statements, invoices with real GST/HSN, repayment (including partial),
payment receipts as PDFs, dunning and aging. A 2026-07-22 defect sweep fixed repayment **losing
money** on overpayment and a dashboard that summed a paginated ledger to produce a wrong
outstanding balance — `getCreditSummary` is now the authoritative source.

**CIBIL score** checks are wired to the Payon API with append-only history and admin refresh. See
§9 — currently blocked on the provider.

### 4.3 Zones, serviceability and store routing — complete
Polygon-based serviceability: Customer → Zone → Store → Inventory → Order. Pure-Python
point-in-polygon (no PostGIS dependency). The customer app hard-locks behind device GPS when out of
coverage and captures expansion interest. Catalog is store-scoped, and stores can browse and share
their **private** products via unguessable `share_token` deep links.

### 4.4 Fulfilment and dispatch — Phase 1–2 done
Delivery state machine with assignment, a **50 m arrival geofence**, delivery-OTP with lockout,
mandatory proof-of-delivery photo, failed/reattempt/return-to-store, agent earnings, and a full
audit timeline.

A Blinkit-style **dispatch engine** batches orders, optimises routes, folds collections onto a
route, and scores agents. Phases 1 (backend: `DeliveryBatch`/`BatchStop`, `assignment_engine`,
`/store/dispatch/*`, `run_dispatch`) and 2 (store dashboard) are deployed. Phases 3–4 are not built.

Real-time dispatch and customer order tracking run over Django Channels (ASGI/daphne) with JWT WS
auth and a polling fallback.

### 4.5 Cash recovery — complete
Collection task state machine, auto and manual assignment, OTP lockout, full and **partial**
collection feeding credit repayment plus a receipt, disputes, dunning/aging and agent performance.
Collected cash then flows: agent deposit → finance verification → **double-entry general ledger**
(chart of accounts, journal, trial balance, P&L, balance sheet). Before the cash book existed,
nothing tracked physical notes.

### 4.6 Store operations — complete
The store panel is scoped to exactly one store via `StoreStaff` and a permission catalog. It covers
POS (with an **offline** mode: IndexedDB cache + outbox + idempotent sync), purchase entry, GRN,
inventory, field verification, collections, returns, reports and audit. Order/customer-360/return/KYC
detail drawers were added in the fulfilment sprint.

### 4.7 KYC and media — code complete, credentials pending
API-based government-source verification on a manual-review app: PAN, Aadhaar OTP-eKYC, DigiLocker
and bank. Signzy is the primary adapter (Cashfree, Setu and a mock are swappable via `kyc_provider`).
DPDP consent, duplicate-fraud detection, and deliberately **RBI-safe**: it informs the reviewer, it
never auto-grants credit.

Media is **self-hosted** via the `mediastore` app — WebP pipeline, public/private split,
permission-gated serving with X-Accel. The engine and all consumers are done and verified.

### 4.8 Notifications and messaging
- **SMS is LIVE** through smslogin.co (sender `VSMRTS`) since 2026-08-05, with per-purpose DLT
  templates.
- **FCM push** works end to end in the customer app: backend HTTP v1 via `firebase-admin`,
  dead-token cleanup, branded channels, foreground display and tap routing. Needs prod Firebase
  credentials. **`agent_app` has no Firebase integration at all** — store-triggered notifications
  reach it as inbox rows only.
- Deep links (App Links / Universal Links) are implemented and correctly parked-and-replayed past
  the splash, auth and serviceability gates. Blocked on §9 credentials.

### 4.9 Cross-cutting
- **Actionable response framework**: a machine-readable catalog of **267 response codes across 25
  modules** (`core/response_codes.py`), raised as `AppError("CODE")`, surfaced to the app as a
  navigate/logout/retry/toast/dialog instruction via `presentFailure`. No surface should ever show
  "Something went wrong."
- **Localization**: customer app is en/te/hi with language-aware fonts. Catalog *content*
  (names/descriptions) localizes through per-language DB columns resolved server-side, not ARB — the
  engine works but the columns are largely empty, so it still looks untranslated.
- Banners, coupons and campaigns run through the `offers` app with one geometry source
  (`PLACEMENT_SPECS`) mirrored in Dart, aspect-locked cropping, store-scoped submission and admin
  approval.

---

## 5. Running the system

### Backend (dev — SQLite, no Docker), from `apps/backend`
```bash
export DJANGO_SETTINGS_MODULE=config.settings.dev
.venv/Scripts/python.exe manage.py migrate
.venv/Scripts/python.exe manage.py seed_demo          # catalog, offers, FAQs, coupons
.venv/Scripts/python.exe scripts/setup_local.py       # test users + stock; prints JWTs
.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000
.venv/Scripts/python.exe manage.py test               # 1,229 tests, ~19s with --parallel 4
```
Run `manage.py check` after any backend edit.

### Mobile apps
```bash
cd apps/user_app   # or apps/agent_app
flutter test && flutter analyze                       # analyze must be clean
flutter build apk --release --dart-define=API_BASE_URL=https://api.thevsmart.com/api/v1
```
Against a local backend on a USB-tethered phone, `adb reverse tcp:8000 tcp:8000` and use
`http://127.0.0.1:8000/api/v1` — this sidesteps Windows Firewall, which blocks inbound 8000. Android
release builds need **NDK 27 and minSdk 23** (Firebase); the pins are already in the Gradle config.

### Consoles
```bash
cd apps/admin && npm install && npm run dev           # :3000
cd apps/store-admin && npm install && npm run dev     # :3001
```

### Demo logins
Dev/demo OTP is **`123456`** for any number (`OTP_DEV_BYPASS_CODE`). Super-admin `+919999999999`;
store staff `9100000001`–`9100000004`. **This is a login backdoor** — blank it out before real
customers are on the system.

---

## 6. Conventions you must match

- **Response envelope** — every response is `{success, message, data, meta?}`. Errors add
  `{error:{code,message,fields}}` plus RFC 9457 members (`type`, `title`, `status`, `detail`,
  `instance`) additively.
- **Casing is split, on purpose** — `/auth/*` and `/users/me` are **snake_case**; every other
  endpoint is **camelCase**. The Flutter models depend on this. Do not "fix" auth.
- **Never rename an existing endpoint.** Shipped APKs depend on them. Add a new one instead.
- **Ledgers are append-only** — credit, inventory and loyalty points. Never UPDATE or DELETE a row;
  post a compensating entry. `credit/services.py` and `inventory/services.py` are the templates.
- **App data layer** — keep the sync repository interface; add a `*BackendDataSource` plus a
  cache-mirror repo and swap the provider. Reads serve the Hive cache, writes hit the backend then
  refresh, hydrate on build. This avoids async-ing every sync caller.
- **Store scoping is a security boundary, not a filter.** Anything a store touches must be scoped to
  that store. Use `agents/candidates.py::candidate_agents(store=…)` / `assignable_agents` for agent
  pickers — four separate store-scope leaks have been found and fixed, all from hand-rolled queries.
- Never name a Django app `collections` (stdlib clash) — hence `cashcollections`.
- Store-admin request bodies are camelCase-parsed via `io_utils.field`; phones are **E.164**.

---

## 7. Gotchas that have cost real time

- **smslogin.co returns HTTP 200 on failure** and will happily answer the *balance* query when your
  send parameters are wrong. You must read the response body to know whether an SMS was sent. The
  DLT template id and body are a **matched pair** — changing one without the other silently fails.
- **`has_usable_password()` reads a blank password as usable** — do not gate password-reset
  eligibility on it. Gate by role.
- **Payon (CIBIL) reseller keys need `reseller.apipayon.in`**, not the bare host — the bare host
  answers "Invalid API key". Success status is `"VERIFIED"`, not `"SUCCESS"`; the band field is
  `scoreCategory`. A value set in the super-admin panel **overrides the env var**.
- **JWT refresh rotation was deliberately REMOVED** (2026-07-22). The refresh token is reusable for
  30 days; logout still blacklists. Access lifetime is 30 minutes. Do not re-introduce rotation
  without understanding why it was removed.
- **Banner resizing happens server-side** — the cropper returns a rectangle, not a blob. Do not
  "fix" it to upload a cropped image.
- **The `scheduler` compose service is what runs periodic jobs.** Before it existed, nothing ran
  crons at all. `docker compose up -d scheduler` after every deploy.
- **Serviceability locks only engage when `stage == approved`** — otherwise a new out-of-area
  registration deadlocks between the lifecycle redirect to `/register` and the serviceability
  redirect to `/not-serviceable`.
- **A stale APK will lie to you.** More than one "backend bug" has turned out to be an old build on
  the test phone. Reinstall before debugging.
- Smoke scripts print through cp1252 — keep labels ASCII or set `PYTHONIOENCODING=utf-8`.

---

## 8. Production

Topology, DNS, first-boot and operations are in **[DEPLOY.md](DEPLOY.md)**. In brief:

One VPS (`187.127.153.152`, Ubuntu 24.04), Docker Compose at `/opt/vsmart`, Caddy terminating TLS
for four hostnames. Services: `db` (Postgres 16), `redis`, `backend` (gunicorn/daphne), `scheduler`,
`admin`, `store-admin`, `landing`, `caddy`.

```bash
cd /opt/vsmart && git pull && docker compose up -d --build
docker compose up -d scheduler
docker compose exec db pg_dump -U vsmart vsmart > backup_$(date +%F).sql   # before migrations
```

SSH key: `C:\Users\PARDHU\.ssh\vsmart_deploy`. Note that Git Bash's `HOME` is corrupted on this
machine, so pass the key path explicitly rather than relying on `~/.ssh`.

APK install links are served off disk by Caddy at `/userapp` and `/agentapp` — stable short URLs
that survive a filename change. The APK binaries are **not** committed (a ~78 MB binary per build
would balloon the repo); they live in the `downloads` volume.

---

## 9. External blockers — cannot be resolved from the code

| Blocker | What is needed | Impact |
|---|---|---|
| **Razorpay live keys** | `RAZORPAY_KEY_ID` / `_SECRET` / `_WEBHOOK_SECRET` | Payments run in mock mode; no real online refunds |
| **Firebase prod credentials** | Service account JSON | No production push notifications |
| **Payon CIBIL permission** | Provider must enable credit-score on the account | Score check returns "Permission denied"; host and key are now correct |
| **Signzy KYC keys + paths** | Sandbox or live credentials | KYC verification cannot run against real government sources |
| **Google Maps API key** | Android key in the manifest | Order tracking map and place search are inert |
| **Play SHA-256 + Apple Team ID** | From Play Console / Apple Developer | Deep links cannot be verified by the OS |
| **RBI lending partner** | An NBFC/LSP agreement | VS Mart **cannot lend on its own books**. No pass-through account; 5% FLDG cap; prescribed collections rules. The LSP restructuring is a separate commercial track and does not block engineering |
| **Physical devices** | Handsets for QA | Integration, performance, battery and FPS passes are unautomatable here |

---

## 10. What is left

**Operational, not code:**
- `rehost_catalog_images` has not been run in production; prod Caddy still needs the X-Accel block
  and a `media_cleanup` cron.
- Catalog localization columns are empty — content needs translating and loading.
- The `subscriptions` feature was removed (it was a write-only table); the `DeleteModel` migration
  has shipped, but the app folder and the `INSTALLED_APPS` line still need deleting once it is
  applied everywhere.
- `geography` app and `orders.DeliveryAssignment` are flagged legacy-dead and should be removed.

**Code:**
- Dispatch engine Phases 3–4.
- Commerce audit items still open: cancel-without-refund, a formal order state machine, payment
  callback verification, and reconciliation.
- Invoice numbering is not yet a compliant GST series.
- `agent_app` has no Firebase/push integration.
- Admin and store consoles have no automated test coverage.

---

## 11. Where to look next

| Topic | Document |
|---|---|
| Architecture and invariants | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Module readiness, blockers | [PROJECT_STATUS.md](PROJECT_STATUS.md) |
| Change history (detailed, newest first) | [CHANGELOG.md](CHANGELOG.md) |
| Deployment and ops | [DEPLOY.md](DEPLOY.md) |
| Backend deep-dives | `apps/backend/docs/` — overview, architecture, data model, API spec, RBAC, deployment, decisions, super-admin control plane, API contract, POS/inventory |
| Response codes | `apps/backend/docs/API_RESPONSE_CODES.md` |
| Realtime / WebSockets | `apps/backend/docs/REALTIME.md` |
| Zone enforcement | `apps/backend/docs/ZONE_ENFORCEMENT.md` |
| Banners | `apps/backend/docs/BANNER_SPEC.md` |
| QA status | [docs/QA_TRACKER.md](docs/QA_TRACKER.md) |
| Unconfirmed decisions | [docs/ASSUMPTIONS.md](docs/ASSUMPTIONS.md) |
| iOS pipeline | [CODEMAGIC_IOS.md](CODEMAGIC_IOS.md) · Play: [PLAY_CONSOLE_VSMART.md](PLAY_CONSOLE_VSMART.md) |
| Maps setup | [MAPS_SETUP.md](MAPS_SETUP.md) |

There is also a working agent memory at
`C:\Users\PARDHU\.claude\projects\C--knight21-VSMart\memory\` that carries per-topic context beyond
what is committed here.
