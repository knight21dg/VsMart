# 01 · Architecture

## Topology (one VPS, Docker Compose)

```
                    Clients (off-VPS)
   Customer app · Agent app  ·  Admin web browser
                      │  HTTPS
                      ▼
            ┌───────────────────────┐
            │  Caddy (reverse proxy)│  auto-TLS, gzip, routes /api + /admin + /media
            └───────────┬───────────┘
                        ▼
            ┌───────────────────────┐        ┌──────────────────────┐
            │  Django + DRF (api)   │◀──────▶│ Celery worker + beat │
            │  Gunicorn, JWT, RBAC  │        │ statements, reminders│
            └───┬─────────┬─────────┘        └─────────┬────────────┘
                │         │                            │
        ┌───────▼──┐  ┌───▼────┐  ┌──────────┐         │
        │ Postgres │  │ Redis  │  │  MinIO   │◀────────┘
        │ (data)   │  │(cache, │  │ (files)  │
        │          │  │ broker)│  └──────────┘
        └──────────┘  └────────┘

   External: SMS gateway (OTP)  ·  Payment gateway (Razorpay) + webhooks
```

Containers: `caddy`, `api` (gunicorn), `worker` (celery), `beat` (celery beat),
`db` (postgres), `redis`, `minio`. See [`05-deployment.md`](05-deployment.md).

## Request lifecycle

1. Client sends HTTPS request with `Authorization: Bearer <access_jwt>`.
2. Caddy terminates TLS → proxies to Gunicorn/Django.
3. DRF authenticates the JWT (SimpleJWT), resolves `request.user` + `role`.
4. A **permission class** checks role + object ownership/scope.
5. View runs inside a DB transaction where money is touched; writes go through
   **service functions** (not fat views) so business rules live in one place.
6. Side effects (SMS, push, statement generation) are queued to Celery, not done inline.
7. Response serialized as JSON envelope (see API spec).

## Layering (Django apps)

Each domain module is a Django app under `vsmart/apps/`:

```
config/            # settings (split: base/dev/prod), urls, asgi/wsgi, celery
core/              # shared: base models, pagination, exceptions, permissions, audit
accounts/          # users, roles, auth (otp/jwt), devices, audit log
kyc/               # applications, documents, verification steps, review workflow
catalog/           # categories, products, variants, images, reviews, search
cart/              # cart, cart items, wishlist
addresses/         # addresses
orders/            # orders, items, status timeline, delivery assignment, tracking
credit/            # credit accounts, ledger, statements, family/shared limit, VS score
payments/          # payments, gateway integration, webhooks, cash collection
offers/            # banners, deals, coupons, redemptions
notifications/     # inbox, device tokens, preferences
support/           # tickets, messages, faqs
referrals/         # referral codes & rewards
ops/               # admin dashboards, reports, manual overrides (admin-only views)
```

**Rule of thumb:** views/serializers per app; cross-app business logic in
`<app>/services.py`; never let a serializer mutate the credit ledger directly.

## Key technical decisions

- **Money is integer paise** (or `Decimal` with fixed scale), never float. Store the
  credit ledger as **append-only rows**; `available`/`outstanding` are derived (and
  cached) from the ledger, never edited in place.
- **Idempotency:** payment and order-create endpoints accept an `Idempotency-Key`
  header; a unique table prevents double-charges/double-orders on retry.
- **Transactions:** order placement + ledger debit + stock decrement happen in one
  `transaction.atomic()` block; partial failures roll back.
- **Webhooks:** payment-gateway webhooks are verified by signature, stored raw, and
  processed idempotently (a payment is only ever finalized by the webhook, not the
  client "success" callback).
- **Audit log:** every staff (admin/agent) write that affects a customer's money, KYC,
  or account state is recorded in `accounts.AuditLog` (actor, action, target, before/after).
- **Soft deletes** for catalog/users (`is_active`), hard deletes avoided for anything
  referenced by orders/ledger.
- **API versioning:** all routes under `/api/v1/`. Breaking changes → `/api/v2/`.
- **Pagination:** cursor or limit/offset, default page size 20 (matches app).
- **Time:** store UTC; the app localizes. Credit cycle cutoffs computed in IST.

## Environments

`dev` (local Docker), `staging` (VPS, test gateway keys), `prod` (VPS, live keys).
The Flutter app already has matching flavors:
`dev-api.vsmart.app` / `staging-api.vsmart.app` / `api.vsmart.app`.

## Scaling path (later, not now)

1. Move Postgres to a managed instance (first thing to outgrow a single VPS).
2. Add a read replica for reporting/dashboards.
3. Horizontal API replicas behind Caddy; Redis stays shared.
4. Object storage → Cloudflare R2 / S3.
