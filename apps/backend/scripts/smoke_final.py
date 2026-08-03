"""Smoke for the final batch: system endpoints, agents, cash collections, reports
(+ CSV/Excel/PDF export), audit log. Run: python scripts/smoke_final.py
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from django.core.files.uploadedfile import SimpleUploadedFile  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from accounts.models import User  # noqa: E402
from accounts.services import issue_tokens  # noqa: E402
from payments.models import CashCollection  # noqa: E402


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
pub = APIClient()
fails = []


def step(label, resp, ok=(200, 201)):
    good = resp.status_code in ok
    print(f"# {label}  [{resp.status_code}] {'OK' if good else 'FAIL'}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:160]))
    return resp


# ── system ──
step("GET /version (public)", pub.get("/api/v1/version"))
step("GET /app-config (public)", pub.get("/api/v1/app-config"))
step("GET /maintenance-status (public)", pub.get("/api/v1/maintenance-status"))
step("GET /feature-flags", cu.get("/api/v1/feature-flags"))
step("POST /uploads", cu.post("/api/v1/uploads",
     {"file": SimpleUploadedFile("x.jpg", b"data", content_type="image/jpeg")},
     format="multipart"))
step("GET /search/global", cu.get("/api/v1/search/global?q=a"))
step("POST /feedback", cu.post("/api/v1/feedback", {"message": "Great app", "rating": 5}, format="json"))

# ── agents ──
step("GET /agents/me", ag.get("/api/v1/agents/me"))
step("GET /agents/performance", ag.get("/api/v1/agents/performance"))
step("GET /agents/earnings", ag.get("/api/v1/agents/earnings"))
step("GET /agents/incentives", ag.get("/api/v1/agents/incentives"))

# ── cash collections ──
cc = CashCollection.objects.create(user=customer, amount=200, status="requested")
step("GET /collections/pending (customer)", cu.get("/api/v1/collections/pending"))
step("GET /collections/assigned (agent)", ag.get("/api/v1/collections/assigned"))
otp_resp = step("POST /collections/{id}/otp (agent)",
                ag.post(f"/api/v1/collections/{cc.id}/otp", {}, format="json"))
otp = otp_resp.json()["data"]["otp"]
step("POST /collections/{id}/collect (with otp)",
     ag.post(f"/api/v1/collections/{cc.id}/collect", {"otp": otp}, format="json"))
cc.refresh_from_db()
assert cc.status == "collected", "collection not finalized"
step("GET /collections/history (customer)", cu.get("/api/v1/collections/history"))
step("GET /collections/receipts (customer)", cu.get("/api/v1/collections/receipts"))

# ── reports ──
rep = step("GET /reports/sales (json)", ad.get("/api/v1/reports/sales"))
assert "columns" in rep.json()["data"]
for fmt, ctype in [("csv", "text/csv"),
                   ("excel", "spreadsheet"),
                   ("pdf", "application/pdf")]:
    r = ad.get(f"/api/v1/reports/export?type=credit&fmt={fmt}")
    ok = r.status_code == 200 and ctype.split("/")[0] in r["Content-Type"]
    print(f"# GET /reports/export?format={fmt}  [{r.status_code}] "
          f"{'OK' if ok else 'FAIL'} ({r['Content-Type'][:40]}, {len(r.content)}b)")
    if not ok:
        fails.append((f"export {fmt}", r.status_code, b""))

# ── audit ──
step("GET /audit/logs (admin)", ad.get("/api/v1/audit/logs"))
# rbac: customer blocked from reports + audit
for path in ["/api/v1/reports/sales", "/api/v1/audit/logs", "/api/v1/agents/me"]:
    r = cu.get(path)
    print(f"# customer blocked from {path}  [{r.status_code}] "
          f"{'OK' if r.status_code == 403 else 'FAIL'}")
    if r.status_code != 403:
        fails.append(("rbac " + path, r.status_code, b""))

print("\n" + ("ALL FINAL CHECKS PASSED" if not fails else f"FAILURES: {fails}"))
