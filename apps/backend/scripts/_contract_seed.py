"""Reference rows for the admin contract dump.

The dump has to see *populated* responses: an endpoint that returns `[]` reveals
none of its field names, and a field name that is never emitted is exactly what
this is hunting for. So every module gets one real row, and the ids come back so
parameterised routes (`admin/zones/<pk>`) can be called for real.

Deliberately small — one row per module, not a demo dataset. It runs inside a
throwaway test database.
"""
from datetime import timedelta
from decimal import Decimal

from django.utils import timezone


def seed_reference_data():
    """Create one row per module. Returns {url-param-name: id} for the dump."""
    from accounts.models import User
    from catalog.models import Category, Product
    from inventory.models import Warehouse
    from orders.models import Order, OrderItem
    from stores.models import Store
    from zones.models import Zone

    ids = {}

    customer = User.objects.create(
        phone="+919000001111", name="Contract Customer", role="customer",
        email="contract.customer@example.com",
    )
    agent = User.objects.create(
        phone="+919000002222", name="Contract Agent", role="agent",
    )
    ids["user_id"] = customer.id
    ids["agent_id"] = agent.id

    warehouse = Warehouse.objects.create(name="Contract WH", code="WH-C", is_active=True)
    store = Store.objects.create(
        code="ST-C", name="Contract Store", status="active", warehouse=warehouse,
        address="1 Test Road", phone="+919000003333",
    )
    ids["store_id"] = store.id

    zone = Zone.objects.create(name="Contract Zone", code="ZN-C", store=store)
    ids["zone_id"] = zone.id

    category = Category.objects.create(name="Contract Cat", slug="contract-cat")
    product = Product.objects.create(
        name="Contract Product", brand="CB", unit="1kg", price=Decimal("100"),
        mrp=Decimal("120"), category=category, sku="CONTRACT-1", stock_count=10,
    )

    order = Order.objects.create(user=customer, zone=zone, store=store)
    OrderItem.objects.create(
        order=order, product=product, quantity=1, name=product.name,
        price=Decimal("100"), mrp=Decimal("120"),
    )

    # `pk` is the catch-all for every ModelViewSet detail route. There is no one
    # right answer, so the dump reports a 404 rather than guessing — the value
    # here just has to exist somewhere. Zones are registered first and are the
    # most-linked object, so they make the least-surprising default.
    ids["pk"] = zone.id
    ids["id"] = zone.id
    ids["code"] = order.code if hasattr(order, "code") else "ZN-C"
    ids["slug"] = category.slug
    ids["content_type_id"] = 1

    ids["product"] = product.id
    ids["customer"] = customer.id
    ids["warehouse"] = warehouse.id
    ids["wid"] = warehouse.id
    ids["activeZone"] = zone.id
    # `/reports/${active}` is a tab name, not an id.
    ids["active"] = "sales"

    _optional_rows(ids, customer=customer, agent=agent, store=store,
                   order=order, product=product, warehouse=warehouse)
    return ids


def seed_store_manager(ids):
    """A store manager for the store-panel sweep.

    `/store/*` is gated on an active StoreStaff row at an active store — not on
    the platform role — so a superadmin token reaches none of it. Manager is the
    right seat to sweep from: it implicitly holds every permission, so a 403
    under it means the endpoint is misgated rather than under-granted.
    """
    from accounts.models import User
    from stores.models import Store
    from storeops.models import StoreStaff

    manager = User.objects.create(
        phone="+919000004444", name="Contract Manager", role="store_staff",
    )
    StoreStaff.objects.create(
        user=manager, store=Store.objects.get(pk=ids["store_id"]),
        staff_role=StoreStaff.StaffRole.MANAGER, is_active=True,
    )
    return manager


def _optional_rows(ids, *, customer, agent, store, order, product, warehouse):
    """Rows whose apps may not be installed in every configuration.

    Each block is independent and best-effort: a module that changed shape must
    not take the whole dump down with it, or one refactor blinds every other
    module's contract check.
    """
    now = timezone.now()

    try:
        from payments.models import Payment

        payment = Payment.objects.create(
            order=order, user=customer, amount=Decimal("100"),
            status="success", method="cod",
        )
        ids["payment"] = payment.id
    except Exception:
        pass

    try:
        from payments.models import CashDeposit

        deposit = CashDeposit.objects.create(
            agent=agent, store=store, amount=Decimal("100"),
            deposited_on=now.date(),
        )
        ids["deposit"] = deposit.id
    except Exception:
        pass

    try:
        from credit.models import CreditApplication

        application = CreditApplication.objects.create(
            user=customer, requested_limit=Decimal("5000"),
        )
        ids["application"] = application.id
    except Exception:
        pass

    try:
        from returns.models import ReturnRequest

        rr = ReturnRequest.objects.create(
            user=customer, order=order, reason="damaged",
        )
        # The returns route takes a CODE, not an id — and so does support. The
        # two share the `${code}` template name with orders, so the last writer
        # would win; they are resolved by their own key instead.
        ids["returns_code"] = rr.code
    except Exception:
        pass

    try:
        from support.models import SupportTicket

        ticket = SupportTicket.objects.create(
            user=customer, subject="Contract ticket",
        )
        ids["support_code"] = ticket.code
    except Exception:
        pass

    try:
        from inventory.models import PurchaseInvoice, Supplier

        supplier = Supplier.objects.create(name="Contract Supplier")
        invoice = PurchaseInvoice.objects.create(
            supplier=supplier, store=store, invoice_number="INV-C-1",
            invoice_date=now.date(), due_date=(now + timedelta(days=30)).date(),
            subtotal=Decimal("100"), tax=Decimal("18"), total=Decimal("118"),
        )
        ids["invoice"] = invoice.id
        ids["supplier"] = supplier.id
    except Exception:
        pass

    try:
        from offers.models import Coupon

        Coupon.objects.create(
            code="CONTRACT10", discount_type="percent", discount_value=Decimal("10"),
            valid_from=now - timedelta(days=1), valid_to=now + timedelta(days=30),
        )
    except Exception:
        pass

    try:
        from inventory.models import StockItem

        StockItem.objects.create(product=product, warehouse=warehouse, quantity=10)
    except Exception:
        pass

    return ids
