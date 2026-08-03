"""Smoke test for the remaining modules: KYC review workflow (agent + admin →
credit enabled), offers, coupons, notifications, support, referrals, ops.
Run: python scripts/smoke_full.py
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
from notifications.models import Notification  # noqa: E402
from offers.models import Coupon, Offer  # noqa: E402
from support.models import Faq  # noqa: E402


def new_phone():
    return f"+91{random.randint(7000000000, 9999999999)}"


customer = User.objects.create_user(phone=new_phone(), name="Cust One")
referee = User.objects.create_user(phone=new_phone(), name="Cust Two")
agent = User.objects.create(phone=new_phone(), name="Agent", role="agent")
superadmin = User.objects.create(phone=new_phone(), name="Boss", role="superadmin")


def client(u):
    c = APIClient()
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {issue_tokens(u)['access_token']}")
    return c


cust, ag, boss, ref = client(customer), client(agent), client(superadmin), client(referee)
fails = []


def step(label, resp, ok_codes=(200, 201)):
    ok = resp.status_code in ok_codes
    print(f"# {label}  [{resp.status_code}] {'OK' if ok else 'FAIL'}")
    if not ok:
        fails.append((label, resp.status_code, resp.content[:200]))
    return resp.json() if resp.content else {}


# ── KYC: submit → agent review → admin approve → credit enabled ──
step("GET /kyc/status", cust.get("/api/v1/kyc/status"))
step("POST /kyc/submit", cust.post("/api/v1/kyc/submit", {
    "documents": [{"type": "aadhaar", "number_masked": "XXXX1234"},
                  {"type": "pan", "number_masked": "XXXXX567Y"}]}, format="json"))
queue = step("GET /agent/kyc/queue", ag.get("/api/v1/agent/kyc/queue"))
app_pk = customer.kyc_application.pk
step("POST /agent/kyc/{id}/review", ag.post(
    f"/api/v1/agent/kyc/{app_pk}/review", {"step": "aadhaar", "decision": "approve"}, format="json"))
step("POST /admin/kyc/{id}/decision (approve)", boss.post(
    f"/api/v1/admin/kyc/{app_pk}/decision", {"decision": "approve"}, format="json"))
me = step("GET /users/me (kyc verified?)", cust.get("/api/v1/users/me"))
assert me["data"]["kyc_status"] == "verified", "KYC approval did not verify user"
# KYC verifies IDENTITY only — it must not grant credit. The line is opened by an
# approved CreditApplication carrying an explicit limit (see credit.services).
assert me["data"]["credit_enabled"] is False, "KYC approval must not enable credit"

# ── Credit application: apply -> admin approves with a limit -> line is live ──
step("POST /credit/apply", cust.post("/api/v1/credit/apply", {
    "occupation": "Teacher", "monthlyIncome": "25000", "familyMembers": 4,
    "houseType": "apartment", "ownership": "rented", "requestedLimit": "5000",
}, format="json"))
queue = step("GET /admin/credit/applications",
             boss.get("/api/v1/admin/credit/applications?status=pending"))
rows = queue["data"]["results"] if isinstance(queue["data"], dict) else queue["data"]
assert rows, "credit application did not reach the review queue"
step("POST /admin/credit/applications/{id}/decision (approve)", boss.post(
    f"/api/v1/admin/credit/applications/{rows[0]['id']}/decision",
    {"decision": "approve", "approvedLimit": "3000"}, format="json"))
me = step("GET /users/me (credit enabled?)", cust.get("/api/v1/users/me"))
assert me["data"]["credit_enabled"] is True, "credit not enabled after approval"

# ── Offers + coupons ──
if not Offer.objects.filter(title="Deal of day").exists():
    Offer.objects.create(type="deal", title="Deal of day", deal_price=99,
                         original_price=150, discount_percent=34, is_active=True)
Coupon.objects.get_or_create(code="VS100", defaults=dict(
    discount_type="flat", value=100, min_order=999, is_active=True))
offers = step("GET /offers (public)", APIClient().get("/api/v1/offers"))
assert len(offers["data"]) >= 1
v1 = step("POST /coupons/validate (eligible)", cust.post(
    "/api/v1/coupons/validate", {"code": "VS100", "cart_total": 1500}, format="json"))
assert v1["data"]["valid"] is True and float(v1["data"]["discount"]) == 100
v2 = step("POST /coupons/validate (below min)", cust.post(
    "/api/v1/coupons/validate", {"code": "VS100", "cart_total": 500}, format="json"))
assert v2["data"]["valid"] is False

# ── Notifications ──
Notification.objects.create(user=customer, type="order", title="Order placed", body="Thanks!")
notifs = step("GET /notifications", cust.get("/api/v1/notifications"))
nid = notifs["data"][0]["id"] if isinstance(notifs["data"], list) else notifs["data"][0]["id"]
step("POST /notifications/{id}/read", cust.post(f"/api/v1/notifications/{nid}/read", {}, format="json"))
step("GET /notifications/preferences", cust.get("/api/v1/notifications/preferences"))

# ── Support ──
if not Faq.objects.filter(question="How to track?").exists():
    Faq.objects.create(category="Orders", question="How to track?",
                       answer="Open the order.", is_active=True)
step("GET /support/faqs (public)", APIClient().get("/api/v1/support/faqs"))
ticket = step("POST /support/tickets", cust.post("/api/v1/support/tickets",
              {"category": "Orders", "subject": "Where is my order?"}, format="json"))
code = ticket["data"]["id"]
step("GET /support/tickets", cust.get("/api/v1/support/tickets"))
step("POST /support/tickets/{code}/messages", cust.post(
    f"/api/v1/support/tickets/{code}/messages", {"body": "Any update?"}, format="json"))

# ── Referrals ──
mine = step("GET /referrals", cust.get("/api/v1/referrals"))
my_code = mine["data"]["code"]
step("POST /referrals/apply", ref.post("/api/v1/referrals/apply", {"code": my_code}, format="json"))

# ── Ops (admin/superadmin) ──
step("GET /admin/dashboard", boss.get("/api/v1/admin/dashboard"))
step("GET /admin/customers", boss.get("/api/v1/admin/customers"))
step("GET /admin/staff", boss.get("/api/v1/admin/staff"))
step("POST /admin/staff (create agent)", boss.post("/api/v1/admin/staff",
     {"phone": new_phone(), "name": "New Agent", "role": "agent"}, format="json"))
# permission: customer must NOT reach staff
denied = cust.get("/api/v1/admin/staff")
print(f"# customer blocked from /admin/staff  [{denied.status_code}] "
      f"{'OK' if denied.status_code == 403 else 'FAIL'}")
if denied.status_code != 403:
    fails.append(("rbac /admin/staff", denied.status_code, b""))

print("\n" + ("ALL FULL SMOKE CHECKS PASSED" if not fails else f"FAILURES: {fails}"))
