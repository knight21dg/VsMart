"""Shared filter + attribution helpers for the executive reports.

All reports derive from source-of-truth modules; these helpers keep the
aggregation DB-side (grouped annotations) and provide the customer→store/zone
attribution used by store/zone breakdowns without N+1 lookups.
"""
from datetime import datetime, timedelta

from django.utils import timezone


def _parse_date(s):
    if not s:
        return None
    try:
        return datetime.strptime(str(s), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return None


def date_range(params, default_days=30):
    """(start, end) inclusive dates from ?date_from / ?date_to (defaults to the
    trailing `default_days`)."""
    params = params or {}
    end = _parse_date(params.get("date_to")) or timezone.now().date()
    start = _parse_date(params.get("date_from")) or (end - timedelta(days=default_days - 1))
    return start, end


def store_id(params):
    return (params or {}).get("store") or None


def zone_id(params):
    return (params or {}).get("zone") or None


def scope_orders(qs, params):
    """Apply store/zone scoping to an Order queryset."""
    sid, zid = store_id(params), zone_id(params)
    if sid:
        qs = qs.filter(store_id=sid)
    if zid:
        qs = qs.filter(zone_id=zid)
    return qs


def user_store_zone_map():
    """{user_id: {store_id, store_name, zone_id, zone_name}} from each customer's
    most recent routed order — one query, used to attribute credit/collection
    figures (which have no store/zone of their own) to a store and zone."""
    from orders.models import Order

    out = {}
    rows = (
        Order.objects.exclude(zone__isnull=True)
        .order_by("user_id", "-placed_at")
        .values("user_id", "store_id", "store__name", "zone_id", "zone__name")
    )
    for r in rows:
        out.setdefault(r["user_id"], r)
    return out


def paginate_sort(report, params):
    """Generic sort + pagination over a {columns, rows} report (applied after the
    builder so every tabular report supports ?sort=<col>&dir=&page=&page_size=)."""
    params = params or {}
    rows = report.get("rows")
    if not isinstance(rows, list):
        return report
    cols = report.get("columns", [])
    sort = params.get("sort")
    if sort and sort in cols:
        idx = cols.index(sort)
        reverse = params.get("dir", "asc") == "desc"
        rows = sorted(
            rows,
            key=lambda r: (r[idx] is None, r[idx] if not isinstance(r[idx], str) else r[idx].lower()),
            reverse=reverse,
        )
    total = len(rows)
    try:
        page = max(1, int(params.get("page", 1)))
        page_size = int(params.get("page_size", 0) or 0)
    except (TypeError, ValueError):
        page, page_size = 1, 0
    if page_size > 0:
        rows = rows[(page - 1) * page_size: page * page_size]
    report = {**report, "rows": rows, "meta": {"total": total, "page": page, "pageSize": page_size}}
    return report
