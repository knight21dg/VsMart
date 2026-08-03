"""Customer 360 — an enterprise CRM aggregation layer over the source-of-truth
modules (accounts, credit, orders, payments/collections, kyc, verification,
support, returns, referrals, zones, stores). Nothing is stored here except admin
notes; every figure is read live. Output is organised into the 15 CRM sections.
"""
from collections import Counter
from datetime import timedelta
from decimal import Decimal

from django.db.models import Avg, Count, Max, Min, Q, Sum
from django.utils import timezone

ZERO = Decimal("0.00")


def _f(v):
    return float(v or 0)


def _pct(part, whole):
    return round(_f(part) / _f(whole) * 100, 1) if whole else 0.0


def vs_id(user):
    return f"VS-CUST-{user.id:08d}"


def zone_resident_customer_ids(*, store_id=None, zone_id=None) -> set:
    """Customer ids whose address falls in a store's zone(s) (or one zone) — so a
    store sees the RESIDENTS of its area, not only people who've already ordered.

    Matches on the same signals the serviceability engine uses: the zone polygon
    (point-in-polygon over the customer's address coords) and the legacy pincode
    list. `store_id` → all that store's active zones; `zone_id` → just that zone."""
    from addresses.models import Address
    from zones.models import Zone
    from zones.serviceability import point_in_polygon

    zones = Zone.objects.filter(is_active=True)
    if zone_id:
        zones = zones.filter(pk=zone_id)
    elif store_id:
        zones = zones.filter(store_id=store_id)
    else:
        return set()
    zones = list(zones)
    if not zones:
        return set()

    polygons = [z.polygon_geojson for z in zones if z.polygon_geojson]
    pincodes = {
        str(p).strip() for z in zones for p in (z.pincodes or []) if str(p).strip()
    }

    ids = set()
    if pincodes:
        ids.update(
            Address.objects.filter(pincode__in=pincodes)
            .values_list("user_id", flat=True)
        )
    if polygons:
        # Test only THIS store's zone polygons (not every zone), over addresses that
        # actually carry coordinates. The customer base at this stage is small, so a
        # Python pass is fine; PostGIS can replace it when the addresses table grows.
        coords = (
            Address.objects.exclude(latitude__isnull=True)
            .exclude(longitude__isnull=True)
            .values("user_id", "latitude", "longitude")
        )
        for a in coords:
            lat, lng = float(a["latitude"]), float(a["longitude"])
            if any(point_in_polygon(lng, lat, g) for g in polygons):
                ids.add(a["user_id"])
    return ids


# ── Search (filters + sort) ──────────────────────────────
CUSTOMER_SORTS = {
    "newest": ["-created_at"],
    "oldest": ["created_at"],
    "highest_outstanding": ["-_outstanding"],
    "highest_vs_score": ["-_vs_score"],
    "lowest_vs_score": ["_vs_score"],
    "most_orders": ["-_orders"],
    "highest_revenue": ["-_revenue"],
    "recently_active": ["-_last_active"],
    "inactive": ["_last_active"],
}

# Risk is scored in Python (not SQL), so filtering/sorting by it has to walk the
# candidate set. This caps that walk; risk-filtered pages therefore page through
# at most this many candidates, unlike the DB-sorted path which is unbounded.
RISK_SCAN_CAP = 1000


def _cust_row(u, risk_level=None):
    return {
        "id": str(u.id), "vsId": vs_id(u), "name": u.name, "phone": u.phone,
        "kycStatus": u.kyc_status,
        "vsScore": getattr(u, "_vs_score", None),
        "outstanding": _f(getattr(u, "_outstanding", 0)),
        "orders": getattr(u, "_orders", 0) or 0,
        "revenue": _f(getattr(u, "_revenue", 0)),
        "lastActiveAt": getattr(u, "_last_active", None),
        "active": u.is_active,
        # Credit account state (active / frozen / closed), or None when the
        # customer has no credit account. Annotated by search_customers so this
        # costs no extra query per row.
        "creditStatus": getattr(u, "_credit_status", None),
        "risk": risk_level or compute_risk(u)["level"],
    }


def customer_directory_source(query="", *, zone=None, store=None, kyc=None,
                              credit=None, status=None, risk=None,
                              credit_status=None, sort="newest"):
    """Build the filtered/sorted customer directory as an UNBOUNDED, sliceable
    source, so the caller decides how much of it to materialise.

    Returns one of two things, both of which support ``len()`` and slicing — all a
    paginator needs:

    * the annotated ``User`` queryset (the common path). It is lazy, so a paginator
      turns it into a single ``COUNT`` plus a one-page ``LIMIT/OFFSET`` query
      instead of dragging the whole directory into memory.
    * a pre-scored ``[(user, risk_level), ...]`` list, when the caller filters or
      sorts by risk. Risk is computed in Python, so it cannot be pushed into SQL;
      that path stays bounded by ``RISK_SCAN_CAP``.

    Pair with :func:`customer_rows` to turn a slice into API rows.
    """
    from django.db.models import Count, Exists, Max, OuterRef, Sum

    from accounts.models import User

    qs = User.objects.filter(role="customer")
    q = (query or "").strip()
    if q:
        cond = Q(name__icontains=q) | Q(phone__icontains=q)
        if q.isdigit():
            cond |= Q(id=int(q))
        cond |= Q(addresses__village__icontains=q) | Q(addresses__area__icontains=q)
        qs = qs.filter(cond)
    if kyc:
        qs = qs.filter(kyc_status=kyc)
    if status == "active":
        qs = qs.filter(is_active=True)
    elif status in ("suspended", "inactive"):
        qs = qs.filter(is_active=False)
    if credit in ("yes", "enabled", "true"):
        qs = qs.filter(credit_account__isnull=False)
    elif credit in ("no", "off", "false"):
        qs = qs.filter(credit_account__isnull=True)
    # Credit *account* state (active / frozen / closed) — distinct from `status`,
    # which is the user account's active/suspended flag. Filtering on this is how
    # staff find everyone whose credit is currently frozen.
    if credit_status in ("active", "frozen", "closed"):
        qs = qs.filter(credit_account__status=credit_status)
    if zone or store:
        from orders.models import Order

        sub = Order.objects.filter(user=OuterRef("pk"))
        if zone:
            sub = sub.filter(zone_id=zone)
        if store:
            sub = sub.filter(store_id=store)
        # A store's customers = anyone who ORDERED there OR RESIDES in its zone. The
        # zone residents were the gap: a customer in the area who hadn't ordered yet
        # never appeared on the store panel.
        resident_ids = zone_resident_customer_ids(store_id=store, zone_id=zone)
        qs = qs.filter(Exists(sub) | Q(id__in=resident_ids))

    qs = qs.distinct().annotate(
        _orders=Count("orders", distinct=True),
        _revenue=Sum("orders__total"),
        _last_active=Max("orders__placed_at"),
        _outstanding=Max("credit_account__outstanding"),
        _vs_score=Max("credit_account__vs_score"),
        _credit_status=Max("credit_account__status"),
    )

    risk_mode = bool(risk) or sort in ("high_risk_first", "low_risk_first")
    if risk_mode:
        scored = [(u, compute_risk(u)["level"]) for u in qs[:RISK_SCAN_CAP]]
        order = {"low": 0, "medium": 1, "high": 2, "critical": 3}
        if risk:
            scored = [s for s in scored if s[1] == risk]
        if sort == "high_risk_first":
            scored.sort(key=lambda s: order[s[1]], reverse=True)
        elif sort == "low_risk_first":
            scored.sort(key=lambda s: order[s[1]])
        return scored

    return qs.order_by(*CUSTOMER_SORTS.get(sort, ["-created_at"]))


def customer_rows(page):
    """Render one slice of :func:`customer_directory_source` into API rows.

    The source yields bare ``User`` objects on the DB-sorted path and
    ``(user, risk_level)`` pairs on the risk-scored path; this hides that seam
    from callers.
    """
    return [
        _cust_row(*item) if isinstance(item, tuple) else _cust_row(item)
        for item in page
    ]


def search_customers(query="", *, limit=100, **filters):
    """Bounded convenience wrapper — the first ``limit`` directory rows.

    Kept for callers that genuinely want a single capped slice (the CSV/Excel
    export). Anything user-facing should paginate ``customer_directory_source``
    instead, so nothing is silently cut off.
    """
    return customer_rows(customer_directory_source(query, **filters)[:limit])


# ── Shared lookups ───────────────────────────────────────
def _latest_order(user):
    from orders.models import Order

    return (
        Order.objects.filter(user=user)
        .select_related("zone", "store")
        .order_by("-placed_at")
        .first()
    )


def _collection_agent(user):
    from payments.models import CashCollection

    c = (
        CashCollection.objects.filter(user=user, agent__isnull=False)
        .select_related("agent")
        .order_by("-created_at")
        .first()
    )
    return c.agent if c else None


def _delivery_agent(user):
    from delivery.models import DeliveryTask

    t = (
        DeliveryTask.objects.filter(order__user=user, agent__isnull=False)
        .select_related("agent")
        .order_by("-created_at")
        .first()
    )
    return t.agent if t else None


# ── Section 1 — Executive header ─────────────────────────
def _header(user):
    o = _latest_order(user)
    zone = store = None
    if o and o.zone:
        zone, store = o.zone.name, (o.store.name if o.store else None)
    else:
        addr = user.addresses.filter(is_default=True).first() or user.addresses.first()
        if addr:
            from zones.serviceability import serviceability

            r = serviceability(lat=addr.latitude, lng=addr.longitude, pincode=addr.pincode)
            if r["serviceable"]:
                zone, store = r["zone_name"], r["store_name"]
    ca = _collection_agent(user)
    da = _delivery_agent(user)
    risk = compute_risk(user)
    return {
        "vsId": vs_id(user),
        "name": user.name,
        "phone": user.phone,
        "customerSince": user.created_at,
        "zone": zone,
        "store": store,
        "assignedAdmin": None,  # no explicit admin-assignment model yet
        "collectionAgent": ca.name if ca else None,
        "deliveryAgent": da.name if da else None,
        "status": "active" if user.is_active else "suspended",
        "risk": risk["level"],
        "avatarUrl": user.avatar_url,
    }


# ── Section 2 — Customer health score ────────────────────
def _health(user):
    from orders.models import Order
    from payments.models import CashCollection

    acc = getattr(user, "credit_account", None)
    o = Order.objects.filter(user=user).exclude(status="cancelled").aggregate(
        revenue=Sum("total"), orders=Count("id")
    )
    collected = _f(
        CashCollection.objects.filter(user=user, status="collected").aggregate(
            s=Sum("amount")
        )["s"]
    )
    months = max(1, round((timezone.now() - user.created_at).days / 30))
    return {
        "lifetimeRevenue": _f(o["revenue"]),
        "orders": o["orders"],
        "creditUsed": _f(acc.outstanding) if acc else 0,
        "collections": collected,
        "outstanding": _f(acc.outstanding) if acc else 0,
        "vsScore": acc.vs_score if acc else None,
        # None, not 100.0. `_credit` returns {"hasAccount": False} for a customer
        # with no credit account, so the old default reported a flawless
        # collection record for every cash-only customer — a number nobody had
        # measured, presented beside real ones.
        "collectionEfficiency": _credit(user).get("collectionEfficiency"),
        "retentionMonths": months,
    }


# ── Section 3 — Credit intelligence ──────────────────────
def _credit(user):
    from credit.models import CreditAccount, Statement

    acc = CreditAccount.objects.filter(user=user).first()
    if not acc:
        return {"hasAccount": False}
    stmts = Statement.objects.filter(account=acc)
    overdue = stmts.filter(status="overdue").aggregate(s=Sum("closing_balance"))["s"]
    next_due = (
        stmts.filter(status__in=["open", "overdue", "partially_paid"])
        .order_by("due_date").values_list("due_date", flat=True).first()
    )
    billed = _f(stmts.aggregate(s=Sum("purchases"))["s"]) + _f(
        stmts.aggregate(s=Sum("fees"))["s"]
    )
    paid = _f(stmts.aggregate(s=Sum("payments"))["s"])
    n_stmts = stmts.count() or 1
    avg_monthly = round(billed / n_stmts, 2)
    max_util = 0.0
    if acc.credit_limit:
        peak = stmts.aggregate(m=Max("closing_balance"))["m"]
        max_util = _pct(peak, acc.credit_limit)
    today = timezone.now().date()
    late = stmts.filter(status__in=["overdue", "partially_paid"]).count()
    missed = stmts.filter(status="overdue", due_date__lt=today).count()
    return {
        "hasAccount": True,
        "status": acc.status,
        "creditLimit": _f(acc.credit_limit),
        "availableCredit": _f(acc.available),
        "usedCredit": _f(acc.outstanding),
        "outstanding": _f(acc.outstanding),
        "overdue": _f(overdue),
        "nextDueDate": next_due,
        "averageMonthlyUsage": avg_monthly,
        "maximumUtilization": max_util,
        "repaymentRate": _pct(paid, billed),
        "latePayments": late,
        "missedPayments": missed,
        "collectionEfficiency": _pct(paid, billed) if billed else 100.0,
        "riskCategory": compute_risk(user)["level"],
        "usageTrend": _credit_usage_trend(acc),
    }


def _credit_usage_trend(acc, months=12):
    from credit.models import Statement

    rows = (
        Statement.objects.filter(account=acc).order_by("-period_end")[:months]
        .values("period_end", "purchases", "payments", "closing_balance")
    )
    return [
        {"period": r["period_end"].isoformat(),
         "purchases": _f(r["purchases"]), "payments": _f(r["payments"]),
         "balance": _f(r["closing_balance"])}
        for r in reversed(list(rows))
    ]


# ── Section 4 — Order analytics ──────────────────────────
def _orders(user):
    from orders.models import Order, OrderItem
    from returns.models import ReturnRequest

    qs = Order.objects.filter(user=user)
    month_start = timezone.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    agg = qs.aggregate(
        lifetime=Count("id"),
        this_month=Count("id", filter=Q(placed_at__gte=month_start)),
        delivered=Count("id", filter=Q(status="delivered")),
        cancelled=Count("id", filter=Q(status="cancelled")),
        aov=Avg("total"), highest=Max("total"),
        monthly_spend=Sum("total", filter=Q(placed_at__gte=month_start)),
    )
    returned = ReturnRequest.objects.filter(user=user).count()

    items = OrderItem.objects.filter(order__user=user).select_related("product__category")
    brand_counter = Counter()
    cat_counter = Counter()
    cat_spend = Counter()
    for it in items[:2000]:
        if it.brand:
            brand_counter[it.brand] += it.quantity
        cat = it.product.category.name if it.product and it.product.category else None
        if cat:
            cat_counter[cat] += it.quantity
            cat_spend[cat] += _f(it.price) * it.quantity

    # Preferred purchase hour.
    hours = Counter(o.placed_at.hour for o in qs.only("placed_at")[:2000])
    preferred_hour = hours.most_common(1)[0][0] if hours else None

    # Orders / revenue by month (last 12).
    by_month = {}
    for o in qs.exclude(status="cancelled").only("placed_at", "total")[:5000]:
        k = o.placed_at.strftime("%Y-%m")
        m = by_month.setdefault(k, {"orders": 0, "revenue": 0.0})
        m["orders"] += 1
        m["revenue"] += _f(o.total)
    months_series = [
        {"month": k, **v} for k, v in sorted(by_month.items())[-12:]
    ]

    return {
        "totalOrders": agg["lifetime"],
        "delivered": agg["delivered"],
        "cancelled": agg["cancelled"],
        "returned": returned,
        "averageOrderValue": round(_f(agg["aov"]), 2),
        "highestOrder": _f(agg["highest"]),
        "monthlySpend": _f(agg["monthly_spend"]),
        "favoriteCategories": [c for c, _ in cat_counter.most_common(5)],
        "favoriteBrands": [b for b, _ in brand_counter.most_common(5)],
        "preferredPurchaseHour": preferred_hour,
        "charts": {
            "byMonth": months_series,
            "categorySpend": [{"category": c, "spend": round(s, 2)}
                              for c, s in cat_spend.most_common(8)],
        },
    }


# ── Section 5 — Collection analytics ─────────────────────
def _collections(user):
    from payments.models import CashCollection

    qs = CashCollection.objects.filter(user=user)
    collected = qs.filter(status="collected")
    pending = qs.filter(status__in=["requested", "assigned"])
    failed = qs.filter(status="cancelled")
    last = collected.order_by("-collected_at").select_related("agent").first()
    spans = collected.exclude(collected_at__isnull=True).annotate(
        d=Max("collected_at")
    )
    days = [
        (c.collected_at - c.created_at).total_seconds() / 86400
        for c in collected.exclude(collected_at__isnull=True)[:500]
    ]
    return {
        "totalCollections": _f(collected.aggregate(s=Sum("amount"))["s"]),
        "totalCount": collected.count(),
        "pending": _f(pending.aggregate(s=Sum("amount"))["s"]),
        "failed": failed.count(),
        "averageRecoveryDays": round(sum(days) / len(days), 1) if days else 0.0,
        "lastCollectionAt": last.collected_at if last else None,
        "collectionAgent": last.agent.name if last and last.agent else None,
    }


# ── Section 7 — Verification center ──────────────────────
def _verification(user):
    from kyc.models import KycApplication, KycDocument
    from verification.models import VerificationEvidence, VerificationTask

    docs = {
        d["type"]: d["status"]
        for d in KycDocument.objects.filter(application__user=user).values("type", "status")
    }
    app = KycApplication.objects.filter(user=user).select_related("reviewed_by").first()
    house = (
        VerificationTask.objects.filter(customer=user, type="residence")
        .order_by("-created_at").first()
    )
    evidence = [
        {"kind": e.kind, "photoKey": e.photo_key,
         "lat": _f(e.latitude) if e.latitude else None,
         "lng": _f(e.longitude) if e.longitude else None}
        for e in VerificationEvidence.objects.filter(task__customer=user)[:20]
    ]
    gps = any(e["kind"] == "gps" for e in evidence)
    return {
        "aadhaar": docs.get("aadhaar", "not_submitted"),
        "pan": docs.get("pan", "not_submitted"),
        "selfie": docs.get("selfie", "not_submitted"),
        "house": house.status if house else "not_submitted",
        "gps": "captured" if gps else "not_captured",
        "agentVerified": VerificationTask.objects.filter(customer=user, status="approved").exists(),
        "verifiedAt": app.reviewed_at if app else None,
        "verifiedBy": app.reviewed_by.name if app and app.reviewed_by else None,
        "evidence": evidence,
    }


# ── Section 8 — Geographic intelligence ──────────────────
def _geographic(user):
    o = _latest_order(user)
    addr = user.addresses.filter(is_default=True).first() or user.addresses.first()
    store = o.store if o else None
    zone = o.zone if o else None
    return {
        "customer": {
            "lat": _f(addr.latitude) if addr and addr.latitude else None,
            "lng": _f(addr.longitude) if addr and addr.longitude else None,
            "address": addr.formatted if addr else None,
        },
        "store": {
            "name": store.name if store else None,
            "lat": _f(store.latitude) if store and store.latitude else None,
            "lng": _f(store.longitude) if store and store.longitude else None,
        } if store else None,
        "zone": {
            "name": zone.name if zone else None,
            "polygon": zone.polygon_geojson if zone else None,
        } if zone else None,
    }


# ── Section 9 — Notes (categorised) ──────────────────────
def _notes(user):
    from verification.models import VerificationTask

    from .models import CustomerNote

    grouped = {"admin": [], "collection": [], "delivery": [], "verification": []}
    for n in CustomerNote.objects.filter(customer=user)[:100]:
        grouped.setdefault(n.category, []).append({
            "id": str(n.id), "body": n.body,
            "author": n.author.name if n.author else None, "at": n.created_at,
        })
    # Verification notes also come from verification tasks.
    for t in VerificationTask.objects.filter(customer=user).exclude(note="")[:50]:
        grouped["verification"].append({
            "id": f"vt-{t.id}", "body": t.note, "author": None, "at": t.created_at,
        })
    return grouped


# ── Section 10 — Support history ─────────────────────────
def _support(user):
    from returns.models import ReturnRequest
    from support.models import SupportTicket

    tickets = SupportTicket.objects.filter(user=user)
    returns = ReturnRequest.objects.filter(user=user)
    refunds = returns.aggregate(s=Sum("refund_amount"))["s"]
    return {
        "tickets": tickets.count(),
        "open": tickets.filter(status__in=["open", "in_progress"]).count(),
        "complaints": tickets.filter(category__icontains="complaint").count(),
        "escalations": tickets.filter(priority="high").count(),
        "returns": returns.count(),
        "refunds": _f(refunds),
    }


# ── Section 11 — Customer network ────────────────────────
def _network(user):
    from accounts.models import User
    from credit.models import FamilyMember
    from referrals.models import Referral

    # Family members.
    family = []
    group = getattr(user, "family_group", None)
    if group:
        for m in group.members.exclude(status="removed"):
            family.append({"phone": m.phone, "relationship": m.relationship,
                           "status": m.status})

    # Same household — customers sharing this customer's pincode + area.
    addr = user.addresses.filter(is_default=True).first() or user.addresses.first()
    household = []
    if addr and addr.pincode:
        near = (
            User.objects.filter(role="customer", addresses__pincode=addr.pincode)
            .exclude(id=user.id)
        )
        if addr.area:
            near = near.filter(addresses__area__iexact=addr.area)
        household = [
            {"id": str(u.id), "name": u.name, "phone": u.phone}
            for u in near.distinct()[:20]
        ]

    # Referral network.
    referred = [
        {"id": str(r.referee_id), "code": r.code, "status": r.status}
        for r in Referral.objects.filter(referrer=user)[:50]
    ]
    referred_by = Referral.objects.filter(referee=user).first()

    return {
        "familyMembers": family,
        "sameHousehold": household,
        "referrals": referred,
        "referredBy": referred_by.referrer_id and str(referred_by.referrer_id) if referred_by else None,
    }


# ── Section 12 — Risk engine ─────────────────────────────
def compute_risk(user) -> dict:
    from credit.models import CreditAccount, Statement
    from orders.models import Order
    from payments.models import CashCollection

    acc = CreditAccount.objects.filter(user=user).first()
    account_age_days = (timezone.now() - user.created_at).days
    if not acc or acc.credit_limit == ZERO:
        return {"score": 0, "level": "low",
                "factors": {"creditExposure": False, "accountAgeDays": account_age_days}}

    utilization = min(_f(acc.outstanding) / _f(acc.credit_limit), 1.0)
    stmts = Statement.objects.filter(account=acc)
    billed = _f(stmts.aggregate(s=Sum("purchases"))["s"]) + _f(
        stmts.aggregate(s=Sum("fees"))["s"]
    )
    paid = _f(stmts.aggregate(s=Sum("payments"))["s"])
    repay_rate = min(paid / billed, 1.0) if billed else 1.0
    overdue = stmts.filter(status="overdue").count()
    late = stmts.filter(status__in=["overdue", "partially_paid"]).count()

    coll = CashCollection.objects.filter(user=user)
    collected = _f(coll.filter(status="collected").aggregate(s=Sum("amount"))["s"])
    pending = _f(coll.filter(status__in=["requested", "assigned"]).aggregate(s=Sum("amount"))["s"])
    coll_eff = collected / (collected + pending) if (collected + pending) else 1.0

    recent_orders = Order.objects.filter(
        user=user, placed_at__gte=timezone.now() - timedelta(days=90)
    ).count()
    inactivity = 1.0 if recent_orders == 0 else max(0.0, 1.0 - min(recent_orders, 6) / 6)
    age_factor = 1.0 if account_age_days < 60 else 0.0  # new accounts a touch riskier

    score = 100 * (
        0.30 * utilization
        + 0.28 * (1 - repay_rate)
        + 0.18 * min(overdue / 3, 1.0)
        + 0.10 * (1 - coll_eff)
        + 0.09 * inactivity
        + 0.05 * age_factor
    )
    score = round(score, 1)
    level = ("low" if score < 25 else "medium" if score < 50
             else "high" if score < 75 else "critical")
    return {
        "score": score, "level": level,
        "factors": {
            "creditUtilization": round(utilization, 2),
            "repaymentRate": round(repay_rate, 2),
            "outstanding": _f(acc.outstanding),
            "overdueStatements": overdue,
            "latePayments": late,
            "orderFrequency": recent_orders,
            "collectionSuccess": round(coll_eff, 2),
            "accountAgeDays": account_age_days,
        },
    }


# ── Section 14 — Financial exposure ──────────────────────
def _financial_exposure(user):
    from credit.models import CreditAccount, Statement

    acc = CreditAccount.objects.filter(user=user).first()
    if not acc:
        return {"hasExposure": False}
    outstanding = _f(acc.outstanding)
    overdue = Statement.objects.filter(account=acc, status="overdue").aggregate(
        s=Sum("closing_balance"), earliest=Min("due_date")
    )
    risk = compute_risk(user)
    recovery_prob = round(max(0.0, 1 - risk["score"] / 100), 2)
    earliest_due = overdue["earliest"]
    days_past_due = (timezone.now().date() - earliest_due).days if earliest_due else 0
    return {
        "hasExposure": True,
        "totalExposure": _f(acc.credit_limit),
        "currentOutstanding": outstanding,
        "overdueAmount": _f(overdue["s"]),
        "expectedRecovery": round(outstanding * recovery_prob, 2),
        "recoveryProbability": recovery_prob,
        "daysPastDue": max(0, days_past_due),
        "riskBucket": risk["level"],
        "projectedLoss": round(outstanding * (1 - recovery_prob), 2),
    }


# ── Section 15 — AI insights (heuristic) ─────────────────
def _ai_insights(user):
    from orders.models import Order

    risk = compute_risk(user)
    credit = _credit(user)
    health = _health(user)
    last_order = Order.objects.filter(user=user).aggregate(m=Max("placed_at"))["m"]
    dormant = not last_order or (timezone.now() - last_order).days > 60
    util = credit.get("usedCredit", 0) / credit["creditLimit"] if credit.get("creditLimit") else 0
    return {
        "_note": "heuristic flags (rule-based, not ML)",
        "likelyToDefault": risk["level"] in ("high", "critical"),
        "likelyToRepay": risk["level"] == "low" and credit.get("repaymentRate", 0) >= 80,
        "eligibleForLimitIncrease": (
            risk["level"] in ("low", "medium")
            and util >= 0.7
            and credit.get("repaymentRate", 0) >= 75
        ),
        "eligibleForPromotion": health["lifetimeRevenue"] >= 50000 and not dormant,
        "dormant": dormant,
        "highValue": health["lifetimeRevenue"] >= 100000,
    }


# ── Timeline (Section 6) ─────────────────────────────────
def build_timeline(user, limit: int = 80):
    from credit.models import CreditLedgerEntry
    from kyc.models import KycApplication
    from orders.models import Order
    from payments.models import CashCollection
    from verification.models import VerificationTask

    events = [{"type": "registered", "label": "Registered", "at": user.created_at}]

    app = KycApplication.objects.filter(user=user).first()
    if app and app.reviewed_at and app.status == "verified":
        events.append({"type": "kyc_approved", "label": "KYC approved", "at": app.reviewed_at})

    for e in CreditLedgerEntry.objects.filter(account__user=user).order_by("-created_at")[:limit]:
        label = {"purchase": "Credit purchase", "repayment": "Payment collected",
                 "fee": "Fee charged", "refund": "Refund issued"}.get(e.type, e.type)
        events.append({"type": f"credit_{e.type}", "label": label,
                       "at": e.created_at, "amount": _f(e.amount)})

    for o in Order.objects.filter(user=user).order_by("-placed_at")[:limit]:
        events.append({"type": "order", "label": f"Order {o.code} — {o.status}",
                       "at": o.placed_at, "amount": _f(o.total)})

    for c in CashCollection.objects.filter(user=user).order_by("-created_at")[:limit]:
        events.append({"type": "collection", "label": f"Collection {c.status}",
                       "at": c.collected_at or c.created_at, "amount": _f(c.amount)})

    for t in VerificationTask.objects.filter(customer=user).order_by("-created_at")[:limit]:
        events.append({"type": "verification",
                       "label": f"Verification {t.type} — {t.status}", "at": t.created_at})

    events = [e for e in events if e.get("at")]
    events.sort(key=lambda e: e["at"], reverse=True)
    return events[:limit]


# ── The 360 aggregate (all 15 sections) ──────────────────
def customer_360(user) -> dict:
    return {
        "header": _header(user),                 # 1
        "health": _health(user),                 # 2
        "creditIntelligence": _credit(user),     # 3
        "orderAnalytics": _orders(user),         # 4
        "collectionAnalytics": _collections(user),  # 5
        "timeline": build_timeline(user),        # 6
        "verification": _verification(user),     # 7
        "geographic": _geographic(user),         # 8
        "notes": _notes(user),                   # 9
        "support": _support(user),               # 10
        "network": _network(user),               # 11
        "risk": compute_risk(user),              # 12
        # 13 (action center) is exposed via the actions endpoint
        "financialExposure": _financial_exposure(user),  # 14
        "aiInsights": _ai_insights(user),        # 15
    }
