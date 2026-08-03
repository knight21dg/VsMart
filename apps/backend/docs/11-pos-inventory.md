# 11 · Phase 5 — Inventory ERP + POS

> **STATUS: ✅ BUILT & VERIFIED (2026-06-20).** This document is the design; the build
> matches it. See `docs/HANDOFF.md` → "Phase 5" for what shipped, the app/service/endpoint
> map, and `scripts/smoke_pos.py` + `inventory/tests.py` for the verification. The sections
> below are the original design spec, kept for reference.

The business backbone: a **ledger-based inventory system of record** plus an in-store
**POS billing** system, with a **stock-sync engine** so online orders, POS sales,
returns, transfers, damage and expiry all move the same stock truthfully.

## The one rule

> **Never update stock directly.** Every movement creates an **InventoryLedger**
> transaction; *available stock is a calculated value*, never a stored mutable number.

```
movement (PO/GRN/Sale/Order/Return/Refund/Transfer/Adjust/Damage/Expiry)
        │
        ▼  InventoryService.post_movement(...)   ← the ONLY writer
   InventoryLedger row  (append-only, signed qty, per product×warehouse)
        │
        ▼  StockCalculationService.available(product, warehouse)
   = Σ ledger.qty − reserved        ← derived, cached
        │
        ▼  StockSyncService.broadcast(...)   → recompute Product.in_stock, low-stock alerts,
                                                notify Customer app / Admin / POS / Agent app
```

This mirrors the **credit ledger** already in production (`credit/services.py`) — same
append-only + reconcile pattern, applied to stock.

## Relationship to what's built

The current `inventory` app has `Warehouse / StockItem / StockTransfer / PurchaseOrder`.
Phase 5A **promotes** it: keep those tables, but `StockItem.quantity` becomes a **cache**
rebuilt from the new `InventoryLedger` (like `CreditAccount.outstanding`). The existing
`ops` stock-adjust endpoint will route through `InventoryService` instead of writing
`stock_count` directly. No endpoint removed.

## 5A — Inventory ERP

**New / extended models**

| Model | Notes |
|---|---|
| `Brand`, `Unit` | masters (name, code) |
| `Supplier` | name, gstin, phone, address, is_active |
| `Barcode` | product/variant ↔ barcode (unique), symbology |
| `Sku` | per variant; on `ProductVariant` (add sku, mrp, cost) |
| `PurchaseOrder` (extend) | supplier, status, expected_at, totals |
| `GRN` + `GRNItem` | goods receipt against a PO → posts `purchase` ledger rows |
| `InventoryLedger` | **append-only**: product, variant?, warehouse, type, qty(signed), balance_after, ref_type/ref_id, batch?, expiry?, created_by |
| `StockBatch` | batch_no, expiry_date, qty (for FEFO + expiry mgmt) |
| `StockAdjustment` (route via ledger) | reason, delta |
| `StockTransfer` (post 2 ledger rows) | out of source, into dest |
| `DamageRecord`, `ExpiryRecord` | reason → negative ledger rows |
| `LowStockAlert` | product, warehouse, threshold, raised_at |

**Ledger movement types:** `purchase, grn, sale, order, order_cancel, return, refund,
transfer_in, transfer_out, adjustment, damage, expiry, opening`.

**Services:** `InventoryService` (post_movement — the sole writer, atomic),
`InventoryLedgerService` (query/reconcile), `StockCalculationService` (available, on-hand,
reserved, FEFO batch pick), `StockSyncService` (recompute caches + alerts + broadcast).

**APIs (admin):** product master CRUD, brands, units, suppliers, barcodes, SKUs,
`/inventory/purchase-orders`, `/inventory/grn`, `/inventory/ledger` (audit view),
`/inventory/adjustments`, `/inventory/transfers`, `/inventory/damage`, `/inventory/expiry`,
`/inventory/low-stock`, `/inventory/valuation`.

## 5B — POS Billing

**Models:** `POSSession` (cashier, store, opened/closed, opening_cash),
`POSTransaction` (session, type sale/return, customer?, totals, payment_status),
`POSTransactionItem` (product/variant, qty, price, tax), `POSPayment` (method
cash/upi/card/credit/split, amount, ref), `POSRefund`, `CashDrawer` (session, movements),
`DayClosing` (session, expected vs counted, variance).

**Flows:** barcode-scan / product-search billing → cart → split payment (cash/UPI/card/
**credit** — debits the credit ledger for approved customers) → invoice (thermal-printer
friendly payload) → **every sale posts a `sale` InventoryLedger row** via
`StockSyncService`. Hold/resume cart (server-held). Returns/refunds post `return`/`refund`
ledger rows (stock back in). **Day closing** reconciles the cash drawer.

**APIs (cashier = staff role):** `/pos/session/open|close`, `/pos/scan`, `/pos/search`,
`/pos/customer-lookup`, `/pos/cart` (hold/resume), `/pos/checkout`, `/pos/transactions`,
`/pos/return`, `/pos/refund`, `/pos/day-closing`, `/pos/cash-drawer`.

## 5C — Stock Sync Engine

`StockSyncService` is called by **every** stock source (POS sale, online order placement,
order cancel, return, refund, purchase/GRN, transfer, damage, expiry, adjustment). It:
1. ensures the movement went through `InventoryService.post_movement` (ledger row),
2. recomputes `available` (Σledger − reserved) + updates `Product.in_stock`/`StockItem`,
3. raises/clears `LowStockAlert`,
4. emits an analytics event + (later) pushes a realtime update to apps/POS.

**Online order integration:** `orders.services.place_order` will *reserve* stock
(reservation ledger/`reserved` bump) at checkout and post a `sale` movement on delivery;
cancellation reverses it — replacing today's direct `stock_count` decrement.

## Deliverables (per phase)
1. **DB architecture** (this doc) · 2. Django apps (`inventory` extended + new `pos`)
· 3. Services (4 above) · 4. APIs · 5. Permissions (staff/cashier + admin) · 6. Analytics
events (stock_moved, sale_completed, low_stock, day_closed) · 7. Reports (stock valuation,
sales by cashier, day-closing, fast/slow movers, expiry) · 8. Dashboard metrics (on-hand
value, today's POS sales, low-stock count, variance).

## Invariants & tests (money/stock — tests first)
- `Σ InventoryLedger.qty (product, warehouse) == StockCalculationService.on_hand` (reconcile).
- POS credit sale debits the credit ledger by the same amount it bills.
- No negative available without an explicit oversell flag.
- Day-closing variance = counted − (opening + cash sales − refunds).

## Build order
5A masters + **InventoryLedger + InventoryService + reconcile (tests first)** → GRN/PO →
adjust/transfer/damage/expiry → low-stock/valuation → 5B POS session/billing/payments →
returns/refunds/day-closing → 5C wire StockSyncService into orders + POS. Then regenerate
OpenAPI once and freeze.
