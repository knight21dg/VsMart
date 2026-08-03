"""Store panel new-order WebSocket smoke.

Proves the live "New Order" push contract end-to-end (in-memory channel
layer, no Redis):
  1. Store staff connect to ws/store/orders with their JWT.
  2. A real checkout (orders.services.place_order) that routes to their store
     fans out a 'new_order' push to that socket, deferred to commit.
  3. A DIFFERENT store's staff do NOT receive it. An unauthenticated /
     non-staff connection is rejected outright.

`place_order` defers the broadcast via `transaction.on_commit`, which never
fires inside Django's TestCase (it wraps each test in a rolled-back
transaction) — hence a script with real commits, matching smoke_ws.py.

Run: .venv/Scripts/python.exe scripts/smoke_store_orders_ws.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

import asyncio  # noqa: E402
import random  # noqa: E402
from decimal import Decimal  # noqa: E402

from asgiref.sync import sync_to_async  # noqa: E402
from channels.testing import WebsocketCommunicator  # noqa: E402

from accounts.models import Role, User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from addresses.models import Address  # noqa: E402
from cart.services import upsert_item  # noqa: E402
from catalog.models import Category, Product  # noqa: E402
from config.asgi import application  # noqa: E402
from inventory.models import Warehouse  # noqa: E402
from inventory.services import InventoryService  # noqa: E402
from orders.models import Order  # noqa: E402
from stores.models import Store  # noqa: E402
from storeops.models import StoreStaff  # noqa: E402
from zones.models import Zone  # noqa: E402

PASSED = 0

# Square over central Bengaluru ([lng, lat]) — matches orders.tests.ZoneRoutingTests.
SQUARE = {
    "type": "Polygon",
    "coordinates": [[
        [77.55, 12.95], [77.65, 12.95], [77.65, 13.00],
        [77.55, 13.00], [77.55, 12.95],
    ]],
}


def ok(label, cond, detail=""):
    global PASSED
    print(f"# {label}  [{'OK' if cond else 'FAIL'}]{(' ' + detail) if detail else ''}")
    assert cond, f"{label} FAILED {detail}"
    PASSED += 1


def rphone():
    return f"+91{random.randint(7000000000, 9999999999)}"


def cleanup_prior_runs():
    """This script runs against a real, persistent dev DB with real commits (see
    module docstring). Old Warehouses can't be deleted (InventoryLedger.warehouse
    is PROTECT — an append-only ledger, by design), so instead of cleaning up we
    make each run's own zone win on priority alone (see the random priority in
    setup() below) rather than relying on stale rows being gone."""
    Zone.objects.filter(name="WS Zone").delete()
    Store.objects.filter(name__in=["WS Store A", "WS Store B"]).delete()


def setup():
    cleanup_prior_runs()
    wh_a = Warehouse.objects.create(name="WS Store A WH", code=f"WSA{random.randint(1000,9999)}")
    wh_b = Warehouse.objects.create(name="WS Store B WH", code=f"WSB{random.randint(1000,9999)}")
    store_a = Store.objects.create(
        name="WS Store A", code=f"WSA{random.randint(1000,9999)}", warehouse=wh_a,
        latitude=Decimal("12.9720"), longitude=Decimal("77.5950"), status="active",
    )
    store_b = Store.objects.create(
        name="WS Store B", code=f"WSB{random.randint(1000,9999)}", warehouse=wh_b,
        latitude=Decimal("12.9720"), longitude=Decimal("77.5950"), status="active",
    )
    manager_a = User.objects.create(phone=rphone(), name="Manager A", role=Role.STORE_STAFF)
    manager_b = User.objects.create(phone=rphone(), name="Manager B", role=Role.STORE_STAFF)
    StoreStaff.objects.create(
        store=store_a, user=manager_a, staff_role="manager", is_active=True,
        permissions=["dashboard.view", "orders.view"],
    )
    StoreStaff.objects.create(
        store=store_b, user=manager_b, staff_role="manager", is_active=True,
        permissions=["dashboard.view", "orders.view"],
    )
    Zone.objects.create(
        # This dev DB has other seeded zones over the same area (e.g. "Bengaluru
        # Central" at priority 10), INCLUDING leftover "WS Zone" rows from past
        # runs of this same script (Warehouses are PROTECT via InventoryLedger,
        # so cleanup_prior_runs() can't remove those). On a priority TIE,
        # `_zone_for_point` favours the lower id — i.e. an OLD leftover zone —
        # so a fixed priority would silently lose to stale data forever. A
        # random high priority guarantees this run's zone wins outright.
        code=f"WSZ{random.randint(1000,9999)}", name="WS Zone", polygon_geojson=SQUARE,
        store=store_a, is_active=True, credit_enabled=True,
        priority=random.randint(100_000, 999_999),
    )
    stranger = User.objects.create_user(phone=rphone(), name="WS Stranger")

    cat, _ = Category.objects.get_or_create(name="WS Grocery", slug=f"ws-grocery-{random.randint(1000,9999)}")
    product = Product.objects.create(
        name="WS Rice", brand="VS", unit="1 kg", price=Decimal("50"),
        mrp=Decimal("60"), category=cat, stock_count=None,
    )
    InventoryService.adjust(product, set=100, warehouse=wh_a)

    customer = User.objects.create_user(phone=rphone(), name="WS Customer")
    address = Address.objects.create(
        user=customer, name="Cust", phone=rphone(), line1="MG Rd",
        latitude=Decimal("12.9720"), longitude=Decimal("77.5950"), pincode="560001",
    )
    return {
        "store_a": store_a, "store_b": store_b, "product": product,
        "customer": customer, "address": address,
        "mgr_a_tok": issue_tokens(manager_a)["access_token"],
        "mgr_b_tok": issue_tokens(manager_b)["access_token"],
        "stranger_tok": issue_tokens(stranger)["access_token"],
    }


async def main():
    d = await sync_to_async(setup)()

    # ── Both stores' staff connect ──
    a = WebsocketCommunicator(application, f"/ws/store/orders?token={d['mgr_a_tok']}")
    aconn, _ = await a.connect()
    ok("store A staff WS connects with JWT", aconn)

    b = WebsocketCommunicator(application, f"/ws/store/orders?token={d['mgr_b_tok']}")
    bconn, _ = await b.connect()
    ok("store B staff WS connects with JWT", bconn)

    # ── A real checkout routed to store A fires on commit ──
    from cart.services import get_cart
    from orders.services import place_order

    async def checkout():
        cart = await sync_to_async(get_cart)(d["customer"])
        await sync_to_async(upsert_item)(cart, d["product"], None, 1)
        return await sync_to_async(place_order)(
            d["customer"], address=d["address"], payment_method=Order.PaymentMethod.COD,
        )

    order = await checkout()
    ok("checkout succeeded and routed to a store", order.store_id is not None)

    msg = await a.receive_json_from(timeout=5)
    ok("store A receives the new_order push", msg.get("type") == "new_order")
    ok("push carries the right order code", msg["data"]["code"] == order.code)
    ok("push carries the order value", float(msg["data"]["value"]) == float(order.total))

    # ── Store B (a different store) must NOT receive it ──
    got_cross_store_leak = True
    try:
        await b.receive_json_from(timeout=1)
    except asyncio.TimeoutError:
        got_cross_store_leak = False
    ok("store B does NOT receive store A's order", not got_cross_store_leak)

    await a.disconnect()
    # `b`'s timed-out receive above already cancels its internal task — a
    # disconnect() call afterwards just raises CancelledError during teardown.
    try:
        await b.disconnect()
    except asyncio.CancelledError:
        pass

    # ── RBAC: a non-staff user and an unauthenticated connection are rejected ──
    bad = WebsocketCommunicator(application, f"/ws/store/orders?token={d['stranger_tok']}")
    sconn, _ = await bad.connect()
    ok("non-staff REJECTED from store orders socket", not sconn)

    noauth = WebsocketCommunicator(application, "/ws/store/orders")
    nconn, _ = await noauth.connect()
    ok("unauthenticated WS REJECTED", not nconn)

    print("\n" + "=" * 60)
    print(f"  STORE ORDERS WS SMOKE PASSED — {PASSED} assertions green")
    print("=" * 60)


asyncio.run(main())
