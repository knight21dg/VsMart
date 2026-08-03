"""Real-time delivery WebSocket smoke.

Proves the live push contract end-to-end (in-memory channel layer, no Redis):
  1. A customer connects to ws/orders/<code>/tracking with their JWT and gets the
     initial snapshot.
  2. An agent GPS ping (delivery.services.log_location) fans out a 'tracking'
     message with the fresh coords to that socket.
  3. The dispatch board socket (ws/admin/delivery/command-center) receives the
     same update; a non-admin is rejected; a stranger can't watch someone's order.

Run: .venv/Scripts/python.exe scripts/smoke_ws.py
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
from config.asgi import application  # noqa: E402
from delivery.models import DeliveryTask  # noqa: E402
from delivery.services import log_location  # noqa: E402
from orders.models import Order  # noqa: E402
from storeops.models import StoreStaff  # noqa: E402
from stores.models import Store  # noqa: E402

PASSED = 0


def ok(label, cond, detail=""):
    global PASSED
    print(f"# {label}  [{'OK' if cond else 'FAIL'}]{(' ' + detail) if detail else ''}")
    assert cond, f"{label} FAILED {detail}"
    PASSED += 1


def rphone():
    return f"+91{random.randint(7000000000, 9999999999)}"


def setup():
    customer = User.objects.create_user(phone=rphone(), name="WS Customer")
    agent = User.objects.create(phone=rphone(), name="WS Agent", role=Role.AGENT)
    admin = User.objects.create(phone=rphone(), name="WS Admin", role=Role.SUPERADMIN)
    stranger = User.objects.create_user(phone=rphone(), name="WS Stranger")
    suffix = random.randint(100000, 999999)
    store = Store.objects.create(code=f"WSST{suffix}", name="WS Store", status="active")
    other_store = Store.objects.create(
        code=f"WSST{suffix}B", name="WS Other Store", status="active")
    own_staff = User.objects.create(phone=rphone(), name="WS Own Staff", role=Role.STORE_STAFF)
    StoreStaff.objects.create(user=own_staff, store=store, staff_role="manager")
    other_staff = User.objects.create(phone=rphone(), name="WS Other Staff", role=Role.STORE_STAFF)
    StoreStaff.objects.create(user=other_staff, store=other_store, staff_role="manager")
    order = Order.objects.create(
        user=customer, store=store, payment_method="cod", status="out_for_delivery",
        subtotal=Decimal("100"), total=Decimal("118"),
        address_snapshot={"latitude": 12.9720, "longitude": 77.5950},
    )
    task = DeliveryTask.objects.create(
        order=order, agent=agent, status=DeliveryTask.Status.OUT_FOR_DELIVERY,
        dest_lat=Decimal("12.9720"), dest_lng=Decimal("77.5950"),
    )
    return {
        "order": order, "agent": agent, "task": task,
        "cust_tok": issue_tokens(customer)["access_token"],
        "admin_tok": issue_tokens(admin)["access_token"],
        "stranger_tok": issue_tokens(stranger)["access_token"],
        "own_staff_tok": issue_tokens(own_staff)["access_token"],
        "other_staff_tok": issue_tokens(other_staff)["access_token"],
    }


async def main():
    d = await sync_to_async(setup)()
    code = d["order"].code

    # ── Customer connects + receives the initial snapshot ──
    cust = WebsocketCommunicator(application, f"/ws/orders/{code}/tracking?token={d['cust_tok']}")
    connected, _ = await cust.connect()
    ok("customer WS connects with JWT", connected)
    snap = await cust.receive_json_from(timeout=5)
    ok("customer gets initial tracking snapshot", snap.get("type") == "tracking")
    ok("snapshot carries the destination coords", snap["data"].get("destLat") is not None)

    # ── Admin dispatch board connects ──
    adm = WebsocketCommunicator(application, f"/ws/admin/delivery/command-center?token={d['admin_tok']}")
    aconn, _ = await adm.connect()
    ok("admin dispatch WS connects", aconn)

    # ── An agent GPS ping fans out to both sockets ──
    await sync_to_async(log_location)(d["agent"], 12.9800, 77.6010, task=d["task"])
    msg = await cust.receive_json_from(timeout=5)
    ok("customer receives live position push", msg.get("type") == "tracking", str(msg.get("data", {}).get("latitude")))
    ok("pushed latitude is the fresh ping", abs(float(msg["data"]["latitude"]) - 12.9800) < 1e-6)
    ok("push carries an ETA", bool(msg["data"].get("eta")))
    amsg = await adm.receive_json_from(timeout=5)
    ok("dispatch board receives the same update", amsg.get("type") == "dispatch" and amsg["data"]["orderCode"] == code)

    await cust.disconnect()
    await adm.disconnect()

    # ── RBAC: non-admin rejected from dispatch; stranger rejected from the order ──
    bad_adm = WebsocketCommunicator(application, f"/ws/admin/delivery/command-center?token={d['stranger_tok']}")
    bconn, _ = await bad_adm.connect()
    ok("non-admin REJECTED from dispatch board", not bconn)

    bad_ord = WebsocketCommunicator(application, f"/ws/orders/{code}/tracking?token={d['stranger_tok']}")
    sconn, _ = await bad_ord.connect()
    ok("stranger REJECTED from another customer's order", not sconn)

    noauth = WebsocketCommunicator(application, f"/ws/orders/{code}/tracking")
    nconn, _ = await noauth.connect()
    ok("unauthenticated WS REJECTED", not nconn)

    # ── Store-admin panel: the order's own store can track it; another store can't ──
    own = WebsocketCommunicator(application, f"/ws/orders/{code}/tracking?token={d['own_staff_tok']}")
    oconn, _ = await own.connect()
    ok("order's own store staff CAN connect", oconn)
    osnap = await own.receive_json_from(timeout=5)
    ok("store staff gets the initial tracking snapshot", osnap.get("type") == "tracking")
    await own.disconnect()

    other = WebsocketCommunicator(application, f"/ws/orders/{code}/tracking?token={d['other_staff_tok']}")
    oth_conn, _ = await other.connect()
    ok("a DIFFERENT store's staff REJECTED", not oth_conn)

    print("\n" + "=" * 60)
    print(f"  REAL-TIME WS SMOKE PASSED — {PASSED} assertions green")
    print("=" * 60)


asyncio.run(main())
