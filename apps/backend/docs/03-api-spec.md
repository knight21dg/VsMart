# 03 · API Specification

Base URL: **`/api/v1`**. JSON only. Auth via `Authorization: Bearer <access>`.

## Conventions

- **Response envelope** (matches the app's `_data()` unwrapper):
  ```json
  { "data": { ... }, "meta": { "page": 1, "page_size": 20, "total": 194 } }
  ```
  Lists return `data: [ ... ]` + `meta`. Single objects return `data: { ... }`.
- **Errors**:
  ```json
  { "error": { "code": "invalid_otp", "message": "Invalid code. Please try again.", "fields": {} } }
  ```
  HTTP status reflects the class (400/401/403/404/409/422/429/500).
- **Auth header** on all but the public auth/catalog reads.
- **Idempotency**: send `Idempotency-Key: <uuid>` on `POST /checkout`, `POST /payments`,
  `POST /credit/repay`.
- **Pagination**: `?page=&page_size=` (default 20) or `?cursor=`. `?q=` for search.
- **Roles** noted as 🟢 customer · 🟡 agent · 🔵 admin · 🟣 superadmin (cumulative upward).

---

## Auth & account — `accounts`  (matches app contract)

| Method | Path | Role | Body / notes |
|---|---|---|---|
| POST | `/auth/otp/send` | public | `{phone}` → `{verification_id}`. Rate-limited. |
| POST | `/auth/otp/verify` | public | `{phone, otp, verification_id}` → `{access, refresh, is_new_user, user}` |
| POST | `/auth/register` | 🟢(new) | `{name, email?}` → `{user}` (completes profile after first OTP) |
| POST | `/auth/refresh` | public | `{refresh}` → `{access, refresh}` (rotation) |
| POST | `/auth/logout` | 🟢 | revokes refresh / device token |
| GET | `/users/me` | 🟢 | current profile + role + kyc_status + credit summary |
| PATCH | `/users/me` | 🟢 | `{name?, email?, avatar?}` |
| POST | `/notifications/device-token` | 🟢 | `{token, platform}` |

> **OTP flow:** server generates 6-digit code, stores `hash` in Redis (TTL 5 min, max 5
> attempts), sends via SMS gateway. Verify issues JWT. `is_new_user=true` routes the app
> to register → KYC.

---

## KYC — `kyc`

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/kyc/status` | 🟢 | application + per-step status |
| POST | `/kyc/submit` | 🟢 | multipart: documents (aadhaar/pan/selfie/residence); creates/updates application → `pending` |
| GET | `/kyc/documents/{id}/url` | 🟢🟡🔵 | short-lived signed MinIO URL |
| **Agent/Admin review** | | | |
| GET | `/agent/kyc/queue` | 🟡 | applications assigned / in area, `pending` |
| POST | `/agent/kyc/{id}/review` | 🟡🔵 | `{step, decision:approve\|reject, note}` |
| POST | `/admin/kyc/{id}/decision` | 🔵 | final approve → sets `user.kyc_status=verified`, enables credit |

---

## Catalog — `catalog`  (public reads)

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/categories` | public | departments (top-level) |
| GET | `/categories/{id}/sub-categories` | public | children (empty ⇒ app shows products) |
| GET | `/products` | public | `?category=&page=&sort=&min_price=&brand=` |
| GET | `/products/{id}` | public | detail + images + variants + specs |
| GET | `/products/search` | public | `?q=` full-text |
| GET | `/offers` | public | `?type=banner\|deal\|coupon` |
| **Admin** | | | |
| POST/PATCH/DELETE | `/admin/products` `…/{id}` | 🔵 | CRUD (also available in Django admin) |
| POST/PATCH/DELETE | `/admin/categories` | 🔵 | CRUD |

---

## Cart & wishlist — `cart`

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/cart` | 🟢 | items + computed bill (subtotal, gst 18%, delivery, total) |
| POST | `/cart/items` | 🟢 | `{product_id, variant_id?, quantity}` (upsert) |
| PATCH | `/cart/items/{id}` | 🟢 | `{quantity}` (0 ⇒ remove) |
| DELETE | `/cart/items/{id}` | 🟢 | |
| GET | `/wishlist` | 🟢 | |
| POST | `/wishlist/{productId}` | 🟢 | toggle on |
| DELETE | `/wishlist/{productId}` | 🟢 | toggle off |

> Server is the source of truth for the bill (don't trust client totals): subtotal from
> live prices, **GST 18%**, delivery fee rule, coupon discount.

---

## Addresses — `addresses`

| GET `/addresses` · POST `/addresses` · GET/PATCH/DELETE `/addresses/{id}` · POST `/addresses/{id}/default` | 🟢 |

---

## Checkout & orders — `orders`

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/checkout` | 🟢 | `{address_id, payment_method, delivery_slot?, coupon_code?}` + Idempotency-Key. Validates stock/credit, places order **atomically**, debits ledger if `credit`, returns `{order, payment?}` |
| GET | `/orders` | 🟢 | `?status=` |
| GET | `/orders/{id}` | 🟢 | detail + items + timeline |
| GET | `/orders/{id}/tracking` | 🟢 | live status + agent + eta |
| POST | `/orders/{id}/cancel` | 🟢 | if cancellable; reverses ledger via `adjustment` |
| POST | `/orders/{id}/reorder` | 🟢 | repopulates cart |
| **Agent** | | | |
| GET | `/agent/deliveries` | 🟡 | assigned orders |
| POST | `/agent/deliveries/{order_id}/status` | 🟡 | `{status, note?}` (picked/delivered/failed) |
| **Admin** | | | |
| GET/PATCH | `/admin/orders` `…/{id}` | 🔵 | list, update status, assign agent, refund |

---

## Credit — `credit`  (the core)

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/credit/dashboard` | 🟢 | account: limit, available, outstanding, vs_score, next due |
| GET | `/credit/score` | 🟢 | score + factors |
| GET | `/credit/ledger` | 🟢 | paginated ledger entries |
| GET | `/credit/statements` | 🟢 | list (weekly/monthly) |
| GET | `/credit/statements/{id}` | 🟢 | statement + lines |
| GET | `/credit/bills/weekly` · `/credit/bills/monthly` | 🟢 | current cycle bill |
| GET | `/credit/outstanding` | 🟢 | total due + breakdown |
| POST | `/credit/repay` | 🟢 | `{amount, statement_id?, method}` + Idempotency-Key → creates payment |
| **Family / shared limit** | | | |
| GET | `/credit/family` | 🟢 | group + members + shared usage |
| POST | `/credit/family/members` | 🟢(primary) | invite `{phone, relationship}` |
| DELETE | `/credit/family/members/{id}` | 🟢(primary) | |
| **Admin** | | | |
| PATCH | `/admin/credit/{user_id}` | 🔵 | adjust limit/status (writes `adjustment` ledger + audit) |
| POST | `/admin/credit/{user_id}/freeze` | 🔵 | freeze/unfreeze |

---

## Payments — `payments`

| Method | Path | Role | Notes |
|---|---|---|---|
| POST | `/payments` | 🟢 | `{purpose, order_id?\|statement_id?, amount, method}` → `{gateway_order_id, ...}` to open gateway sheet |
| GET | `/payments/history` | 🟢 | |
| GET | `/payments/{id}` | 🟢 | status |
| POST | `/webhooks/razorpay` | gateway | **signature-verified**, idempotent; finalizes payment + posts repayment ledger entry |
| **Cash collection (agent)** | | | |
| POST | `/credit/cash-collection` | 🟢 | request collection `{amount, statement_id?}` |
| GET | `/agent/collections` | 🟡 | assigned requests |
| POST | `/agent/collections/{id}/collect` | 🟡 | marks collected → creates `cash` payment → ledger repayment |

---

## Offers — `offers`

| GET `/offers` (public) · GET `/coupons/wallet` 🟢 · POST `/coupons/validate` 🟢 `{code, cart_total}` |
| Admin: CRUD `/admin/offers`, `/admin/coupons` 🔵 |

---

## Notifications — `notifications`

| GET `/notifications` 🟢 · POST `/notifications/{id}/read` 🟢 · POST `/notifications/read-all` 🟢 · GET/PATCH `/notifications/preferences` 🟢 |
| Admin: POST `/admin/notifications/broadcast` 🔵 (segment + message) |

---

## Support — `support`

| GET/POST `/support/tickets` 🟢 · GET `/support/tickets/{id}` 🟢 · POST `/support/tickets/{id}/messages` 🟢🟡🔵 · GET `/support/faqs` (public) |
| Agent/Admin: GET `/admin/support/tickets` (queue), PATCH status/assignee |

---

## Referrals — `referrals`

| GET `/referrals` 🟢 (my code + status) · POST `/referrals/apply` 🟢 `{code}` |

---

## Admin / Ops — `ops`  (🔵🟣, mostly via Django admin + a few JSON endpoints)

| GET | `/admin/dashboard` | 🔵 | KPIs: GMV, active credit, overdue, orders today |
| GET/POST/PATCH | `/admin/staff` | 🟣 | manage admins & agents (create, assign role, deactivate) — **superadmin only** |
| GET | `/admin/customers` `…/{id}` | 🔵 | customer 360 (orders, credit, kyc) |
| GET | `/admin/reports/*` | 🔵 | exports |

> The Django admin site (`/admin/`) covers most CRUD for superadmin/admin for free;
> the JSON `/admin/*` endpoints exist where the agent app or a custom dashboard needs them.

---

## Notes for implementation

- Serializers for the **customer** endpoints must match the app's model JSON
  (field names like `imageUrl`, `mrp`, `creditPrice`, `inStock`, `kycStatus`) — see
  `apps/user_app/lib/.../data/models/*.dart`. Either match camelCase or add a
  rename layer; decide once (recommend a DRF camelCase renderer/parser).
- Every `POST` that moves money returns the resulting ledger/payment state so the app
  can update optimistically without a second round-trip.
- All staff `/admin/*` and `/agent/*` writes emit `audit_log` rows.
