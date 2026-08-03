"""Zone -> Store isolation E2E smoke. Proves the secure, no-loophole contract:

  1. Super-admin creates two stores (auto-provisioned warehouses) and onboards a
     store admin for store A with an EMAIL + PASSWORD login.
  2. Super-admin draws two non-overlapping zones (GeoJSON polygons) and assigns one
     store to each.
  3. With zone_store_visibility + zone_enforcement ON:
       - a customer inside zone A sees ONLY store A's catalog (not store B's);
       - their order routes to store A and reserves/decrements store A's warehouse
         ONLY (store B's stock is never touched);
       - they CANNOT order a product store A doesn't carry (PRODUCT_UNAVAILABLE);
       - a customer OUTSIDE every zone is rejected at checkout (OUTSIDE_SERVICE_AREA);
       - a customer in zone B routes to store B.
  4. The store admin signs in (email+password), sees ONLY store A's orders, and is
     denied access to a store B order (cross-store isolation).
  5. On delivery, store A's on-hand drops; store B's on-hand is unchanged.

The two feature flags are flipped ON for the run and RESTORED in a finally block so
the other smoke suites (which assume a global catalog) are unaffected.

Run: .venv/Scripts/python.exe scripts/smoke_zone_e2e.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

import random  # noqa: E402
from decimal import Decimal  # noqa: E402

from rest_framework.test import APIClient  # noqa: E402

from accounts.models import Role, User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from catalog.models import Category, Product  # noqa: E402
from inventory.models import InventoryLedger  # noqa: E402
from inventory.services import InventoryService, StockCalculationService  # noqa: E402
from orders.models import Order  # noqa: E402
from orders.services import advance_status  # noqa: E402
from stores.models import Store, StoreProduct  # noqa: E402
from stores.services import ENFORCEMENT_FLAG, VISIBILITY_FLAG  # noqa: E402
from system.models import FeatureFlag  # noqa: E402
from zones.models import Zone  # noqa: E402

TAG = f"{random.randint(1000, 9999)}"
PW = "StoreAdmin#2026"
PASSED = 0

# Place this run's zones in an empty mid-ocean band, offset by the run tag, so repeated
# runs never overlap each other or the seeded zones (overlapping equal-priority zones are
# ambiguous). Zone A and Zone B are 3° apart (no overlap); the "outside" point is in the
# Arctic where no zone will ever exist.
_seed = int(TAG)
AX_LNG, AX_LAT = -160.0 + (_seed % 40) * 0.5, -8.0 + (_seed % 16) * 0.5
BX_LNG, BX_LAT = AX_LNG + 3.0, AX_LAT
OUT_LNG, OUT_LAT = 5.0, 80.0


def ok(label, cond, detail=""):
    global PASSED
    print(f"# {label}  [{'OK' if cond else 'FAIL'}]{(' ' + detail) if detail else ''}")
    assert cond, f"{label} FAILED  {detail}"
    PASSED += 1


def rphone():
    return f"+91{random.randint(7000000000, 9999999999)}"


def data_of(resp, expect_lt=400):
    assert resp.status_code < expect_lt, f"[{resp.status_code}] {resp.content[:400]}"
    body = resp.json()
    return body.get("data", body)


def err_code(resp):
    body = resp.json()
    return body.get("code") or body.get("error", {}).get("code")


def square(clng, clat, half=0.05):
    return {
        "type": "Polygon",
        "coordinates": [[
            [clng - half, clat - half], [clng + half, clat - half],
            [clng + half, clat + half], [clng - half, clat + half],
            [clng - half, clat - half],
        ]],
    }


# ── Flag state (restore on exit) ─────────────────────────
def set_flag(key, enabled):
    """Enable/disable a flag, returning its PRIOR state: True/False if the row
    existed, or None if it didn't (so restore can delete it again)."""
    existing = FeatureFlag.objects.filter(key=key).first()
    prev = existing.enabled if existing else None
    ff = existing or FeatureFlag(key=key)
    ff.enabled = enabled
    ff.save()
    return prev


def restore_flag(key, prev):
    if prev is None:
        FeatureFlag.objects.filter(key=key).delete()
    else:
        FeatureFlag.objects.filter(key=key).update(enabled=prev)


_prev_vis = set_flag(VISIBILITY_FLAG, True)
_prev_enf = set_flag(ENFORCEMENT_FLAG, True)

try:
    # Tidy any leftover test zones from earlier runs (keeps polygon resolution clean).
    Zone.objects.filter(code__startswith="ZONE-A-").delete()
    Zone.objects.filter(code__startswith="ZONE-B-").delete()

    # ── Actors ───────────────────────────────────────────
    superadmin = User.objects.create(phone=rphone(), name="E2E Super", role=Role.SUPERADMIN)
    sa = APIClient()
    sa.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(superadmin)['access_token']}")

    cat, _ = Category.objects.get_or_create(slug="e2e-grocery", defaults={"name": "E2E Grocery"})

    def make_product(label):
        return Product.objects.create(
            name=f"ZE-{label}-{TAG}", brand="E2E", unit="1 pc",
            price=Decimal("100.00"), mrp=Decimal("120.00"), category=cat,
            stock_count=0, in_stock=False,
        )

    pA1, pA2 = make_product("A1"), make_product("A2")
    pB1, pB2 = make_product("B1"), make_product("B2")

    # ── 1. Super-admin creates two stores (RBAC + auto-warehouse) ──
    sA = data_of(sa.post("/api/v1/admin/stores", {
        "code": f"ZE-A-{TAG}", "name": f"E2E Store A {TAG}",
        "address": "Zone A HQ", "latitude": f"{AX_LAT:.4f}",
        "longitude": f"{AX_LNG:.4f}", "phone": "9000000001", "status": "active",
    }, format="json"))
    sB = data_of(sa.post("/api/v1/admin/stores", {
        "code": f"ZE-B-{TAG}", "name": f"E2E Store B {TAG}",
        "address": "Zone B HQ", "latitude": f"{BX_LAT:.4f}",
        "longitude": f"{BX_LNG:.4f}", "phone": "9000000002", "status": "active",
    }, format="json"))
    storeA = Store.objects.select_related("warehouse").get(pk=sA["id"])
    storeB = Store.objects.select_related("warehouse").get(pk=sB["id"])
    ok("store A auto-provisioned a warehouse", storeA.warehouse_id is not None)
    ok("store B auto-provisioned a warehouse", storeB.warehouse_id is not None)
    ok("stores have DISTINCT warehouses", storeA.warehouse_id != storeB.warehouse_id,
       f"A={storeA.warehouse_id} B={storeB.warehouse_id}")
    whA, whB = storeA.warehouse, storeB.warehouse

    # ── Stock + per-store catalog mapping ──
    for p, wh in [(pA1, whA), (pA2, whA), (pB1, whB), (pB2, whB)]:
        InventoryService.post_movement(
            product=p, warehouse=wh, type=InventoryLedger.Type.GRN, quantity=100,
            unit_cost=p.price, ref_type="e2e", note="e2e stock", created_by=superadmin,
        )
    for p in (pA1, pA2):
        StoreProduct.objects.create(store=storeA, product=p, is_available=True)
    for p in (pB1, pB2):
        StoreProduct.objects.create(store=storeB, product=p, is_available=True)

    # ── 2. Super-admin draws two non-overlapping zones, assigns a store to each ──
    zA = data_of(sa.post("/api/v1/admin/zones", {
        "name": f"E2E Zone A {TAG}", "code": f"ZONE-A-{TAG}",
        "polygonGeojson": square(AX_LNG, AX_LAT), "store": int(storeA.id),
        "isActive": True, "creditEnabled": True, "priority": _seed,
        "deliveryFee": "15.00", "minOrder": "0.00", "freeDeliveryThreshold": "199.00",
    }, format="json"))
    zB = data_of(sa.post("/api/v1/admin/zones", {
        "name": f"E2E Zone B {TAG}", "code": f"ZONE-B-{TAG}",
        "polygonGeojson": square(BX_LNG, BX_LAT), "store": int(storeB.id),
        "isActive": True, "creditEnabled": True, "priority": _seed,
        "deliveryFee": "15.00", "minOrder": "0.00", "freeDeliveryThreshold": "199.00",
    }, format="json"))
    ok("zone A created + assigned to store A", str(zA.get("store")) == str(storeA.id))
    ok("zone B created + assigned to store B", str(zB.get("store")) == str(storeB.id))

    # ── 3. Super-admin onboards store A's admin (email + password login) ──
    admin_email = f"admin.a.{TAG}@vsmart.test"
    onboarded = data_of(sa.post(f"/api/v1/admin/stores/{storeA.id}/admin", {
        "email": admin_email, "password": PW, "name": "Store A Admin",
    }, format="json"))
    ok("store admin onboarded as manager", onboarded.get("isManager") is True,
       f"role={onboarded.get('staffRole')}")
    ok("onboarded admin carries the email", (onboarded.get("email") or "").lower() == admin_email)

    # RBAC: a plain admin (not superadmin) must NOT be able to onboard a store admin.
    plain_admin = User.objects.create(phone=rphone(), name="Plain Admin", role=Role.ADMIN)
    ac = APIClient()
    ac.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(plain_admin)['access_token']}")
    r = ac.post(f"/api/v1/admin/stores/{storeA.id}/admin",
                {"email": f"x{TAG}@y.test", "password": PW}, format="json")
    ok("non-superadmin CANNOT onboard a store admin", r.status_code == 403, f"[{r.status_code}]")

    # ── 4. Customer inside zone A ──
    custA = User.objects.create_user(phone=rphone(), name="Customer A")
    ca = APIClient()
    ca.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(custA)['access_token']}")
    addrA = data_of(ca.post("/api/v1/addresses", {
        "name": "Customer A", "phone": "9800000001", "line1": "1 A St",
        "area": "Zone A", "city": "ZoneA", "pincode": "110001",
        "latitude": f"{AX_LAT:.4f}", "longitude": f"{AX_LNG:.4f}", "isDefault": True,
    }, format="json"))

    serv = data_of(ca.get(f"/api/v1/serviceability/check?lat={AX_LAT:.4f}&lng={AX_LNG:.4f}"))
    ok("serviceability routes customer A to store A",
       str(serv.get("storeId")) == str(storeA.id), f"got storeId={serv.get('storeId')}")

    def names_of(resp):
        d = data_of(resp)
        rows = d if isinstance(d, list) else d.get("results", d)
        return {p["name"] for p in rows}

    # SERVER-SIDE resolution: NO ?store= param at all — the backend resolves store A
    # from the customer's saved address and returns ONLY store A's catalog.
    a_names = names_of(ca.get("/api/v1/products"))
    ok("catalog (no store param) resolves store A from address", {pA1.name, pA2.name} <= a_names)
    ok("catalog (no store param) HIDES store B products", not ({pB1.name, pB2.name} & a_names))
    ok("catalog (no store param) is store A ONLY, not the global catalog",
       a_names == {pA1.name, pA2.name}, f"unexpected leak: {a_names - {pA1.name, pA2.name}}")

    # The anti-loophole: a client CANNOT widen the catalog by spoofing a different store
    # id — the server ignores it and uses the address-resolved store.
    spoof = names_of(ca.get(f"/api/v1/products?store={storeB.id}"))
    ok("spoofed ?store=B is IGNORED (address resolves store A)",
       {pA1.name, pA2.name} <= spoof and not ({pB1.name, pB2.name} & spoof))

    # Pre-login browse: only a LOCATION (lat/lng) selects the store, never a store id.
    anon = APIClient()
    b_loc = names_of(anon.get(f"/api/v1/products?lat={BX_LAT:.4f}&lng={BX_LNG:.4f}"))
    ok("location params resolve store B catalog",
       {pB1.name, pB2.name} <= b_loc and not ({pA1.name, pA2.name} & b_loc))

    # Out-of-area / unknown location => EMPTY catalog, never the global one.
    ok("out-of-area location returns EMPTY catalog (no global leak)",
       len(names_of(anon.get(f"/api/v1/products?lat={OUT_LAT:.4f}&lng={OUT_LNG:.4f}"))) == 0)
    fresh = APIClient()
    fresh.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(User.objects.create_user(phone=rphone(), name='No Addr'))['access_token']}")
    ok("authed user with NO address + NO location returns EMPTY (no global leak)",
       len(names_of(fresh.get("/api/v1/products"))) == 0)

    # Search is scoped the same way.
    srch = names_of(ca.get(f"/api/v1/products/search?q=ZE-"))
    ok("search is store-scoped (store A only)", not ({pB1.name, pB2.name} & srch))

    # Cross-store product DETAIL 404s (a deep link can't reveal another store's product).
    ok("cross-store product detail 404 for store-A customer",
       ca.get(f"/api/v1/products/{pB1.id}").status_code == 404)
    ok("own-store product detail OK", ca.get(f"/api/v1/products/{pA1.id}").status_code == 200)

    # #6 Hidden-from-sale: a store can hold inventory but pull a product from sale.
    spA2 = StoreProduct.objects.get(store=storeA, product=pA2)
    spA2.is_available = False
    spA2.save(update_fields=["is_available"])
    ok("delisted product disappears from catalog", pA2.name not in names_of(ca.get("/api/v1/products")))
    ok("delisted product still has inventory", StockCalculationService.on_hand(pA2, whA) > 0)
    spA2.is_available = True
    spA2.save(update_fields=["is_available"])

    # Helper: a fresh zone-A customer with one item in cart, ready to checkout.
    def zoneA_buyer(product, qty=1):
        u = User.objects.create_user(phone=rphone(), name="ZA Buyer")
        cl = APIClient()
        cl.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(u)['access_token']}")
        ad = data_of(cl.post("/api/v1/addresses", {
            "name": "ZA Buyer", "phone": "9800000009", "line1": "x", "area": "Zone A",
            "city": "ZoneA", "pincode": "110001",
            "latitude": f"{AX_LAT:.4f}", "longitude": f"{AX_LNG:.4f}", "isDefault": True,
        }, format="json"))
        data_of(cl.post("/api/v1/cart/items", {"productId": product.id, "quantity": qty}, format="json"))
        return cl, ad

    # Capture stock before ordering.
    a_avail_before = StockCalculationService.available(pA1, whA)
    b_avail_before = StockCalculationService.available(pB1, whB)

    data_of(ca.post("/api/v1/cart/items", {"productId": pA1.id, "quantity": 3}, format="json"))
    order_resp = ca.post("/api/v1/checkout", {"addressId": addrA["id"], "paymentMethod": "cod"},
                         format="json")
    ok("customer A checkout succeeds", order_resp.status_code < 400, f"[{order_resp.status_code}]")
    orderA = Order.objects.filter(user=custA).latest("placed_at")
    ok("order A routed to store A", orderA.store_id == storeA.id, f"store={orderA.store_id}")
    ok("order A routed to zone A", str(orderA.zone_id) == str(zA["id"]))
    # #8 Immutable order snapshot (invoice history can't break later).
    ok("order snapshots store name", orderA.store_name == storeA.name, orderA.store_name)
    ok("order snapshots zone name", orderA.zone_name == zA["name"], orderA.zone_name)
    _oi = orderA.items.first()
    ok("order line snapshots GST rate", _oi is not None and _oi.gst_rate is not None,
       f"gst={getattr(_oi, 'gst_rate', None)}")

    a_avail_after = StockCalculationService.available(pA1, whA)
    b_avail_after = StockCalculationService.available(pB1, whB)
    ok("store A stock reserved (available -3)", a_avail_after == a_avail_before - 3,
       f"{a_avail_before} -> {a_avail_after}")
    ok("store B stock UNTOUCHED by store A order", b_avail_after == b_avail_before,
       f"{b_avail_before} -> {b_avail_after}")

    # Loophole probe: try to order a product store A does NOT carry (store B's product).
    data_of(ca.post("/api/v1/cart/items", {"productId": pB1.id, "quantity": 1}, format="json"))
    bad = ca.post("/api/v1/checkout", {"addressId": addrA["id"], "paymentMethod": "cod"},
                  format="json")
    ok("cross-store item REJECTED at checkout", bad.status_code >= 400 and err_code(bad) == "PRODUCT_UNAVAILABLE",
       f"[{bad.status_code}] code={err_code(bad)}")
    # store B stock still untouched after the rejected attempt.
    ok("store B stock still UNTOUCHED after rejected cross-store order",
       StockCalculationService.available(pB1, whB) == b_avail_before)
    ca.delete(f"/api/v1/cart/items/{pB1.id}")  # tidy cart (best-effort)

    # ── Ops gates: store closed (#4), capacity full (#5), address moved (#1) ──
    storeA.accepting_orders = False
    storeA.save(update_fields=["accepting_orders"])
    clc, adc = zoneA_buyer(pA1)
    rc = clc.post("/api/v1/checkout", {"addressId": adc["id"], "paymentMethod": "cod"}, format="json")
    ok("closed store rejects checkout (STORE_CLOSED)",
       rc.status_code >= 400 and err_code(rc) == "STORE_CLOSED", f"[{rc.status_code}] {err_code(rc)}")
    storeA.accepting_orders = True
    storeA.save(update_fields=["accepting_orders"])

    storeA.refresh_from_db()
    storeA.daily_order_capacity = storeA.orders_today()  # already at capacity
    storeA.save(update_fields=["daily_order_capacity"])
    clp, adp = zoneA_buyer(pA1)
    rp = clp.post("/api/v1/checkout", {"addressId": adp["id"], "paymentMethod": "cod"}, format="json")
    ok("full store rejects checkout (DELIVERY_CAPACITY_REACHED)",
       rp.status_code >= 400 and err_code(rp) == "DELIVERY_CAPACITY_REACHED", f"[{rp.status_code}] {err_code(rp)}")
    storeA.daily_order_capacity = None
    storeA.save(update_fields=["daily_order_capacity"])

    # #1 Cart built for store A, then delivery address moved into store B's zone.
    clx, adx = zoneA_buyer(pA1)  # cart now bound to store A
    adxB = data_of(clx.post("/api/v1/addresses", {
        "name": "ZA Buyer", "phone": "9800000009", "line1": "y", "area": "Zone B",
        "city": "ZoneB", "pincode": "600001",
        "latitude": f"{BX_LAT:.4f}", "longitude": f"{BX_LNG:.4f}", "isDefault": False,
    }, format="json"))
    rx = clx.post("/api/v1/checkout", {"addressId": adxB["id"], "paymentMethod": "cod"}, format="json")
    ok("store-A cart + delivery into zone B -> STORE_CHANGED (never an A->B order)",
       rx.status_code >= 400 and err_code(rx) == "STORE_CHANGED", f"[{rx.status_code}] {err_code(rx)}")
    cart_after = data_of(clx.get("/api/v1/cart"))
    ok("STORE_CHANGED cleared the stale cart server-side",
       len((cart_after.get("items") or [])) == 0, f"items={len(cart_after.get('items') or [])}")

    # ── 5. Customer OUTSIDE every zone is rejected ──
    custOut = User.objects.create_user(phone=rphone(), name="Customer Out")
    co = APIClient()
    co.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(custOut)['access_token']}")
    addrOut = data_of(co.post("/api/v1/addresses", {
        "name": "Customer Out", "phone": "9800000003", "line1": "Far Away",
        "area": "Nowhere", "city": "Arctic", "pincode": "400050",
        "latitude": f"{OUT_LAT:.4f}", "longitude": f"{OUT_LNG:.4f}", "isDefault": True,
    }, format="json"))
    data_of(co.post("/api/v1/cart/items", {"productId": pA1.id, "quantity": 1}, format="json"))
    out = co.post("/api/v1/checkout", {"addressId": addrOut["id"], "paymentMethod": "cod"},
                  format="json")
    ok("out-of-zone checkout REJECTED with 4xx", out.status_code >= 400 and err_code(out) == "OUTSIDE_SERVICE_AREA",
       f"[{out.status_code}] code={err_code(out)}")
    ok("out-of-zone order was NOT created", not Order.objects.filter(user=custOut).exists())

    # ── 6. Customer in zone B routes to store B ──
    custB = User.objects.create_user(phone=rphone(), name="Customer B")
    cb = APIClient()
    cb.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(custB)['access_token']}")
    addrB = data_of(cb.post("/api/v1/addresses", {
        "name": "Customer B", "phone": "9800000002", "line1": "1 B St",
        "area": "Zone B", "city": "ZoneB", "pincode": "600001",
        "latitude": f"{BX_LAT:.4f}", "longitude": f"{BX_LNG:.4f}", "isDefault": True,
    }, format="json"))
    data_of(cb.post("/api/v1/cart/items", {"productId": pB1.id, "quantity": 2}, format="json"))
    obresp = cb.post("/api/v1/checkout", {"addressId": addrB["id"], "paymentMethod": "cod"},
                     format="json")
    ok("customer B checkout succeeds", obresp.status_code < 400, f"[{obresp.status_code}]")
    orderB = Order.objects.filter(user=custB).latest("placed_at")
    ok("order B routed to store B", orderB.store_id == storeB.id, f"store={orderB.store_id}")

    # ── 7. Store admin A: email+password login, store-scoped order view ──
    login = APIClient().post("/api/v1/auth/login", {"email": admin_email, "password": PW},
                             format="json")
    ok("store admin email+password login works", login.status_code == 200, f"[{login.status_code}]")
    tok = login.json()["data"]["access_token"]
    adm = APIClient()
    adm.credentials(HTTP_AUTHORIZATION=f"Bearer {tok}")
    me = data_of(adm.get("/api/v1/store/me"))
    ok("store admin /store/me scoped to store A", str(me["store"]["id"]) == str(storeA.id))

    orders_list = data_of(adm.get("/api/v1/store/orders"))
    olist = orders_list if isinstance(orders_list, list) else orders_list.get("results", orders_list)
    codes = {o["code"] for o in olist}
    ok("store admin SEES store A order", orderA.code in codes)
    ok("store admin does NOT see store B order", orderB.code not in codes,
       f"leaked={orderB.code in codes}")

    cross = adm.get(f"/api/v1/store/orders/{orderB.code}")
    ok("store admin DENIED store B order detail (cross-store)", cross.status_code == 404,
       f"[{cross.status_code}]")

    # ── 8. Delivery fulfilment isolation ──
    a_onhand_before = StockCalculationService.on_hand(pA1, whA)
    b_onhand_before = StockCalculationService.on_hand(pB1, whB)
    advance_status(orderA, "delivered")
    ok("store A on-hand drops on delivery (-3)",
       StockCalculationService.on_hand(pA1, whA) == a_onhand_before - 3,
       f"{a_onhand_before} -> {StockCalculationService.on_hand(pA1, whA)}")
    ok("store B on-hand UNCHANGED by store A delivery",
       StockCalculationService.on_hand(pB1, whB) == b_onhand_before)

    # ── #10 Single stock source: a POS sale hits the SAME store warehouse as online ──
    from pos.services import checkout as pos_checkout
    from pos.services import open_session

    cashier = User.objects.create(phone=rphone(), name="POS Cashier", role=Role.ADMIN)
    sess = open_session(cashier=cashier, warehouse=whA, opening_cash=0)
    ok("POS till opens on the store's own warehouse", sess.warehouse_id == whA.id)
    pos_before = StockCalculationService.on_hand(pA1, whA)
    pos_checkout(session=sess, lines=[{"product": pA1, "qty": 2}],
                 payments=[{"method": "cash", "amount": 1000}], by=cashier, allow_partial=True)
    ok("POS sale decrements the SAME warehouse online uses (single stock source)",
       StockCalculationService.on_hand(pA1, whA) == pos_before - 2,
       f"{pos_before} -> {StockCalculationService.on_hand(pA1, whA)}")

    # ── #3 Disabling a zone cuts off serviceability, catalog AND checkout there ──
    Zone.objects.filter(pk=zB["id"]).update(is_active=False)
    anon3 = APIClient()
    serv_b = data_of(anon3.get(f"/api/v1/serviceability/check?lat={BX_LAT:.4f}&lng={BX_LNG:.4f}"))
    ok("disabled zone -> not serviceable", serv_b.get("serviceable") is False, f"{serv_b.get('serviceable')}")
    ok("disabled zone -> empty catalog",
       len(names_of(anon3.get(f"/api/v1/products?lat={BX_LAT:.4f}&lng={BX_LNG:.4f}"))) == 0)
    uz = User.objects.create_user(phone=rphone(), name="ZB After")
    clz = APIClient()
    clz.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(uz)['access_token']}")
    adz = data_of(clz.post("/api/v1/addresses", {
        "name": "ZB After", "phone": "9800000004", "line1": "z", "area": "Zone B",
        "city": "ZoneB", "pincode": "600001",
        "latitude": f"{BX_LAT:.4f}", "longitude": f"{BX_LNG:.4f}", "isDefault": True,
    }, format="json"))
    data_of(clz.post("/api/v1/cart/items", {"productId": pB1.id, "quantity": 1}, format="json"))
    rz = clz.post("/api/v1/checkout", {"addressId": adz["id"], "paymentMethod": "cod"}, format="json")
    ok("disabled zone -> checkout rejected (OUTSIDE_SERVICE_AREA)",
       rz.status_code >= 400 and err_code(rz) == "OUTSIDE_SERVICE_AREA", f"[{rz.status_code}] {err_code(rz)}")

    print("\n" + "=" * 64)
    print(f"  ZONE E2E SMOKE PASSED - {PASSED} assertions green")
    print("  zone -> store -> store-admin -> catalog -> order routing -> inventory")
    print("  isolation verified with enforcement + visibility ON.")
    print("=" * 64)

finally:
    restore_flag(VISIBILITY_FLAG, _prev_vis)
    restore_flag(ENFORCEMENT_FLAG, _prev_enf)
    # Drop this run's zones so repeated runs don't accumulate overlapping polygons
    # (Order.zone is SET_NULL, so placed orders survive). Test products can't be deleted
    # (OrderItem refs), but we clear their GLOBAL sellable flag so they never leak into
    # other smokes that pick `Product.objects.filter(in_stock=True).first()` — their
    # stock only ever lived in a store warehouse, not the default one.
    Zone.objects.filter(code__in=[f"ZONE-A-{TAG}", f"ZONE-B-{TAG}"]).delete()
    Product.objects.filter(name__startswith="ZE-").update(in_stock=False, stock_count=0)
    print(f"[flags restored to prior state: {VISIBILITY_FLAG}={_prev_vis}, "
          f"{ENFORCEMENT_FLAG}={_prev_enf}; test zones cleaned]")
