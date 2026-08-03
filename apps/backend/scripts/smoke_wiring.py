"""Contract smoke for the app-wiring pass: asserts the (camelCased) response
fields the Flutter app now parses actually appear on the live endpoints —
referrals, family, KYC status, notification preferences (incl. new fields),
credit monthly aggregates, and coupon validation.
Run: python scripts/smoke_wiring.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

import random  # noqa: E402

from rest_framework.test import APIClient  # noqa: E402

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from offers.models import Coupon  # noqa: E402


def new_phone():
    return f"+91{random.randint(7000000000, 9999999999)}"


customer = User.objects.create_user(phone=new_phone(), name="Wire Tester")
c = APIClient()
c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(customer)['access_token']}")

Coupon.objects.get_or_create(
    code="VS100",
    defaults=dict(discount_type="flat", value=100, min_order=999, is_active=True),
)

fails = []


def data(resp):
    j = resp.json() if resp.content else {}
    return j.get("data", j)


def check(label, cond):
    print(f"# {label}: {'OK' if cond else 'FAIL'}")
    if not cond:
        fails.append(label)


# ── Referrals ──
d = data(c.get("/api/v1/referrals"))
check("GET /referrals has code/reward/referredCount",
      "code" in d and "reward" in d and "referredCount" in d)

# ── Credit family ──
d = data(c.get("/api/v1/credit/family"))
check("GET /credit/family has sharedLimit/members",
      "sharedLimit" in d and isinstance(d.get("members"), list))
d = data(c.post("/api/v1/credit/family",
                {"phone": new_phone(), "relationship": "Spouse"}, format="json"))
member_ok = len(d.get("members", [])) >= 1 and "sharedUsage" in d["members"][0]
check("POST /credit/family adds member with sharedUsage", member_ok)
if member_ok:
    mid = d["members"][0]["id"]
    r = c.delete(f"/api/v1/credit/family/members/{mid}")
    check("DELETE /credit/family/members/{id}", r.status_code == 200)

# ── KYC status ──
d = data(c.get("/api/v1/kyc/status"))
check("GET /kyc/status has status/steps",
      "status" in d and "steps" in d)

# ── Notification preferences (new fields) ──
d = data(c.get("/api/v1/notifications/preferences"))
check("GET /notifications/preferences has new fields",
      "reminderEnabled" in d and "reminderOffsetDays" in d and "categories" in d)
d = data(c.patch("/api/v1/notifications/preferences",
                 {"categories": {"orderConfirmed": False}, "reminderOffsetDays": 1},
                 format="json"))
check("PATCH /notifications/preferences persists categories + offset",
      d.get("categories", {}).get("orderConfirmed") is False
      and d.get("reminderOffsetDays") == 1)

# ── Credit dashboard monthly aggregates ──
d = data(c.get("/api/v1/credit/dashboard"))
check("GET /credit/dashboard has purchasesThisMonth/paymentsThisMonth",
      "purchasesThisMonth" in d and "paymentsThisMonth" in d)

# ── Coupon validation ──
d = data(c.post("/api/v1/coupons/validate",
                {"code": "VS100", "cart_total": 1500}, format="json"))
check("POST /coupons/validate VS100@1500 valid + discount 100",
      d.get("valid") is True and float(d.get("discount", 0)) == 100)
d = data(c.post("/api/v1/coupons/validate",
                {"code": "NOPE", "cart_total": 1500}, format="json"))
check("POST /coupons/validate invalid code -> valid false",
      d.get("valid") is False)

print()
if fails:
    print(f"WIRING SMOKE FAILED: {len(fails)} check(s) -> {fails}")
    sys.exit(1)
print("ALL WIRING CONTRACT CHECKS PASSED")
