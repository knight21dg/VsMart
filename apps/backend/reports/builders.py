"""Each builder returns {title, columns, rows} computed from live data."""
from datetime import timedelta

from django.db.models import Count, Sum
from django.utils import timezone


def _num(v):
    return float(v or 0)


def sales(params=None):
    from orders.models import Order

    today = timezone.now().date()
    rows = []
    for i in range(29, -1, -1):
        d = today - timedelta(days=i)
        a = (Order.objects.filter(placed_at__date=d).exclude(status="cancelled")
             .aggregate(n=Count("id"), gmv=Sum("total"), pf=Sum("platform_fee")))
        rows.append([d.isoformat(), a["n"] or 0, _num(a["gmv"]), _num(a["pf"])])
    return {"title": "Sales (last 30 days)",
            "columns": ["Date", "Orders", "GMV", "Platform Fee"], "rows": rows}


def orders(params=None):
    from orders.models import Order

    rows = [[o.code, o.user.name or o.user.phone, o.status, _num(o.total),
             o.placed_at.strftime("%Y-%m-%d %H:%M")]
            for o in Order.objects.select_related("user")[:200]]
    return {"title": "Orders",
            "columns": ["Code", "Customer", "Status", "Total", "Placed"], "rows": rows}


def credit(params=None):
    from credit.models import CreditAccount

    rows = [[a.user.name or a.user.phone, _num(a.credit_limit), _num(a.outstanding),
             _num(a.available), a.status]
            for a in CreditAccount.objects.select_related("user")]
    return {"title": "Credit",
            "columns": ["Customer", "Limit", "Outstanding", "Available", "Status"],
            "rows": rows}


def collections(params=None):
    from payments.models import CashCollection

    rows = [[c.user.name or c.user.phone,
             (c.agent.name if c.agent else "-"), _num(c.amount), c.status,
             c.collected_at.strftime("%Y-%m-%d") if c.collected_at else "-"]
            for c in CashCollection.objects.select_related("user", "agent")[:200]]
    return {"title": "Collections",
            "columns": ["Customer", "Agent", "Amount", "Status", "Collected"],
            "rows": rows}


def inventory(params=None):
    from catalog.models import Product

    rows = [[p.name, p.brand, p.stock_count or 0, "Yes" if p.in_stock else "No"]
            for p in Product.objects.all()[:500]]
    return {"title": "Inventory",
            "columns": ["Product", "Brand", "Stock", "In stock"], "rows": rows}


def agents(params=None):
    from accounts.models import Role, User
    from delivery.models import DeliveryTask
    from payments.models import CashCollection

    rows = []
    for u in User.objects.filter(role=Role.AGENT):
        d = DeliveryTask.objects.filter(agent=u, status="delivered").count()
        c = CashCollection.objects.filter(agent=u, status="collected").count()
        rows.append([u.name or u.phone, d, c])
    return {"title": "Agents",
            "columns": ["Agent", "Deliveries", "Collections"], "rows": rows}


from .executive import EXECUTIVE_BUILDERS  # noqa: E402

BUILDERS = {
    "sales": sales, "orders": orders, "credit": credit,
    "collections": collections, "inventory": inventory, "agents": agents,
    **EXECUTIVE_BUILDERS,
}
