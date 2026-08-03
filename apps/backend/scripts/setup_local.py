"""Provision a ready-to-test local environment (idempotent — safe to re-run):
  · a superadmin + admin (Django admin + API), a demo customer with credit
  · a default warehouse with stock received for the seeded products
  · a barcode per product (for POS scan testing)
  · prints fresh JWT access tokens + the key URLs.
Run: python scripts/setup_local.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from decimal import Decimal  # noqa: E402

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from catalog.models import Product  # noqa: E402
from credit.services import ensure_account  # noqa: E402
from inventory.models import Barcode, InventoryLedger, Warehouse  # noqa: E402
from inventory.services import InventoryService, StockCalculationService  # noqa: E402
from stores.models import Store  # noqa: E402
from zones.models import Zone  # noqa: E402

PASSWORD = "Admin@123"


def upsert_user(phone, name, role, password=None, **extra):
    user, created = User.objects.get_or_create(
        phone=phone, defaults={"name": name, "role": role, **extra}
    )
    if not created:
        user.name, user.role = name, role
        for k, v in extra.items():
            setattr(user, k, v)
    if password:
        user.set_password(password)
    user.save()
    return user


# ── Staff + customer ─────────────────────────────────────
superadmin = upsert_user("+919999999999", "VS Super Admin", "superadmin", PASSWORD)
admin = upsert_user("+919888888888", "VS Store Admin", "admin", PASSWORD)
customer = upsert_user(
    "+919000000001", "Demo Customer", "customer",
    kyc_status="verified", credit_enabled=True,
)

acc = ensure_account(customer)
acc.credit_limit = Decimal("10000.00")
acc.status = "active"
acc.save(update_fields=["credit_limit", "status"])

# ── Default warehouse ────────────────────────────────────
warehouse, _ = Warehouse.objects.get_or_create(
    code="MAIN", defaults={"name": "Main Store", "is_default": True}
)
if not warehouse.is_default:
    warehouse.is_default = True
    warehouse.save(update_fields=["is_default"])

# ── Store + serviceable polygon zone ─────────────────────
# One store, holding its stock in the MAIN warehouse, serving a polygon over
# central Bengaluru. Customers inside the polygon are serviceable; outside ⇒ not.
store, _ = Store.objects.update_or_create(
    code="STORE-BLR-01",
    defaults={
        "name": "VS Mart Bengaluru Central",
        "address": "MG Road, Bengaluru, Karnataka",
        "latitude": Decimal("12.9750"),
        "longitude": Decimal("77.6000"),
        "phone": "9000000010",
        "status": Store.Status.ACTIVE,
        "warehouse": warehouse,
    },
)
blr_polygon = {
    "type": "Polygon",
    "coordinates": [[
        [77.45, 12.85], [77.75, 12.85], [77.75, 13.10],
        [77.45, 13.10], [77.45, 12.85],
    ]],
}
zone, _ = Zone.objects.update_or_create(
    code="ZONE-BLR-CENTRAL",
    defaults={
        "name": "Bengaluru Central",
        "polygon_geojson": blr_polygon,
        "store": store,
        "is_active": True,
        "credit_enabled": True,
        "estimated_delivery_minutes": 20,
        "priority": 10,
        "delivery_fee": Decimal("15.00"),
        "min_order": Decimal("99.00"),
        "free_delivery_threshold": Decimal("199.00"),
    },
)

# ── Stock + barcodes for the seeded products ─────────────
stocked = 0
for p in Product.objects.all()[:12]:
    bc_code = f"890{p.id:010d}"
    Barcode.objects.get_or_create(
        code=bc_code,
        defaults={"product": p, "symbology": "EAN13", "is_primary": True},
    )
    on_hand = StockCalculationService.on_hand(p, warehouse)
    if on_hand < 50:
        InventoryService.post_movement(
            product=p, warehouse=warehouse, type=InventoryLedger.Type.GRN,
            quantity=100 - on_hand, unit_cost=p.price, ref_type="setup",
            note="Local setup stock", created_by=admin,
        )
        stocked += 1

# ── Report ───────────────────────────────────────────────
sa_tok = issue_tokens(superadmin)["access_token"]
ad_tok = issue_tokens(admin)["access_token"]
cu_tok = issue_tokens(customer)["access_token"]

bar = "=" * 64
print(f"\n{bar}\n  VS MART — LOCAL TEST ENVIRONMENT READY\n{bar}")
print(f"  Products in catalog : {Product.objects.count()}")
print(f"  Warehouse           : {warehouse.name} ({warehouse.code}, default)")
print(f"  Store / Zone        : {store.name} <-> {zone.name} (polygon, serviceable)")
print(f"  Topped up stock for : {stocked} product(s) to ~100 units each")
print(f"  Barcodes            : {Barcode.objects.count()} total")
print(bar)
print("  DJANGO ADMIN   http://127.0.0.1:8000/admin/")
print(f"    superadmin   phone +919999999999   password {PASSWORD}")
print(f"    store admin  phone +919888888888   password {PASSWORD}")
print(bar)
print("  SWAGGER UI     http://127.0.0.1:8000/api/docs/")
print("  ReDoc          http://127.0.0.1:8000/api/redoc/")
print("    -> click 'Authorize', paste one of the Bearer tokens below")
print(bar)
print("  API BASE       http://127.0.0.1:8000/api/v1")
print("  Demo customer  phone +919000000001  (credit limit 10000, KYC verified)")
print(bar)
print("  JWT ACCESS TOKENS (valid ~30 min; re-run this script to refresh):\n")
print(f"  SUPERADMIN:\n  {sa_tok}\n")
print(f"  STORE ADMIN / CASHIER:\n  {ad_tok}\n")
print(f"  DEMO CUSTOMER:\n  {cu_tok}\n")
print(bar)
print("  Tip: real OTP login also works — POST /api/v1/auth/otp/request then")
print("       /api/v1/auth/otp/verify; the OTP code prints in the server console.")
print(bar)
