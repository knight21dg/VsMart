"""Superadmin control-plane smoke: platform config + fees, zones (radius + per-zone
overrides), platform fee applied at checkout, analytics, inventory adjust, admin credit,
and RBAC (admin cannot touch money levers). Run: python scripts/smoke_admin.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from decimal import Decimal  # noqa: E402

from rest_framework.test import APIClient  # noqa: E402

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from catalog.models import Category, Product  # noqa: E402


def phone():
    return f"+91{random.randint(7000000000, 9999999999)}"


customer = User.objects.create_user(phone=phone(), name="Zone Cust")
admin = User.objects.create(phone=phone(), name="Admin", role="admin")
boss = User.objects.create(phone=phone(), name="Boss", role="superadmin")

if not Product.objects.exists():
    cat = Category.objects.create(name="Groceries", slug="groceries")
    Product.objects.create(name="Apple", brand="Groceries", unit="1 kg", price=165,
                           mrp=189, category=cat, stock_count=50)
product = Product.objects.filter(in_stock=True).first()


def cl(u):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(u)['access_token']}")
    return c


cust, adm, sup = cl(customer), cl(admin), cl(boss)
fails = []


def step(label, resp, ok=(200, 201), show=None):
    good = resp.status_code in ok
    extra = ""
    if show and good:
        d = resp.json().get("data", resp.json())
        extra = "  " + " ".join(f"{k}={d.get(k)}" for k in show)
    print(f"# {label}  [{resp.status_code}] {'OK' if good else 'FAIL'}{extra}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:160]))
    return resp.json().get("data", {}) if resp.content else {}


# ── 1. superadmin sets money config (2% platform fee) ──
step("PATCH /admin/config (superadmin)", sup.patch("/api/v1/admin/config", {
    "platform_fee_type": "percent", "platform_fee_value": 2, "gst_rate": 0.18,
}, format="json"), show=["platformFeeType", "platformFeeValue"])
# admin can read, cannot write
step("GET /admin/config (admin reads)", adm.get("/api/v1/admin/config"))
r = adm.patch("/api/v1/admin/config", {"platform_fee_value": 5}, format="json")
print(f"# admin BLOCKED from editing config  [{r.status_code}] {'OK' if r.status_code == 403 else 'FAIL'}")
fails.append(("rbac config", r.status_code, b"")) if r.status_code != 403 else None

# ── 2. superadmin creates a zone with overrides ──
zone = step("POST /admin/zones (superadmin)", sup.post("/api/v1/admin/zones", {
    "name": "Central BLR", "center_lat": "12.9716", "center_lng": "77.5946",
    "radius_km": "8", "pincodes": ["560001"], "delivery_fee": "30",
    "free_delivery_threshold": "100000",
}, format="json"), ok=(201,))
r = adm.post("/api/v1/admin/zones", {"name": "X", "center_lat": "1", "center_lng": "1"}, format="json")
print(f"# admin BLOCKED from creating zone  [{r.status_code}] {'OK' if r.status_code == 403 else 'FAIL'}")
fails.append(("rbac zone", r.status_code, b"")) if r.status_code != 403 else None

# ── 3. serviceability check ──
chk = step("GET /zones/check?pincode=560001", cust.get("/api/v1/zones/check?pincode=560001"),
           show=["serviceable", "zone", "deliveryFee"])
assert chk.get("serviceable") is True
assert Decimal(str(chk.get("deliveryFee"))) == Decimal("30")

# ── 4. checkout in-zone reflects platform fee + zone delivery override ──
addr = step("POST /addresses (in zone)", cust.post("/api/v1/addresses", {
    "name": "Zone Cust", "phone": "9800000009", "line1": "1 MG Rd",
    "pincode": "560001", "is_default": True}, format="json"), ok=(201,))
cust.post("/api/v1/cart/items", {"product_id": product.id, "quantity": 1}, format="json")
order = step("POST /checkout (in zone)", cust.post("/api/v1/checkout", {
    "address_id": addr["id"], "payment_method": "cod"}, format="json"), ok=(201,),
    show=["subtotal", "deliveryFee", "gst", "platformFee", "total"])
assert Decimal(str(order["platformFee"])) > 0, "platform fee not applied"
assert Decimal(str(order["deliveryFee"])) == Decimal("30"), "zone delivery override not applied"
exp_fee = (Decimal(str(order["subtotal"])) * 2 / 100).quantize(Decimal("0.01"))
assert Decimal(str(order["platformFee"])) == exp_fee, "platform fee math wrong"

# ── 5. analytics ──
step("GET /admin/analytics/overview", adm.get("/api/v1/admin/analytics/overview"),
     show=["orders", "gmv", "platformFeeCollected", "averageOrderValue"])
step("GET /admin/analytics/sales?days=7", adm.get("/api/v1/admin/analytics/sales?days=7"))
step("GET /admin/analytics/top-products", adm.get("/api/v1/admin/analytics/top-products"))
step("GET /admin/analytics/zones", adm.get("/api/v1/admin/analytics/zones"))

# ── 6. inventory ──
step("GET /admin/inventory", adm.get("/api/v1/admin/inventory"))
inv = step("POST /admin/inventory/{id}/adjust (+25)",
           adm.post(f"/api/v1/admin/inventory/{product.id}/adjust",
                    {"delta": 25, "reason": "restock"}, format="json"),
           show=["stockCount", "inStock"])

# ── 7. admin credit controls ──
step("PATCH /admin/credit/{id} (limit 20000)",
     adm.patch(f"/api/v1/admin/credit/{customer.id}",
               {"credit_limit": "20000"}, format="json"), show=["creditLimit", "status"])
step("POST /admin/credit/{id}/freeze",
     adm.post(f"/api/v1/admin/credit/{customer.id}/freeze", {}, format="json"),
     show=["status"])

print("\n" + ("ALL CONTROL-PLANE CHECKS PASSED" if not fails else f"FAILURES: {fails}"))
