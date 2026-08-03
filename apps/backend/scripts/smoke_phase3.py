"""Smoke for Phase 3 customer modules: content (CMS), reviews, returns, loyalty.
Run: python scripts/smoke_phase3.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

import random  # noqa: E402
from decimal import Decimal  # noqa: E402

from django.core.management import call_command  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from catalog.models import Product  # noqa: E402
from orders.models import Order  # noqa: E402


def new_phone():
    return f"+91{random.randint(7000000000, 9999999999)}"


customer = User.objects.create_user(phone=new_phone(), name="P3 Tester")
c = APIClient()
c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(customer)['access_token']}")
pub = APIClient()
fails = []


def data(r):
    j = r.json() if r.content else {}
    return j.get("data", j)


def check(label, cond):
    print(f"# {label}: {'OK' if cond else 'FAIL'}")
    if not cond:
        fails.append(label)


# ── content / CMS ──
call_command("seed_content")
pages = data(pub.get("/api/v1/content/pages"))
check("GET /content/pages (public)", isinstance(pages, list) and len(pages) >= 5)
about = data(pub.get("/api/v1/content/pages/about"))
check("GET /content/pages/about", about.get("slug") == "about" and bool(about.get("body")))

# ── reviews ──
prod = Product.objects.filter(is_active=True).first()
check("product exists for reviews", prod is not None)
pid = prod.pk
r = c.post(f"/api/v1/products/{pid}/reviews",
           {"rating": 5, "title": "Great", "body": "Fresh!"}, format="json")
check("POST product review", r.status_code in (200, 201))
rev = data(pub.get(f"/api/v1/products/{pid}/reviews"))
check("GET product reviews + summary",
      isinstance(rev.get("reviews"), list) and rev.get("summary", {}).get("count", 0) >= 1)
mine = data(c.get("/api/v1/reviews/mine"))
check("GET /reviews/mine", isinstance(mine, list) and len(mine) >= 1)
prod.refresh_from_db()
check("product rating/review_count cache updated",
      prod.review_count >= 1 and float(prod.rating) > 0)

# (subscriptions removed — the feature was never finished; see
#  subscriptions/migrations/0002_delete_subscription.py)

# ── loyalty ──
dash = data(c.get("/api/v1/loyalty"))
check("GET /loyalty initial (0 / Bronze)",
      dash.get("balance") == 0 and dash.get("tier") == "Bronze")
red = c.post("/api/v1/loyalty/redeem", {"points": 100}, format="json")
check("redeem insufficient -> 400", red.status_code == 400)
from loyalty.services import post as loyalty_post  # noqa: E402

loyalty_post(customer, "earn", 500, note="test")
dash2 = data(c.get("/api/v1/loyalty"))
check("loyalty balance after earn = 500", dash2.get("balance") == 500)
red2 = c.post("/api/v1/loyalty/redeem", {"points": 100}, format="json")
check("redeem 100 -> balance 400", data(red2).get("balance") == 400)
ledger = data(c.get("/api/v1/loyalty/ledger"))
check("loyalty ledger has entries", isinstance(ledger, list) and len(ledger) >= 2)

# ── returns ──
delivered = Order.objects.create(
    user=customer, payment_method="cod", status="delivered",
    total=Decimal("500"), subtotal=Decimal("500"))
rr = c.post(f"/api/v1/orders/{delivered.code}/returns",
            {"reason": "Damaged", "description": "Crushed box"}, format="json")
check("POST return on delivered order", rr.status_code in (200, 201))
rlist = data(c.get("/api/v1/returns"))
check("GET /returns", isinstance(rlist, list) and len(rlist) >= 1)
pending = Order.objects.create(
    user=customer, payment_method="cod", status="pending", total=Decimal("200"))
rr2 = c.post(f"/api/v1/orders/{pending.code}/returns",
             {"reason": "x"}, format="json")
check("return on non-delivered -> 400", rr2.status_code == 400)

print()
if fails:
    print(f"PHASE 3 SMOKE FAILED: {fails}")
    sys.exit(1)
print("ALL PHASE 3 SMOKE CHECKS PASSED")
