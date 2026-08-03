# VS Mart — Backend

Backend API and admin platform for **VS Mart**, a B2B grocery + **credit (BNPL)** app.
Serves the Flutter customer app, a Flutter agent flow, and a web admin console, with
four roles: **superadmin, admin, agent, customer**.

> Status: **Enterprise scope implemented & verified.** 25 Django apps, **62 models,
> 462 URL patterns**, migrating clean and passing **6 end-to-end smoke suites**
> (`scripts/smoke_*.py`: auth, money, full, admin/control-plane, modules, final).
> Aligned to the enterprise architecture as a modular monolith — see
> [`docs/09-enterprise-alignment.md`](docs/09-enterprise-alignment.md) and the
> Flutter-authoritative [`docs/10-api-contract.md`](docs/10-api-contract.md).
>
> Modules: accounts/auth · users · geography · kyc · credit · catalog · inventory ·
> cart · orders · payments · billing · cashcollections · delivery · verification ·
> agents · notifications · offers · referrals · support · siteconfig · zones · ops
> (analytics+staff+customer-360+inventory-adjust+audit) · reports (CSV/Excel/PDF) ·
> system (version/app-config/maintenance/feature-flags/uploads/global-search/feedback).
>
> **Contract notes:** response envelope is `{success, message, data, meta}`; the
> **auth/user** endpoints return **snake_case** (access_token/refresh_token/kyc_status,
> string `id`) per the Flutter models, everything else camelCase. Existing app paths
> are preserved (no renames); new admin/agent features are new endpoints.
>
> Remaining before production: swap mock payment gateway → Razorpay keys, SMS console →
> MSG91, wire MinIO signed URLs (uploads/KYC), schedule statement/reminder Celery jobs,
> move to Postgres. See [`docs/06-roadmap.md`](docs/06-roadmap.md).
>
> **Verified flows:** OTP→JWT→profile · catalog · cart+GST bill · COD/credit checkout ·
> **append-only credit ledger** (debit on purchase, repay via webhook, agent cash
> collection, `SUM(ledger)==outstanding` invariant) · KYC submit→agent review→admin
> approve→credit enabled · offers/coupons · notifications · support · referrals ·
> admin dashboard/staff/customer-360 · RBAC (customer blocked from `/admin/*`).
>
> Run the suites: `python scripts/smoke_test.py`, `scripts/smoke_money.py`,
> `scripts/smoke_full.py`, `scripts/smoke_admin.py`.
>
> **Superadmin control plane** (see [`docs/08-superadmin-control-plane.md`](docs/08-superadmin-control-plane.md)):
> runtime money config (GST, delivery, **platform fee**) editable by superadmin;
> **delivery zones** (center+radius_km, per-zone fee overrides, serviceability check);
> analytics (GMV/revenue/sales-trend/top-products/zone sales); inventory (stock +
> adjust-with-audit); admin credit limit/freeze. Money levers are superadmin-only
> (admin gets a verified 403).

## Run it now (dev, SQLite — no Docker needed)

```bash
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt   # or: pip install Django djangorestframework djangorestframework-simplejwt django-environ djangorestframework-camel-case django-cors-headers django-filter
.venv/Scripts/python manage.py migrate
.venv/Scripts/python manage.py seed_demo
.venv/Scripts/python manage.py createsuperuser     # first superadmin → /admin/
.venv/Scripts/python manage.py runserver           # API at http://127.0.0.1:8000/api/v1/
.venv/Scripts/python scripts/smoke_test.py         # end-to-end check
```
OTP codes print to the server console in dev (`SMS_PROVIDER=console`).

## Tech stack (decided)

| Concern | Choice | Why |
|---|---|---|
| Language / framework | **Python · Django 5 + Django REST Framework** | Free, production-grade admin panel for superadmin/admin/agent management; mature, safe for money. |
| Database | **PostgreSQL 16** | ACID transactions + append-only credit ledger. |
| Cache / queue / OTP | **Redis 7** | OTP store, rate-limiting, cache, Celery broker. |
| Background jobs | **Celery + Celery Beat** | Statements, due-date reminders, payment alerts. |
| Object storage | **MinIO** (S3-compatible, self-hosted) or Cloudflare R2 | KYC docs, product images. |
| Auth | **JWT** (access + refresh) via `djangorestframework-simplejwt` | Stateless, role claims, refresh rotation. |
| Edge / TLS | **Caddy** (auto-HTTPS) | One entry point, free certs. |
| Deploy | **Docker Compose** on a single VPS | Cheap, simple, reproducible. |
| SMS (OTP) | MSG91 / Fast2SMS (India) | +91 numbers. |
| Payments | Razorpay / Cashfree | UPI + cards + webhooks. |

Swappable later: the framework box (NestJS / Laravel) without changing the rest of
the architecture. The choice above optimizes for shipping a multi-role admin-heavy
fintech app solo.

## Documents

Read in order:

1. [`docs/00-overview.md`](docs/00-overview.md) — product scope, modules, glossary.
2. [`docs/01-architecture.md`](docs/01-architecture.md) — components, request flow, topology.
3. [`docs/02-data-model.md`](docs/02-data-model.md) — full database schema (the source of truth).
4. [`docs/03-api-spec.md`](docs/03-api-spec.md) — REST endpoints (customer + agent + admin).
5. [`docs/04-rbac.md`](docs/04-rbac.md) — roles & permission matrix.
6. [`docs/05-deployment.md`](docs/05-deployment.md) — Docker, VPS, env, backups, CI/CD.
7. [`docs/06-roadmap.md`](docs/06-roadmap.md) — phased implementation plan.

## API contract

The customer API mirrors the contract the Flutter app already calls
(`apps/user_app/lib/app/constants/api_constants.dart`), served under **`/api/v1`**.
Once the auth + catalog endpoints are live, the app drops its demo OTP bypass
(`AuthController._acceptAnyCredentials = false`) and points `AppConfig.apiBaseUrl` at
the server.

## Quickstart (once implemented)

```bash
cp .env.example .env          # fill secrets
docker compose up -d --build  # api, db, redis, worker, minio, caddy
docker compose exec api python manage.py migrate
docker compose exec api python manage.py createsuperuser   # first superadmin
```

Admin console: `https://<host>/admin/` · API: `https://<host>/api/v1/`
