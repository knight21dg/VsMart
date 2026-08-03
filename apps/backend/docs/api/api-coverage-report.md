# API Coverage Report

Generated from the live URL resolver + DRF permission classes (the source of truth).

- **Total operations:** 222  (path × method)
- **Public (no auth):** 16
- **Authenticated:** 206

## By access tier
| Access tier | Count |
|---|---|
| authenticated | 100 |
| admin | 66 |
| agent | 29 |
| public | 16 |
| admin (dynamic) | 8 |
| superadmin | 3 |

> `admin (dynamic)` = views that branch permissions per-method via `get_permissions`
> (read = admin, write = superadmin), e.g. platform config and zones.

## By module
| Module | Count |
|---|---|
| inventory | 50 |
| admin | 23 |
| pos | 21 |
| credit | 15 |
| deliveries | 9 |
| geography | 8 |
| addresses | 7 |
| agent | 6 |
| collections | 6 |
| notifications | 6 |
| verification | 6 |
| agents | 5 |
| auth | 5 |
| orders | 5 |
| support | 5 |
| billing | 4 |
| cart | 4 |
| kyc | 3 |
| payments | 3 |
| products | 3 |
| wishlist | 3 |
| audit | 2 |
| categories | 2 |
| coupons | 2 |
| health | 2 |
| referrals | 2 |
| reports | 2 |
| users | 2 |
| app-config | 1 |
| checkout | 1 |
| feature-flags | 1 |
| feedback | 1 |
| maintenance-status | 1 |
| offers | 1 |
| search | 1 |
| uploads | 1 |
| version | 1 |
| webhooks | 1 |
| zones | 1 |


## Artifacts
- `docs/api/openapi.yaml` — OpenAPI 3.0 spec (all operations, envelope-wrapped).
- `docs/api/swagger.json` — same, JSON.
- `docs/api/postman_collection.json` — this run.
- Live docs: `/api/docs/` (Swagger UI), `/api/redoc/` (ReDoc), `/api/schema/` (raw).
