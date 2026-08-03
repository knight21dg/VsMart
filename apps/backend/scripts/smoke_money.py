"""End-to-end money-flow smoke test: address -> cart -> COD order -> credit order
(ledger debit) -> repayment via webhook -> cash collection -> ledger invariant.
Run: python scripts/smoke_money.py
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

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from catalog.models import Category, Product  # noqa: E402
from credit.services import ensure_account, reconcile  # noqa: E402
from payments.models import Payment  # noqa: E402


def new_phone():
    # Unique each run — users with orders/payments can't be hard-deleted (PROTECT),
    # which is intended, so we just create fresh test users.
    return f"+91{random.randint(7000000000, 9999999999)}"


customer = User.objects.create_user(phone=new_phone(), name="Money Tester")
agent = User.objects.create(phone=new_phone(), name="Field Agent", role="agent")

# Ensure a product exists. Plain (no-variant) on purpose — a variant SKU needs
# its stock movement scoped to one pack, which this money-flow smoke doesn't
# exercise.
if not Product.objects.filter(variants__isnull=True).exists():
    cat = Category.objects.create(name="Groceries", slug="groceries")
    Product.objects.create(name="Apple", brand="Groceries", unit="1 kg", price=165,
                           mrp=189, category=cat, stock_count=50)
product = Product.objects.filter(in_stock=True, variants__isnull=True).first()

# This COD order checks out without a serving zone → it reserves from the DEFAULT
# warehouse. Other smokes can leave products that are globally `in_stock` but whose stock
# lives only in a store warehouse, so guarantee on-hand in the default warehouse here.
from inventory.models import InventoryLedger  # noqa: E402
from inventory.services import (  # noqa: E402
    InventoryService, StockCalculationService, default_warehouse,
)

_wh = default_warehouse()
if StockCalculationService.available(product, _wh) < 5:
    InventoryService.post_movement(
        product=product, warehouse=_wh, type=InventoryLedger.Type.GRN, quantity=50,
        unit_cost=product.price, ref_type="smoke", note="smoke_money default-wh top-up",
    )

c = APIClient()
c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(customer)['access_token']}")


def step(label, resp, expect=None):
    ok = resp.status_code < 400
    print(f"# {label}  [{resp.status_code}] {'OK' if ok else 'FAIL'}")
    assert ok, resp.content
    if expect:
        expect(resp.json()["data"])
    return resp.json().get("data")


# 1. address
addr = step("POST /addresses", c.post("/api/v1/addresses", {
    "name": "Money Tester", "phone": "9800000001", "line1": "12 Test St",
    "area": "Sector 1", "city": "Bengaluru", "pincode": "560001", "isDefault": True,
}, format="json"))

# 2. add to cart + bill
step("POST /cart/items", c.post("/api/v1/cart/items",
     {"productId": product.id, "quantity": 2}, format="json"))
cart = step("GET /cart", c.get("/api/v1/cart"),
            lambda d: print(f"   bill: subtotal={d['bill']['subtotal']} gst={d['bill']['gst']} "
                            f"delivery={d['bill']['deliveryFee']} total={d['bill']['total']}"))

# 3. COD checkout
order = step("POST /checkout (cod)", c.post("/api/v1/checkout",
             {"addressId": addr["id"], "paymentMethod": "cod"}, format="json"),
             lambda d: print(f"   order {d['id']} status={d['status']} total={d['total']}"))
step("GET /orders", c.get("/api/v1/orders"))

# 4. credit checkout  (credit requires a completed KYC)
customer.kyc_status = "verified"
customer.credit_enabled = True
customer.save(update_fields=["kyc_status", "credit_enabled"])
ensure_account(customer, default_limit=Decimal("10000"))
c.post("/api/v1/cart/items", {"productId": product.id, "quantity": 1}, format="json")
corder = step("POST /checkout (credit)", c.post("/api/v1/checkout",
              {"addressId": addr["id"], "paymentMethod": "credit"}, format="json"))
dash = step("GET /credit/dashboard", c.get("/api/v1/credit/dashboard"),
            lambda d: print(f"   outstanding={d['outstanding']} available={d['available']}"))
assert Decimal(str(dash["outstanding"])) > 0, "credit purchase did not debit ledger"

# 5. repay -> webhook finalize
repay = step("POST /credit/repay", c.post("/api/v1/credit/repay",
             {"amount": "100.00", "method": "upi"}, format="json"))
pay = Payment.objects.get(pk=repay["id"])
pub = APIClient()
step("POST /webhooks/razorpay", pub.post("/api/v1/webhooks/razorpay", {
    "event_id": f"evt_{pay.id}", "gateway_order_id": pay.gateway_order_id,
    "status": "success", "gateway_payment_id": f"pay_{pay.id}",
}, format="json"))
dash2 = step("GET /credit/dashboard (after repay)", c.get("/api/v1/credit/dashboard"),
             lambda d: print(f"   outstanding={d['outstanding']}"))
assert Decimal(str(dash2["outstanding"])) == Decimal(str(dash["outstanding"])) - Decimal("100"), \
    "repayment not reflected"

# 6. cash collection -> agent collects via the REAL state-machine + OTP path
# (cashcollections.services), the same one the app's own "collections/<id>/collect"
# endpoint uses — not the old direct-collect shortcut, which was removed for
# skipping OTP entirely.
from cashcollections import services as coll_services  # noqa: E402
from payments.models import CashCollection  # noqa: E402

cc = step("POST /credit/cash-collection", c.post("/api/v1/credit/cash-collection",
          {"amount": "50.00"}, format="json"))
coll = CashCollection.objects.get(pk=cc["id"])
coll_services.manual_assign(coll, agent, by=agent)
coll_services.accept(coll, agent)
coll_services.en_route(coll, agent)
coll_services.reach(coll, agent)
coll_services.request_collection_otp(coll, agent, coll.amount)
otp_code = coll.collection_otp.code
coll_services.verify_otp(coll, agent, otp_code)
coll_services.collect(coll, agent)
coll.refresh_from_db()
assert coll.status == CashCollection.Status.COLLECTED, coll.status
print(f"# cash collection settled via OTP-gated flow  [{coll.status}] OK")
dash3 = step("GET /credit/dashboard (after cash)", c.get("/api/v1/credit/dashboard"),
             lambda d: print(f"   outstanding={d['outstanding']}"))

# 7. ledger invariant
account = ensure_account(customer)
recon = reconcile(account)
print(f"\n# ledger invariant: outstanding={account.outstanding} == SUM(ledger)={recon}")
assert account.outstanding == recon

print("\nMONEY-FLOW SMOKE PASSED")
