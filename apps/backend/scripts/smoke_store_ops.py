"""Store-Admin OPS smoke: purchase entry → stock, POS sale (cash), receipt,
day-closing, reports, collections, returns. Run:
    .venv/Scripts/python.exe scripts/smoke_store_ops.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from rest_framework.test import APIClient  # noqa: E402

from accounts.models import Role, User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from catalog.models import Category, Product  # noqa: E402
from inventory.models import Warehouse  # noqa: E402
from orders.models import Order  # noqa: E402
from storeops.models import StoreStaff  # noqa: E402
from stores.models import Store  # noqa: E402

fails = []


def ph():
    return f"+91{random.randint(7000000000, 9999999999)}"


def cl(u):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(u)['access_token']}")
    return c


def step(label, resp, ok=(200, 201), show=None):
    good = resp.status_code in (ok if isinstance(ok, tuple) else (ok,))
    extra = ""
    if good and show:
        body = resp.json().get("data", resp.json())
        if isinstance(body, dict):
            extra = "  " + " ".join(f"{k}={body.get(k)}" for k in show)
        elif isinstance(body, list):
            extra = f"  ({len(body)} rows)"
    print(f"# {label}  [{resp.status_code}] {'OK' if good else 'FAIL'}{extra}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:220]))
    try:
        return resp.json().get("data", {})
    except Exception:
        return {}


# ── Setup ──
sfx = random.randint(1000, 9999)
wh = Warehouse.objects.create(name=f"OpsWH{sfx}", code=f"WH-OPS-{sfx}", is_active=True)
store = Store.objects.create(code=f"STORE-OPS-{sfx}", name="Ops Store", status="active",
                             warehouse=wh, address="1 Ops Rd", phone="0800")
manager = User.objects.create(phone=ph(), name="Ops Manager", role=Role.STORE_STAFF)
StoreStaff.objects.create(user=manager, store=store, staff_role="manager", title="Manager")
mgr = cl(manager)

cat, _ = Category.objects.get_or_create(name="Ops Groceries", slug=f"ops-groceries-{sfx}")
product = Product.objects.create(name=f"Ops Rice {sfx}", brand="Ops", unit="1 kg",
                                 price=60, mrp=75, category=cat, sku=f"OPS-{sfx}",
                                 is_active=True)

# A store customer (has an order at this store) for collections / credit.
customer = User.objects.create(phone=ph(), name="Ops Customer", role=Role.CUSTOMER)
Order.objects.create(user=customer, store=store, code=f"OPS-ORD-{sfx}", total=500,
                     subtotal=500, status="delivered", payment_method="credit",
                     payment_status="pending", credit_used=500)

print("== Purchase entry → stock ==")
pe = step("POST /store/purchases (record invoice)", mgr.post("/api/v1/store/purchases", {
    "invoiceNumber": f"INV-{sfx}", "items": [
        {"productId": str(product.id), "quantity": 100, "unitCost": 40, "batchNo": f"B{sfx}"},
    ],
}, format="json"), show=["status", "totalCost"])
inv = step("GET /store/inventory", mgr.get("/api/v1/store/inventory"))
on_hand = next((r["available"] for r in inv if r["productId"] == str(product.id)), None)
print(f"  -> {product.name} available = {on_hand}")
if on_hand != 100:
    fails.append(("stock after purchase", on_hand, b"expected 100"))

print("\n== POS sale ==")
step("POST /store/pos/session (open)", mgr.post("/api/v1/store/pos/session",
     {"openingCash": 500}, format="json"), show=["session"])
step("GET /store/pos/search", mgr.get("/api/v1/store/pos/search", {"q": "Ops Rice"}))
sale = step("POST /store/pos/checkout (cash)", mgr.post("/api/v1/store/pos/checkout", {
    "items": [{"productId": str(product.id), "qty": 3}],
    "payments": [{"method": "cash", "amount": 500}],
}, format="json"), show=["code", "total", "changeDue", "paymentStatus"])
code = sale.get("code")
step("GET /store/pos/transactions", mgr.get("/api/v1/store/pos/transactions"))
if code:
    step(f"GET /store/pos/transactions/{code}/receipt",
         mgr.get(f"/api/v1/store/pos/transactions/{code}/receipt"))
# Stock should now be 97
inv2 = step("GET /store/inventory (after sale)", mgr.get("/api/v1/store/inventory"))
after = next((r["available"] for r in inv2 if r["productId"] == str(product.id)), None)
print(f"  -> available after selling 3 = {after}")
if after != 97:
    fails.append(("stock after sale", after, b"expected 97"))

print("\n== Offline POS: catalog snapshot (for local caching) ==")
snap = step("GET /store/pos/catalog", mgr.get("/api/v1/store/pos/catalog"),
            show=["warehouseId"])
prods = snap.get("products", []) if isinstance(snap, dict) else []
row = next((p for p in prods if p["productId"] == str(product.id)), None)
if row is None:
    fails.append(("catalog snapshot", None, b"product missing from catalog"))
elif row.get("available") != 97 or "barcode" not in row:
    fails.append(("catalog fields", row, b"expected available=97 + barcode key"))
else:
    print(f"  -> catalog has {len(prods)} products; {product.name} available={row['available']}")

print("\n== Offline POS: idempotent replay (same Idempotency-Key, no double-post) ==")
idem = f"offline-{sfx}-001"
body = {"items": [{"productId": str(product.id), "qty": 2}],
        "payments": [{"method": "cash", "amount": 200}]}
r1 = mgr.post("/api/v1/store/pos/checkout", body, format="json", HTTP_IDEMPOTENCY_KEY=idem)
step("POST checkout (key, 1st)", r1)
r2 = mgr.post("/api/v1/store/pos/checkout", body, format="json", HTTP_IDEMPOTENCY_KEY=idem)
step("POST checkout (key, replay)", r2)
c1 = (r1.json().get("data") or {}).get("code")
c2 = (r2.json().get("data") or {}).get("code")
if c1 and c1 == c2:
    print(f"  -> replay returned the same sale {c1}")
else:
    fails.append(("idempotent replay", (c1, c2), b"expected same code"))
inv3 = mgr.get("/api/v1/store/inventory").json().get("data", [])
after2 = next((r["available"] for r in inv3 if r["productId"] == str(product.id)), None)
if after2 != 95:
    fails.append(("stock after replay", after2, b"expected 95 (decremented once, not twice)"))
else:
    print(f"  -> stock decremented exactly once: available={after2}")

print("\n== Offline POS: out-of-stock sync conflict → 409 ==")
conflict = mgr.post("/api/v1/store/pos/checkout",
                    {"items": [{"productId": str(product.id), "qty": 9999}],
                     "payments": [{"method": "cash", "amount": 100}]},
                    format="json", HTTP_IDEMPOTENCY_KEY=f"offline-{sfx}-x")
if conflict.status_code == 409:
    cbody = conflict.json()
    ecode = (cbody.get("error") or cbody.get("data", {}).get("error") or {}).get("code")
    print(f"  -> 409 conflict, code={ecode}")
    if ecode != "pos_out_of_stock":
        fails.append(("conflict code", ecode, b"expected pos_out_of_stock"))
else:
    fails.append(("out-of-stock 409", conflict.status_code, conflict.content[:160]))

step("POST /store/pos/session/close", mgr.post("/api/v1/store/pos/session/close",
     {"countedCash": None}, format="json"), show=["totalSales", "variance"])

print("\n== Reports ==")
step("GET /store/reports/sales", mgr.get("/api/v1/store/reports/sales"), show=["title"])
step("GET /store/reports/inventory", mgr.get("/api/v1/store/reports/inventory"), show=["title"])
step("GET /store/reports/top-products", mgr.get("/api/v1/store/reports/top-products"), show=["title"])
step("GET /store/reports/credit", mgr.get("/api/v1/store/reports/credit"), show=["title"])

print("\n== Collections + Returns ==")
coll = step("POST /store/collections (create)", mgr.post("/api/v1/store/collections", {
    "customerId": str(customer.id), "amount": 200,
}, format="json"), show=["status", "amount"])
step("GET /store/collections", mgr.get("/api/v1/store/collections"))
if coll.get("id"):
    step("POST /store/collections/<id>/collect",
         mgr.post(f"/api/v1/store/collections/{coll['id']}/collect", {}, format="json"),
         show=["status"])
step("GET /store/returns", mgr.get("/api/v1/store/returns"))

print("\n" + ("ALL STORE-OPS CHECKS PASSED" if not fails else f"FAILURES: {len(fails)}"))
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
