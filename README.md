# VS Mart

Grocery commerce + **BNPL credit** platform (fintech) for the Indian market. Single-tenant —
VS Mart owns every store; this is not a marketplace. Owner: Knight21 Digi Hub.

**Live:** [thevsmart.com](https://thevsmart.com) · [admin.thevsmart.com](https://admin.thevsmart.com) ·
[store.thevsmart.com](https://store.thevsmart.com) · [api.thevsmart.com](https://api.thevsmart.com)

New to the project? Read **[HANDOFF.md](HANDOFF.md)** — it is the single bootstrap document and
covers the whole system in depth. This README is only the map.

---

## The six surfaces

| Path | Surface | Stack | Notes |
|---|---|---|---|
| `apps/backend` | REST API + admin | Django 5 · DRF · Postgres · Channels | 41 apps, ~573 routes, ~1,230 tests |
| `apps/user_app` | Customer mobile app | Flutter 3.32 / Dart 3.8 | 384 Dart files; fully backend-driven |
| `apps/agent_app` | Field-agent mobile app | Flutter | Delivery, cash collection, KYC field verification |
| `apps/admin` | Super-admin console | Next.js 16 · Tailwind · shadcn | 52 pages, platform-wide |
| `apps/store-admin` | Store panel | Next.js · offline-capable PWA | 29 pages, scoped to ONE store; includes POS |
| `apps/vsmartlanding` | Marketing site | Next.js | Public site + customer web sign-in and `/account` |

Supporting: `docs/` (specs, QA tracker, user guides), `scripts/` (release gate), `VS Mart Design/`
(63 client mockups, authoritative for customer-app screens), `Caddyfile` + `docker-compose.yml`
(production topology).

## What the platform does

**Commerce** — catalog with per-variant stock, cart, checkout, coupons, orders, returns, reviews,
loyalty points, referrals.
**Credit (BNPL)** — application → review → grant, append-only credit ledger, statements, invoices,
repayment, CIBIL score checks, dunning. VS Mart cannot lend on its own books; the model is an RBI
NBFC/LSP partnership (see [HANDOFF.md §9](HANDOFF.md)).
**Fulfilment** — polygon-based serviceability zones route an order to a store; dispatch engine
batches and assigns deliveries; agents deliver with a 50 m arrival geofence, OTP and mandatory
proof-of-delivery photo.
**Cash recovery** — collection tasks, OTP-confirmed collection, partial payments, disputes, agent
cash deposit → finance verification → general ledger.
**Store operations** — POS (offline-capable), purchase entry, GRN, inventory ledger, field
verification queue, reports.

## Quick start (local development)

```bash
# Backend — from apps/backend
export DJANGO_SETTINGS_MODULE=config.settings.dev
.venv/Scripts/python.exe manage.py migrate
.venv/Scripts/python.exe manage.py seed_demo
.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000

# Customer app — from apps/user_app
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1

# Consoles — from apps/admin (:3000) or apps/store-admin (:3001)
npm install && npm run dev
```

Dev OTP for any phone number is **`123456`**. Full setup, seeded logins and the physical-device path
are in [HANDOFF.md §5](HANDOFF.md).

## Testing

```bash
cd apps/backend && .venv/Scripts/python.exe manage.py test    # ~1,230 tests
cd apps/user_app  && flutter test && flutter analyze
cd apps/agent_app && flutter test && flutter analyze
./scripts/release_gate.sh                                      # hard gates before a release
```

## Deployment

One VPS runs everything behind Caddy (automatic HTTPS). See **[DEPLOY.md](DEPLOY.md)**.

```bash
cd /opt/vsmart && git pull && docker compose up -d --build
docker compose up -d scheduler      # periodic jobs — easy to forget after a deploy
```

## Documentation map

| Document | What it covers |
|---|---|
| [HANDOFF.md](HANDOFF.md) | **Start here.** Full system state, conventions, invariants, blockers, runbook |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the pieces fit; the invariants you must not break |
| [PROJECT_STATUS.md](PROJECT_STATUS.md) | Module-by-module readiness and known blockers |
| [CHANGELOG.md](CHANGELOG.md) | Every notable engineering change, newest first |
| [DEPLOY.md](DEPLOY.md) | Production deployment and operations |
| [apps/backend/docs/](apps/backend/docs/) | Backend deep-dives: data model, API spec, RBAC, POS/inventory, realtime, zones |
| [docs/QA_TRACKER.md](docs/QA_TRACKER.md) | Per-test-case QA status |
| [docs/ASSUMPTIONS.md](docs/ASSUMPTIONS.md) | Decisions taken without client confirmation |

## Conventions that bite

- Every response is an envelope: `{success, message, data, meta?}`.
- **Casing is split**: `/auth/*` and `/users/me` are snake_case; everything else is camelCase. Do not
  "fix" auth to camelCase — the Flutter models depend on it.
- Ledgers (credit, inventory, loyalty) are **append-only**. Never UPDATE or DELETE a ledger row.
- Never rename an existing endpoint — shipped app builds depend on it. Add a new one.
- Anything store-scoped must filter by store. Four separate store-scope leaks have been found and
  fixed; use `agents/candidates.py` for agent pickers rather than writing a new query.

Full list in [HANDOFF.md §6](HANDOFF.md).

---

Proprietary. © Knight21 Digi Hub. All rights reserved.
