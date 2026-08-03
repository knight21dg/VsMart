"""Phase 5 smoke — Inventory ERP (ledger) + POS billing, end-to-end with the
ledger invariant asserted throughout. Run: python scripts/smoke_pos.py

Covers: masters (brand/unit/supplier/barcode) · PO -> GRN posting -> `grn` ledger rows ·
adjustments · transfers (conservation) · damage/expiry write-offs · low-stock alerts ·
valuation · ledger audit · reconcile.  (POS section appended below.)
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
from inventory.models import InventoryLedger, StockItem, Warehouse  # noqa: E402
from inventory.services import StockCalculationService, reconcile  # noqa: E402

fails = []


def phone():
    return f"+91{random.randint(7000000000, 9999999999)}"


def cl(u):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(u)['access_token']}")
    return c


def step(label, resp, ok=(200, 201), show=None):
    good = resp.status_code in ok
    extra = ""
    data = resp.json().get("data", {}) if resp.content else {}
    if show and good and isinstance(data, dict):
        extra = "  " + " ".join(f"{k}={data.get(k)}" for k in show)
    print(f"# {label}  [{resp.status_code}] {'OK' if good else 'FAIL'}{extra}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:200]))
    return data


def check(label, cond):
    print(f"# {label}  {'OK' if cond else 'FAIL'}")
    if not cond:
        fails.append((label, "assert", b""))


admin = User.objects.create(phone=phone(), name="Inv Admin", role="admin")
adm = cl(admin)

cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
product = Product.objects.create(
    name=f"Toor Dal {random.randint(1,99999)}", brand="VS", unit="1 kg",
    price=Decimal("120.00"), mrp=Decimal("140.00"), category=cat, stock_count=None,
)

print("\n========== INVENTORY ERP ==========")

# ── 1. masters ──
wh = step("POST /inventory/warehouses", adm.post("/api/v1/inventory/warehouses", {
    "name": "Main Store", "code": f"MAIN{random.randint(1,9999)}",
    "is_default": True}, format="json"), ok=(201,), show=["id", "code"])
wh2 = step("POST /inventory/warehouses (2nd)", adm.post("/api/v1/inventory/warehouses", {
    "name": "Backroom", "code": f"BACK{random.randint(1,9999)}"}, format="json"),
    ok=(201,), show=["id"])
brand = step("POST /inventory/brands", adm.post("/api/v1/inventory/brands", {
    "name": f"VS Gold {random.randint(1,9999)}", "code": "VSG"}, format="json"),
    ok=(201,), show=["id", "name"])
unit = step("POST /inventory/units", adm.post("/api/v1/inventory/units", {
    "name": f"Kilogram {random.randint(1,9999)}", "code": f"kg{random.randint(1,999)}"},
    format="json"), ok=(201,), show=["id"])
supplier = step("POST /inventory/suppliers", adm.post("/api/v1/inventory/suppliers", {
    "name": "Metro Wholesale", "gstin": "29ABCDE1234F1Z5", "phone": "9800000000"},
    format="json"), ok=(201,), show=["id", "name"])
barcode = step("POST /inventory/barcodes", adm.post("/api/v1/inventory/barcodes", {
    "product_id": product.id, "code": f"890{random.randint(1000000000,9999999999)}",
    "symbology": "EAN13", "is_primary": True}, format="json"), ok=(201,), show=["id"])
barcode_code = barcode["code"]

# ── 2. PO -> GRN posting moves stock via the ledger ──
po = step("POST /inventory/purchase-orders", adm.post("/api/v1/inventory/purchase-orders", {
    "supplier_id": supplier["id"], "warehouse": wh["id"],
    "items": [{"product_id": product.id, "quantity": 100, "unit_cost": "100.00"}]},
    format="json"), ok=(201,), show=["id", "status", "total"])
grn = step("POST /inventory/grn (against PO, auto-post)", adm.post("/api/v1/inventory/grn", {
    "warehouse": wh["id"], "supplier_id": supplier["id"], "purchase_order_id": po["id"],
    "reference": "INV-5567",
    "items": [{"product_id": product.id, "quantity": 100, "unit_cost": "100.00",
               "batch_no": "B-2026-01", "expiry_date": "2027-01-01"}]},
    format="json"), ok=(201,), show=["id", "status", "totalCost"])
check("GRN posted", grn.get("status") == "posted")
on_hand = StockCalculationService.on_hand(product)
check("on-hand == 100 after GRN", on_hand == 100)
check("`grn` ledger row exists",
      InventoryLedger.objects.filter(product=product, type="grn").exists())
product.refresh_from_db()
check("Product.stock_count synced to 100", product.stock_count == 100)

# ── 3. adjustment (set absolute) ──
adj = step("POST /inventory/adjustments (set=90)", adm.post("/api/v1/inventory/adjustments", {
    "product_id": product.id, "warehouse": wh["id"], "set": 90,
    "reason": "cycle count"}, format="json"), ok=(201,), show=["onHand"])
check("on-hand == 90 after adjust", StockCalculationService.on_hand(product) == 90)

# ── 4. transfer conserves total ──
step("POST /inventory/transfers (30 -> backroom)", adm.post("/api/v1/inventory/transfers", {
    "product_id": product.id, "from_warehouse": wh["id"], "to_warehouse": wh2["id"],
    "quantity": 30}, format="json"), ok=(201,), show=["status"])
main_wh = Warehouse.objects.get(pk=wh["id"])
check("main on-hand == 60", StockCalculationService.on_hand(product, main_wh) == 60)
check("total on-hand conserved == 90", StockCalculationService.on_hand(product) == 90)

# ── 5. damage write-off ──
step("POST /inventory/damage (5 units)", adm.post("/api/v1/inventory/damage", {
    "product_id": product.id, "warehouse": wh["id"], "quantity": 5,
    "reason": "spillage"}, format="json"), ok=(201,), show=["type", "quantity"])
check("total on-hand == 85 after damage", StockCalculationService.on_hand(product) == 85)

# ── 6. ledger audit + reconcile invariant ──
led = step("GET /inventory/ledger?product=", adm.get(
    f"/api/v1/inventory/ledger?product={product.id}"))
check("ledger audit returns rows", isinstance(led, list) and len(led) >= 4)
truth = sum(e.quantity for e in InventoryLedger.objects.filter(product=product))
cache = sum(i.quantity for i in StockItem.objects.filter(product=product))
check(f"INVARIANT sum(ledger)={truth} == sum(cache)={cache}", truth == cache == 85)
check("reconcile finds no drift", reconcile(product=product) == [])

# ── 7. valuation + low-stock ──
val = step("GET /inventory/valuation", adm.get("/api/v1/inventory/valuation"),
           show=["total", "skuCount"])
check("valuation total > 0", Decimal(str(val.get("total", 0))) > 0)
step("GET /inventory/low-stock", adm.get("/api/v1/inventory/low-stock"))

# ──────────────────────────────────────────────────────────
print("\n========== POS BILLING ==========")
from credit.services import ensure_account  # noqa: E402

# A KYC-verified customer with credit headroom for the split-tender test.
customer = User.objects.create_user(
    phone=phone(), name="POS Cust", kyc_status="verified", credit_enabled=True
)
acc = ensure_account(customer)
acc.credit_limit = Decimal("5000.00")
acc.status = "active"
acc.save(update_fields=["credit_limit", "status"])
cust = cl(customer)
cust_phone10 = customer.phone[-10:]

# ── 8. open session (adm acts as cashier) ──
sess = step("POST /pos/session/open (float 1000)", adm.post("/api/v1/pos/session/open", {
    "warehouse": wh["id"], "opening_cash": "1000"}, format="json"), ok=(201,),
    show=["id", "status"])
step("GET /pos/session", adm.get("/api/v1/pos/session"))

# ── 9. lookups ──
scan = step("GET /pos/scan?barcode=", adm.get(f"/api/v1/pos/scan?barcode={barcode_code}"),
            show=["name", "available"])
check("scan resolves product", scan.get("productId") == str(product.id))
step("GET /pos/search?q=Toor", adm.get("/api/v1/pos/search?q=Toor"))
look = step("GET /pos/customer-lookup", adm.get(
    f"/api/v1/pos/customer-lookup?phone={cust_phone10}"),
    show=["name", "creditAvailable"])
check("customer lookup ok", look.get("customerId") == str(customer.id))

# ── 10. checkout — split tender (cash + credit), qty 2 ──
before_main = StockCalculationService.on_hand(product, main_wh)
co = step("POST /pos/checkout (cash 100 + credit 183.20)", adm.post("/api/v1/pos/checkout", {
    "customer_id": customer.id,
    "items": [{"product_id": product.id, "qty": 2}],
    "payments": [{"method": "cash", "amount": "100"},
                 {"method": "credit", "amount": "183.20"}]},
    format="json"), ok=(201,), show=["code", "total", "creditUsed", "paymentStatus"])
check("POS total == 283.20 (240 + 18% GST)", Decimal(str(co["total"])) == Decimal("283.20"))
check("creditUsed == 183.20", Decimal(str(co["creditUsed"])) == Decimal("183.20"))
check("paymentStatus == paid", co["paymentStatus"] == "paid")
acc.refresh_from_db()
check("INVARIANT credit ledger debited == billed (183.20)",
      acc.outstanding == Decimal("183.20"))
check("main stock -2 after sale",
      StockCalculationService.on_hand(product, main_wh) == before_main - 2)
check("`sale` ledger row exists",
      InventoryLedger.objects.filter(product=product, type="sale").exists())

# ── 11. return 1 unit, cash refund ──
ret = step("POST /pos/return (1 unit, cash)", adm.post("/api/v1/pos/return", {
    "original_id": co["id"], "items": [{"product_id": product.id, "qty": 1}],
    "refund_method": "cash"}, format="json"), ok=(201,),
    show=["code", "total", "paymentStatus"])
check("return total == 141.60", Decimal(str(ret["total"])) == Decimal("141.60"))
check("stock +1 after return",
      StockCalculationService.on_hand(product, main_wh) == before_main - 1)
check("`return` ledger row exists",
      InventoryLedger.objects.filter(product=product, type="return").exists())

# ── 12. cash drawer reconciliation ──
dr = step("GET /pos/cash-drawer", adm.get("/api/v1/pos/cash-drawer"),
          show=["expectedCash", "cashSales", "cashRefunds"])
check("expected cash == 958.40 (1000 + 100 - 141.60)",
      Decimal(str(dr["expectedCash"])) == Decimal("958.40"))
step("POST /pos/cash-drawer (pay_out 50)", adm.post("/api/v1/pos/cash-drawer", {
    "type": "pay_out", "amount": "50", "note": "petty cash"}, format="json"), ok=(201,))
dr2 = step("GET /pos/cash-drawer (after pay_out)", adm.get("/api/v1/pos/cash-drawer"),
           show=["expectedCash"])
check("expected cash == 908.40 after pay_out",
      Decimal(str(dr2["expectedCash"])) == Decimal("908.40"))

# ── 13. held cart (park / resume) ──
hc = step("POST /pos/cart (hold)", adm.post("/api/v1/pos/cart", {
    "label": "Mrs Rao", "items": [{"product_id": product.id, "qty": 3}]},
    format="json"), ok=(201,), show=["id", "label"])
step("GET /pos/cart (resume list)", adm.get("/api/v1/pos/cart"))
step("DELETE /pos/cart/{id}", adm.delete(f"/api/v1/pos/cart/{hc['id']}"))

step("GET /pos/transactions?mine=1", adm.get("/api/v1/pos/transactions?mine=1"))

# ── 13b. receipt payload (CGST/SGST split) ──
rcpt = step(f"GET /pos/transactions/{co['id']}/receipt",
            adm.get(f"/api/v1/pos/transactions/{co['id']}/receipt"))
tax = rcpt.get("tax", {})
check("receipt CGST + SGST == total tax",
      Decimal(str(tax.get("cgst", 0))) + Decimal(str(tax.get("sgst", 0)))
      == Decimal(str(tax.get("total", -1))))
check("receipt carries store header + items",
      bool(rcpt.get("store", {}).get("name")) and len(rcpt.get("items", [])) >= 1)

# ── 13c. void a (separate) cash sale → stock back, drawer nets to zero ──
on_hand_pre_void = StockCalculationService.on_hand(product, main_wh)
v_sale = step("POST /pos/checkout (cash, to be voided)", adm.post("/api/v1/pos/checkout", {
    "items": [{"product_id": product.id, "qty": 1}],
    "payments": [{"method": "cash", "amount": "141.60"}]}, format="json"), ok=(201,),
    show=["code"])
check("sale dropped stock by 1",
      StockCalculationService.on_hand(product, main_wh) == on_hand_pre_void - 1)
voided = step(f"POST /pos/transactions/{v_sale['id']}/void",
              adm.post(f"/api/v1/pos/transactions/{v_sale['id']}/void",
                       {"reason": "wrong item"}, format="json"),
              show=["isVoided", "paymentStatus"])
check("void flag set", voided.get("isVoided") is True)
check("void returned the stock (net zero)",
      StockCalculationService.on_hand(product, main_wh) == on_hand_pre_void)

# ── 13d. per-line discount applies ──
disc = step("POST /pos/checkout (line discount 20)", adm.post("/api/v1/pos/checkout", {
    "items": [{"product_id": product.id, "qty": 1, "discount": "20"}],
    "payments": [{"method": "cash", "amount": "118.00"}]}, format="json"), ok=(201,),
    show=["subtotal", "total"])
check("line discount reflected (subtotal 100)",
      Decimal(str(disc.get("subtotal"))) == Decimal("100.00"))

# ── 13e. events feed + reports + reorder-level ──
ev = step("GET /pos/events", adm.get("/api/v1/pos/events"))
check("events feed has sale/stock events", len(ev.get("events", [])) >= 1)
step("GET /pos/reports/sales-by-cashier", adm.get("/api/v1/pos/reports/sales-by-cashier"))
step("GET /pos/reports/fast-movers", adm.get("/api/v1/pos/reports/fast-movers"))
step("GET /pos/reports/expiry", adm.get("/api/v1/pos/reports/expiry"))
rl = step("POST /inventory/reorder-level (threshold 5)", adm.post(
    "/api/v1/inventory/reorder-level",
    {"product": product.id, "warehouse": wh["id"], "threshold": 5}, format="json"),
    show=["lowStockThreshold"])
check("reorder level set to 5", rl.get("lowStockThreshold") == 5)

# ── 14. day closing — count the actual expected cash → zero variance ──
dr_final = step("GET /pos/cash-drawer (pre-close)",
                adm.get("/api/v1/pos/cash-drawer"), show=["expectedCash"])
expected = str(dr_final["expectedCash"])
close = step("POST /pos/session/close (counted = expected)", adm.post(
    "/api/v1/pos/session/close", {"counted_cash": expected, "notes": "eod"},
    format="json"), ok=(201,),
    show=["expectedCash", "countedCash", "variance", "totalSales", "creditSales"])
check("INVARIANT day-closing variance == 0", Decimal(str(close["variance"])) == Decimal("0"))
check("day-closing records credit tender",
      Decimal(str(close.get("creditSales", -1))) == Decimal("183.20"))

# ──────────────────────────────────────────────────────────
print("\n========== ONLINE ORDER: RESERVE -> FULFIL -> LEDGER ==========")
from orders.models import Order as OrderModel  # noqa: E402
from orders.services import fulfil_order  # noqa: E402

before_avail = StockCalculationService.available(product)
before_on_hand = StockCalculationService.on_hand(product)
addr = step("POST /addresses", cust.post("/api/v1/addresses", {
    "name": "POS Cust", "phone": "9800000001", "line1": "5 Market Rd",
    "pincode": "560001", "is_default": True}, format="json"), ok=(201,))
cust.post("/api/v1/cart/items", {"product_id": product.id, "quantity": 1}, format="json")
# idempotency: same key twice → one order
hdr = {"HTTP_IDEMPOTENCY_KEY": "smoke-key-001"}
order = step("POST /checkout (COD, Idempotency-Key)", cust.post("/api/v1/checkout", {
    "address_id": addr["id"], "payment_method": "cod"}, format="json", **hdr), ok=(201,),
    show=["total"])
cust.post("/api/v1/cart/items", {"product_id": product.id, "quantity": 1}, format="json")
step("POST /checkout (same key -> idempotent)", cust.post("/api/v1/checkout", {
    "address_id": addr["id"], "payment_method": "cod"}, format="json", **hdr), ok=(201,))
check("idempotent: only ONE order for the key",
      OrderModel.objects.filter(user=customer, idempotency_key="smoke-key-001").count() == 1)
check("checkout RESERVES (available -1, on-hand unchanged)",
      StockCalculationService.available(product) == before_avail - 1
      and StockCalculationService.on_hand(product) == before_on_hand)
order_obj = OrderModel.objects.filter(user=customer).latest("placed_at")
check("order stock_state == reserved", order_obj.stock_state == "reserved")

# deliver → fulfilment posts the `order` ledger movement
fulfil_order(order_obj)
order_obj.refresh_from_db()
check("`order` ledger row exists after delivery",
      InventoryLedger.objects.filter(product=product, type="order").exists())
check("on-hand -1 after fulfilment",
      StockCalculationService.on_hand(product) == before_on_hand - 1)
check("order stock_state == fulfilled", order_obj.stock_state == "fulfilled")

# final ledger == cache invariant across all warehouses for the product
truth = sum(e.quantity for e in InventoryLedger.objects.filter(product=product))
cache = sum(i.quantity for i in StockItem.objects.filter(product=product))
check(f"FINAL INVARIANT sum(ledger)={truth} == sum(cache)={cache}", truth == cache)
check("reconcile still clean", reconcile(product=product) == [])

print("\n" + ("ALL PHASE 5 (INVENTORY + POS) CHECKS PASSED"
              if not fails else f"FAILURES: {fails}"))
if fails:
    sys.exit(1)
