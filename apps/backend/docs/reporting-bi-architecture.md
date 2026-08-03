# VS Mart — Reporting & BI Architecture

Backend-only analytics layer. **No reporting tables, no duplicate storage** — every
figure is derived live from the source-of-truth modules (orders, credit, payments/
collections, inventory, accounts, delivery, verification, zones, returns).

## Components

| File | Role |
|------|------|
| `reports/builders.py` | Registry (`BUILDERS`) + the original 6 builders (sales, orders, credit, collections, inventory, agents). |
| `reports/executive.py` | The 6 executive reports + the dashboard (`EXECUTIVE_BUILDERS`, merged into `BUILDERS`). |
| `reports/filters.py` | Date-range / store / zone parsing, the customer→store/zone attribution map, and generic sort + pagination. |
| `reports/views.py` | `ReportView` (JSON), `DashboardView` (KPIs), `ReportExportView` (CSV/Excel/PDF). |

## Builder contract
A builder is `fn(params: dict) -> dict` returning some of:
- `title` — display name.
- `columns` + `rows` — tabular data (drives CSV/Excel/PDF export + sort/pagination).
- `summary` — headline KPI dict.
- `charts` — chart-ready series (trends, heatmaps, distributions).
- `widgets` — dashboard-only KPI map.

`params` carries `date_from`, `date_to`, `store`, `zone`, `sort`, `dir`, `page`,
`page_size`. Sort + pagination are applied generically by `filters.paginate_sort`
*after* the builder, so every tabular report gets them for free.

## Reports

| Name | Output |
|------|--------|
| `recovery_performance` | summary (outstanding/collected/overdue/recovery-rate/efficiency/avg-time) + agent ranking rows + recovery-trend chart. |
| `store_performance` | per-store revenue/orders/customers/credit/inventory-value/returns/delivery-success + derived rev-per-order / rev-per-customer; ranked by revenue. |
| `zone_performance` | per-zone revenue/orders/customers/outstanding/collections + collection-efficiency; heatmap-ready series. |
| `customer_cohorts` | registration-month cohorts with 30/60/90-day retention, repeat %, credit adoption %. |
| `credit_utilization` | portfolio totals + utilization bands (0-25…100+) + risk bands (low…critical). |
| `collection_efficiency` | assigned/completed/failed + success rate + avg recovery time + agent & zone rankings. |
| `dashboard` | 14 executive KPI widgets (revenue/orders/collections today+MTD, outstanding, utilization, active/new customers, pending deliveries/verifications, inventory value, low-stock count). |

## Endpoints (all `IsAdmin`)
- `GET /api/v1/reports/dashboard` → KPI widgets.
- `GET /api/v1/reports/<name>?date_from&date_to&store&zone&sort&dir&page&page_size` → JSON report.
- `GET /api/v1/reports/export?type=<name>&fmt=csv|excel|pdf` → file download (CSV native, Excel via openpyxl, PDF via reportlab).

## Performance & scale
- **DB-side aggregation** — grouped `.values(...).annotate(Sum/Count/Avg)` and conditional
  aggregation (`Count(filter=Q(...))`); no per-row queries in the hot path.
- **Cross-module attribution without N+1** — collections/outstanding have no store/zone
  of their own, so a single `user_store_zone_map()` query maps each customer to their
  most recent routed order's store+zone; reports bucket in memory against that map.
- **Bounded scans** — average-time computations sample (`[:2000]`); risk-band scans over
  credit accounts are list-materialised (portfolios are far smaller than the order table).
- Designed for the 100k-customer / 1M-order / 100-store / 1000-zone targets; the only
  builders that materialise per-row are the legacy tabular ones (already `[:200]/[:500]`
  capped). Aggregate reports return one row per store/zone/cohort/band.

## Tests
`reports/tests.py` — 12 tests: each builder's aggregation correctness against a fixture
(revenue, inventory value, utilization %, collection success, cohort size) + the
endpoints (dashboard, pagination meta, CSV export, 404, admin-only).
