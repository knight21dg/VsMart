# 08 · Superadmin Control Plane (zones · fees · analytics · inventory)

The customer/agent/admin APIs exist. This adds the **control plane** — the knobs a
superadmin uses to run the business: money configuration, delivery zones, analytics,
and inventory. Admin gets read/operate; superadmin gets the money + config levers.

## What the superadmin needs

1. **Money configuration (runtime, not code):** GST %, delivery fee, free-delivery
   threshold, **platform fee** (commission), min order, default credit limit, late fee,
   currency, support contact.
2. **Delivery zones:** define serviceable areas by **center + radius (km)** and/or
   pincodes, with **per-zone fee overrides** (delivery fee, platform fee, min order,
   free-delivery threshold) and agent assignment.
3. **Platform fee selection:** percent-of-order or flat, with a cap — global default,
   overridable per zone.
4. **Analytics & sales:** GMV, revenue (platform fee + delivery), orders trend, AOV,
   top products/categories, zone-wise sales, new customers.
5. **Credit oversight:** outstanding, overdue, repayment rate; **set limits / freeze**.
6. **Inventory:** stock levels, low-stock alerts, **stock adjustments with audit**.
7. **Staff & roles** (already built in `ops`).

## Gap analysis (what's lacking today)

| Need | Today | Gap to close |
|---|---|---|
| Editable money settings | GST/delivery are **env constants** in `core/pricing.py` | DB-backed `PlatformConfig` editable by superadmin |
| Platform fee | none | new fee field + applied in bill + shown as a line |
| Delivery zones / radius | none | `Zone` model + serviceability + per-zone overrides |
| Serviceability check | none | `/zones/check` by lat/lng or pincode |
| Analytics | basic counts in `/admin/dashboard` | real sales/revenue/top-products/zone endpoints |
| Inventory ops | product CRUD only | stock list, low-stock, **adjust with history** |
| Admin credit controls | spec'd, not built | set limit / freeze (+ ledger adjustment + audit) |

## Design

### New app: `siteconfig`
`PlatformConfig` — **singleton** (pk=1, `PlatformConfig.load()`):
`gst_rate, delivery_fee, free_delivery_threshold, min_order, platform_fee_type
(percent|flat), platform_fee_value, platform_fee_cap, credit_default_limit,
late_fee_flat, late_fee_percent, currency, support_phone, support_email`.
- `GET /admin/config` (admin) · `PATCH /admin/config` (**superadmin**, audited).
- Editable in Django admin. Seeded with defaults from env on first load.

### New app: `zones`
`Zone` — `name, center_lat, center_lng, radius_km, pincodes[], is_active` + nullable
overrides `delivery_fee, free_delivery_threshold, min_order, platform_fee_value`.
`ZoneAgent` — agent ↔ zone.
- `GET /zones/check?lat=&lng=` or `?pincode=` (customer) → `{serviceable, zone, fees}`.
- `GET/POST/PATCH/DELETE /admin/zones` (admin list/superadmin write).
- Serviceability = haversine(point, center) ≤ radius_km, or pincode in list.

### Pricing rework — `core/pricing.py`
`compute_bill(subtotal, …, zone=None)` now:
- reads `PlatformConfig.load()` (falls back to env defaults),
- applies **platform fee** (percent of subtotal or flat, capped),
- lets a **zone** override delivery fee / free threshold / min order / platform fee,
- returns `platform_fee` in the breakdown.
`Order` gains a `platform_fee` column; `total = subtotal + delivery + gst +
platform_fee − discount`. Credit debit uses the new total.

### `ops` additions
- **Analytics:** `/admin/analytics/overview`, `/sales?period=`, `/top-products`,
  `/zones` (admin).
- **Inventory:** `/admin/inventory` (+ `?low_stock=1`), `POST /admin/inventory/{id}/adjust`
  → `StockAdjustment` row + updates product. (admin)
- **Credit:** `PATCH /admin/credit/{user_id}` (limit/status), `POST …/freeze`
  (admin; writes ledger adjustment + audit).

## RBAC split (superadmin vs admin)

| Capability | admin | superadmin |
|---|:--:|:--:|
| View analytics / sales / inventory | ✅ | ✅ |
| Adjust stock | ✅ | ✅ |
| Set credit limit / freeze | ✅ | ✅ |
| View platform config & zones | ✅ | ✅ |
| **Edit platform fees / GST / config** | — | ✅ |
| **Create / edit / delete zones** | — | ✅ |

Money levers (fees, config, zones) are **superadmin-only**; everything operational is shared.
