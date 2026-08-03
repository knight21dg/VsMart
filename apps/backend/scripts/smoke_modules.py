"""Workflow smoke for the enterprise modules: geography, inventory, delivery,
verification, billing. Run: python scripts/smoke_modules.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from rest_framework.test import APIClient  # noqa: E402

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from billing.models import Invoice, InvoiceItem, Receipt  # noqa: E402
from catalog.models import Category, Product  # noqa: E402
from delivery.models import DeliveryTask  # noqa: E402
from geography.models import Area, District, GeoZone, State, Warehouse  # noqa: E402
from inventory.models import StockItem  # noqa: E402
from inventory.models import Warehouse as InvWarehouse  # noqa: E402
from orders.models import Order  # noqa: E402
from verification.models import VerificationTask  # noqa: E402


def phone():
    return f"+91{random.randint(7000000000, 9999999999)}"


def cl(u):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(u)['access_token']}")
    return c


customer = User.objects.create_user(phone=phone(), name="Cust")
agent = User.objects.create(phone=phone(), name="Agent", role="agent")
admin = User.objects.create(phone=phone(), name="Admin", role="admin")
cu, ag, ad = cl(customer), cl(agent), cl(admin)
fails = []


def step(label, resp, ok=(200, 201)):
    good = resp.status_code in ok
    print(f"# {label}  [{resp.status_code}] {'OK' if good else 'FAIL'}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:160]))
    return resp.json().get("data") if resp.content else None


# ── geography ──
st = State.objects.create(name="Karnataka", code=f"KA{random.randint(1,9999)}")
di = District.objects.create(state=st, name="Bengaluru", code="BLR")
gz = GeoZone.objects.create(district=di, name="South", code="SO")
ar = Area.objects.create(zone=gz, name="Ballari", code=f"BAL{random.randint(1,999)}")
Warehouse.objects.create(name="WH Central", code=f"WH{random.randint(1,9999)}",
                         area=ar, serviceable_pincodes=["560001"])
step("GET /geography/states", cu.get("/api/v1/geography/states"))
step("GET /geography/districts?state", cu.get(f"/api/v1/geography/districts?state={st.id}"))
step("GET /geography/areas?q", cu.get("/api/v1/geography/areas?q=Ballari"))
step("GET /geography/stores", cu.get("/api/v1/geography/stores"))
serv = step("GET /geography/serviceable", cu.get("/api/v1/geography/serviceable?pincode=560001"))
assert serv and serv["serviceable"] is True

# ── inventory ──
cat = Category.objects.first() or Category.objects.create(name="Groceries", slug="groceries")
product = Product.objects.first() or Product.objects.create(
    name="Apple", brand="G", unit="1kg", price=100, mrp=120, category=cat)
wh1 = InvWarehouse.objects.create(name="A", code=f"A{random.randint(1,9999)}")
wh2 = InvWarehouse.objects.create(name="B", code=f"B{random.randint(1,9999)}")
StockItem.objects.create(product=product, warehouse=wh1, quantity=100, reserved=5)
step("GET /inventory/warehouses", ad.get("/api/v1/inventory/warehouses"))
step("GET /inventory/products", ad.get("/api/v1/inventory/products"))
step("GET /inventory/stock", ad.get("/api/v1/inventory/stock"))
step("POST /inventory/transfer", ad.post("/api/v1/inventory/transfer", {
    "product_id": product.id, "from_warehouse": wh1.id, "to_warehouse": wh2.id,
    "quantity": 10}, format="json"))
step("GET /inventory/transfers", ad.get("/api/v1/inventory/transfers"))
step("POST /inventory/purchase-orders", ad.post("/api/v1/inventory/purchase-orders", {
    "supplier_name": "ACME", "warehouse": wh1.id,
    "items": [{"product_id": product.id, "quantity": 50, "unit_cost": "80.00"}]},
    format="json"))
step("GET /inventory/purchase-orders", ad.get("/api/v1/inventory/purchase-orders"))

# ── delivery workflow ──
order = Order.objects.create(user=customer, payment_method="cod", status="packed",
                             subtotal=100, total=118)
task = DeliveryTask.objects.create(order=order, agent=agent, status="assigned")
step("GET /deliveries/assigned", ag.get("/api/v1/deliveries/assigned"))
step("POST /deliveries/{id}/accept", ag.post(f"/api/v1/deliveries/{task.id}/accept", {}, format="json"))
started = step("POST /deliveries/{id}/start", ag.post(f"/api/v1/deliveries/{task.id}/start", {}, format="json"))
task.refresh_from_db()
step("POST /deliveries/{id}/otp (verify)", ag.post(
    f"/api/v1/deliveries/{task.id}/otp", {"otp": task.otp}, format="json"))
step("POST /deliveries/{id}/complete", ag.post(f"/api/v1/deliveries/{task.id}/complete", {}, format="json"))
order.refresh_from_db()
assert order.status == "delivered", "delivery complete did not mark order delivered"
step("POST /deliveries/location", ag.post("/api/v1/deliveries/location",
     {"latitude": "12.97", "longitude": "77.59"}, format="json"))

# ── verification workflow ──
vt = VerificationTask.objects.create(customer=customer, type="residence", status="pending")
step("GET /verification/tasks", ag.get("/api/v1/verification/tasks"))
step("POST /verification/tasks/{id}/start", ag.post(f"/api/v1/verification/tasks/{vt.id}/start", {}, format="json"))
step("POST /verification/photo", ag.post("/api/v1/verification/photo",
     {"task_id": vt.id, "photo_key": "kyc/x.jpg"}, format="json"))
step("POST /verification/gps", ag.post("/api/v1/verification/gps",
     {"task_id": vt.id, "latitude": "12.9", "longitude": "77.5"}, format="json"))
step("POST /verification/tasks/{id}/submit", ag.post(
    f"/api/v1/verification/tasks/{vt.id}/submit", {"decision": "approve"}, format="json"))

# ── billing ──
inv = Invoice.objects.create(user=customer, amount=118, gst=18, status="issued")
InvoiceItem.objects.create(invoice=inv, name="Apple", quantity=1, price=100)
Receipt.objects.create(user=customer, amount=118, method="upi")
step("GET /billing/invoices", cu.get("/api/v1/billing/invoices"))
step("GET /billing/invoices/{id}", cu.get(f"/api/v1/billing/invoices/{inv.id}"))
step("GET /billing/receipts", cu.get("/api/v1/billing/receipts"))

print("\n" + ("ALL MODULE CHECKS PASSED" if not fails else f"FAILURES: {fails}"))
