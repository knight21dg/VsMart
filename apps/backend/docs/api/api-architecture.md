# VS Mart — API Architecture & Contract

The frozen, code-derived contract for the VS Mart backend. Generated from the live
DRF views/serializers and URL resolver — **the spec follows the code, not the other way
around**, so it stays accurate as POS/Inventory land (just re-run the generators).

## Artifacts (in this folder)
| File | What |
|---|---|
| `openapi.yaml` | OpenAPI 3.0 spec — every operation, envelope-wrapped, grouped by module tag |
| `swagger.json` | Same spec as JSON |
| `postman_collection.json` | All endpoints grouped by module, Bearer auth pre-wired |
| `api-coverage-report.md` | Endpoint counts by access tier + module |
| `api-architecture.md` | This document |

**Live docs** (when the server runs): `/api/docs/` (Swagger UI) · `/api/redoc/` (ReDoc)
· `/api/schema/` (raw OpenAPI).

## Conventions

- **Base URL:** `/api/v1`. Breaking changes → `/api/v2`.
- **Auth:** JWT. `Authorization: Bearer <access_token>`. Obtain via `POST /auth/otp/send`
  → `POST /auth/otp/verify`. Refresh via `POST /auth/refresh`.
- **Response envelope** (every endpoint):
  ```json
  { "success": true, "message": "", "data": { }, "meta": { } }
  ```
  Lists carry `meta` (`page`, `pageSize`, `total`, `totalPages`). Errors:
  ```json
  { "success": false, "message": "…", "error": { "code": "…", "message": "…", "fields": {} } }
  ```
- **Casing (important):** the **auth/user** endpoints (`/auth/*`, `/users/me`) return
  **snake_case** keys (`access_token`, `refresh_token`, `kyc_status`, `credit_enabled`,
  and `id` as a **string**) to match the Flutter `AuthTokenModel`/`UserModel`.
  **Everything else is camelCase** (`imageUrl`, `creditPrice`, `inStock`, …).
- **Money:** rendered as JSON numbers (Decimals), 2 dp.
- **Pagination:** `?page=&page_size=` (default 20). Filters per endpoint (e.g. products:
  `category`, `brand`, `sort`, `q`).
- **Idempotency:** `Idempotency-Key` header on `POST /checkout`, `POST /payments`,
  `POST /credit/repay`.

## Auth & RBAC

Roles: **superadmin · admin · agent · customer** (single-tenant — no geographic admin
tiers). Permission classes (`core/permissions.py`): `IsCustomer`, `IsAgent`, `IsAdmin`
(admin+superadmin), `IsSuperAdmin`, `IsOwner`. Money/config levers (platform fees, zones,
config) are **superadmin-only**; operational endpoints are admin+superadmin. Agent
endpoints are scoped to assignment. See `api-coverage-report.md` for per-tier counts and
`docs/04-rbac.md` for the full matrix.

## Module map (tags)

`auth/users` · `geography` · `kyc`/`verification` · `credit` · `catalog`/`products` ·
`inventory` · `cart`/`wishlist` · `addresses` · `checkout`/`orders` · `payments` ·
`billing` · `collections` · `deliveries` · `agents` · `notifications` · `offers`/`coupons`
· `referrals` · `support` · `zones` · `admin` (analytics, staff, customer-360, inventory
adjust, credit controls) · `audit` · `reports` · `system` (version/app-config/maintenance/
feature-flags/uploads/search/feedback).

## Regenerating (after POS / Inventory)

```bash
python manage.py spectacular --file docs/api/openapi.yaml
python manage.py spectacular --format openapi-json --file docs/api/swagger.json
python scripts/gen_api_docs.py    # postman_collection.json + api-coverage-report.md
```

## Known limitations (v1 contract)
- Hand-rolled `APIView` endpoints (many admin/agent actions) document their **path,
  method, auth and envelope** precisely, but their request/response *bodies* are loosely
  typed (no serializer to introspect). Generic/ViewSet endpoints (catalog, addresses,
  zones, credit reads, etc.) have full body schemas. Tightening bodies = adding
  `@extend_schema(request=…, responses=…)` per view — a follow-up, not a blocker.
- Object-level scoping (owner/assigned-agent) is enforced in code, not expressed in OpenAPI.
