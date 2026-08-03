# Zone enforcement — secure, zone-scoped operations

The platform can run in two modes, controlled by two `FeatureFlag`s:

| Flag | Off (default) | On |
|------|---------------|----|
| `zone_store_visibility` | Global catalog — every customer sees every product. | A customer sees **only** the catalog of the store that serves their zone. |
| `zone_enforcement` | Orders can be placed anywhere; stock draws from the default warehouse. | Checkout is **rejected** outside every serviceable zone; each order is bound to its zone's store and reserves/fulfils that store's warehouse only. |

Both default **off** so nothing changes until you deliberately switch zones on.

## The model (single source of truth)

```
Customer address ──▶ Zone (polygon)  ──▶ Store ──▶ Warehouse (stock) ──▶ Order
                     resolve_serviceable_zone()      order.store / fulfil_warehouse
```

* `zones/serviceability.py` resolves a point to its highest-priority active polygon zone.
* `Zone.store` is the routing target; `Store.warehouse` holds that store's stock.
* `orders/services.place_order` stamps `order.store` and **reserves the serving store's
  warehouse** — never the global default — so an order can only ever draw down the stock
  of the store that serves the customer. `fulfil_order`/`cancel_order` use the same
  warehouse via `order_warehouse(order)`.

## No-loophole gates (all enforced server-side at checkout)

1. **Out of area** → `422 OUTSIDE_SERVICE_AREA` when no zone (or no active store) serves
   the address. No order row is created.
2. **Cross-store item** → `409 PRODUCT_UNAVAILABLE` when a cart item isn't carried by the
   serving store (closes the deep-link / spoofed `?store=` / stale-cart hole).
3. **Out of store stock** → `409 OUT_OF_STOCK` / `INSUFFICIENT_QUANTITY` checked against the
   serving store's warehouse (a product in stock elsewhere can't be ordered here).
4. **Credit gate** → `CREDIT_DISABLED` when the zone has `credit_enabled = False`.

## Catalog is resolved server-side (never "send all, filter on the client")

When `zone_store_visibility` is on, the catalog endpoints (`/products`, `/products/search`,
`/products/<id>`) resolve the serving store **on the backend**, in priority order:

1. `lat` / `lng` / `pincode` query params — the device's current/selected delivery location;
2. the authenticated customer's saved (default/selected) address;
3. *(transitional)* a `store` id param, accepted only as a real active store — a single-store
   scope, never the union — so older app builds keep working until they send location.

The backend then returns **only that store's products**. Key properties:

* **No global leak** — when scoping is on and no serviceable store resolves (out of area, or no
  location/address yet), the catalog is **empty**, never the full cross-store list. Omitting the
  store can't widen what a client sees.
* **Client can't choose the store** — a spoofed `?store=` is ignored whenever a location/address
  resolves; the store is the server's decision.
* **Cross-store products are hidden** — a deep link to a product the serving store doesn't carry
  returns `404`, so the app never reveals another store's products.

The Flutter app sends the customer's `lat`/`lng`/`pincode` (from the selected delivery address)
on every catalog call; the store id is sent only as a transitional fallback. Order placement
re-resolves the store from the delivery address, so the param can never route an order to the
wrong store.

## Operational gates (real grocery edge cases)

All enforced server-side in `orders.services.place_order`, no-ops until configured:

| Situation | Gate | Code |
|-----------|------|------|
| Address moved into another store's zone | Store-A cart can't become a Store-B order; the cart is cleared server-side | `STORE_CHANGED` (action `refresh_cart`) |
| Item delisted since it was added | Per-item check against the store catalog | `PRODUCT_UNAVAILABLE` |
| Stock ran out mid-checkout | Atomic `select_for_update` reserve on the store warehouse | `INSUFFICIENT_QUANTITY` / `OUT_OF_STOCK` |
| Store outside business hours / paused | `Store.is_open_now()` (`opens_at`/`closes_at`/`accepting_orders`) | `STORE_CLOSED` |
| Store hit its daily order cap | `Store.capacity_reached()` (`daily_order_capacity`) | `DELIVERY_CAPACITY_REACHED` |
| Zone disabled | Serviceability only resolves `is_active` zones → empty catalog | `OUTSIDE_SERVICE_AREA` |

Store hours/capacity are editable by the store admin (`PATCH /store/settings`) and the
super-admin (store create/edit). The serviceability response exposes `store_open`,
`opens_at`, `closes_at`, `accepting_orders`, `capacity_reached` so the app keeps the
catalog visible but disables checkout with the reason (`ServiceabilityResult.canCheckout`
/ `blockedReason`).

**Single stock source:** a store's POS till and its online orders both post to the SAME
`InventoryLedger`/`StockItem` (the store's warehouse) — a POS sale of −2 and an online
order of −3 hit one number. No separate POS/online inventory tables.

**Immutable order snapshot:** each order captures `store_name`, `store_address`,
`zone_name` (header) and per-line `name`/`price`/`mrp`/`gst_rate`, so invoice history is
reproducible even if the store/zone/product changes or is deleted later.

**Per-store pricing:** price comes from `StoreProduct.selling_price` (via `store_price()`),
not the product master, when `store_pricing` is on.

**Hide-from-sale:** `StoreProduct.is_available=False` hides a product from the online
catalog and blocks online checkout while its inventory stays intact (POS still sells from
stock) — inventory ≠ catalog visibility.

## Onboarding a store admin (Super-Admin)

`POST /api/v1/admin/stores/<id>/admin` (superadmin only) creates an **email + password**
login bound to a `manager` `StoreStaff` membership for that store. The admin signs into the
Store-Admin panel (`/auth/login`) and sees **only** that store's data — the membership is the
sole scope, so they can never reach another store. Also available in the Admin Console:
**Stores → (row) → Admin**.

* `GET  /api/v1/admin/stores/<id>/admin` — list the store's admins.
* `POST /api/v1/admin/stores/<id>/admin/reset-password` — reset an admin's password.

## Turning it on safely

A serviceable zone whose store carries no products would show an empty storefront — a
defect. So enabling runs a pre-flight check and **refuses** unless every active zone routes
to an active store with a non-empty catalog.

```bash
# 1. Map each store's catalog (StoreProduct rows) so visibility has something to show.
python manage.py map_store_catalog --store STORE-BLR-01 --all

# 2. Enable both flags (pre-flight will list any empty/missing-store zones and refuse).
python manage.py zone_mode --on        # add --force to override the warnings
python manage.py zone_mode --status
python manage.py zone_mode --off        # back to global catalog
```

Flags can also be toggled per-environment from the Django admin (`/admin/system/featureflag/`).

## Verification

`scripts/smoke_zone_e2e.py` builds two stores + zones + a store admin, flips both flags on
(restoring prior state afterwards), and asserts the full contract: catalog isolation, order
routing, per-store inventory draw-down, cross-store rejection, out-of-area rejection, and
store-admin order scoping (29 assertions).

```bash
.venv/Scripts/python.exe scripts/smoke_zone_e2e.py
```
