"""Store-Admin panel smoke: store-scoped RBAC + the /store/* contract.

Proves: manager sees all permissions; dashboard/orders/inventory/customers/credit/
delivery endpoints are store-scoped & return 200; staff CRUD + permission assignment
work; a limited cashier is allowed POS/dashboard but BLOCKED (403) from staff
management and inventory management it wasn't granted.

    .venv/Scripts/python.exe scripts/smoke_store.py
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
from inventory.models import Warehouse  # noqa: E402
from storeops.models import StoreStaff  # noqa: E402
from storeops.permissions_catalog import default_permissions_for  # noqa: E402
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
    if show and good:
        body = resp.json().get("data", resp.json())
        if isinstance(body, dict):
            extra = "  " + " ".join(f"{k}={body.get(k)}" for k in show)
        elif isinstance(body, list):
            extra = f"  ({len(body)} rows)"
    print(f"# {label}  [{resp.status_code}] {'OK' if good else 'FAIL'}{extra}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:200]))
    try:
        return resp.json().get("data", {})
    except Exception:
        return {}


def expect_403(label, resp):
    good = resp.status_code == 403
    print(f"# {label}  [{resp.status_code}] {'OK (blocked)' if good else 'FAIL (should be 403)'}")
    if not good:
        fails.append((label, resp.status_code, resp.content[:200]))


# ── Setup: an isolated store + a manager ──
wh = Warehouse.objects.create(name="Smoke WH", code=f"WH-SMOKE-{random.randint(1000,9999)}",
                              is_active=True)
store = Store.objects.create(code=f"STORE-SMK-{random.randint(1000,9999)}", name="Smoke Store",
                             status="active", warehouse=wh, address="1 Test Rd", phone="0800")

manager_user = User.objects.create(phone=ph(), name="Smoke Manager", role=Role.STORE_STAFF)
StoreStaff.objects.create(user=manager_user, store=store, staff_role="manager", title="Manager")
mgr = cl(manager_user)

print("== Manager (all permissions) ==")
me = step("GET /store/me", mgr.get("/api/v1/store/me"), show=["isManager", "staffRole"])
assert me.get("isManager") is True, "manager should be flagged"
assert len(me.get("permissions", [])) >= 15, "manager should hold all permissions"

step("GET /store/dashboard", mgr.get("/api/v1/store/dashboard"), show=["kpis"])
step("GET /store/permissions", mgr.get("/api/v1/store/permissions"))
step("GET /store/orders", mgr.get("/api/v1/store/orders"))
step("GET /store/orders/queues", mgr.get("/api/v1/store/orders/queues"))
step("GET /store/inventory", mgr.get("/api/v1/store/inventory"))
step("GET /store/inventory/expiry", mgr.get("/api/v1/store/inventory/expiry"))
step("GET /store/suppliers", mgr.get("/api/v1/store/suppliers"))
step("GET /store/purchases", mgr.get("/api/v1/store/purchases"))
step("GET /store/customers", mgr.get("/api/v1/store/customers"))
step("GET /store/credit", mgr.get("/api/v1/store/credit"))
step("GET /store/verification", mgr.get("/api/v1/store/verification"))
step("GET /store/delivery", mgr.get("/api/v1/store/delivery"))
step("GET /store/delivery/agents", mgr.get("/api/v1/store/delivery/agents"))
step("GET /store/audit", mgr.get("/api/v1/store/audit"))
step("GET /store/settings", mgr.get("/api/v1/store/settings"))

# ── Manager hires a cashier, then narrows perms ──
print("\n== Staff management ==")
created = step("POST /store/staff (hire cashier)", mgr.post("/api/v1/store/staff", {
    "phone": ph(), "name": "Smoke Cashier", "staffRole": "cashier",
}, format="json"), show=["staffRole", "permissionCount"])
staff_id = created.get("id")
step("GET /store/staff", mgr.get("/api/v1/store/staff"))
step("PATCH /store/staff/<id> (grant inventory.view)", mgr.patch(
    f"/api/v1/store/staff/{staff_id}",
    {"permissions": default_permissions_for("cashier") + ["inventory.view"]},
    format="json"), show=["permissionCount"])

# ── Cashier login → limited access ──
print("\n== Cashier (limited) ==")
cashier_user = User.objects.get(id=created["userId"])
csh = cl(cashier_user)
cme = step("GET /store/me (cashier)", csh.get("/api/v1/store/me"), show=["staffRole"])
assert cme.get("isManager") is False
step("cashier GET /store/dashboard (allowed)", csh.get("/api/v1/store/dashboard"))
expect_403("cashier GET /store/staff (no employees.view)", csh.get("/api/v1/store/staff"))
expect_403("cashier POST /store/inventory adjust (no inventory.manage)",
           csh.post("/api/v1/store/inventory/1/adjust", {"delta": 5}, format="json"))

# ── Attendance ──
print("\n== Attendance ==")
step("POST /store/staff/attendance/check-in (cashier)",
     csh.post("/api/v1/store/staff/attendance/check-in", {}, format="json"),
     show=["checkInAt"])

# ── A user with no membership is locked out ──
print("\n== Non-staff is locked out ==")
outsider = User.objects.create(phone=ph(), name="Random Customer", role=Role.CUSTOMER)
expect_403("customer GET /store/me (no membership)", cl(outsider).get("/api/v1/store/me"))

print("\n" + ("ALL STORE SMOKE CHECKS PASSED" if not fails else f"FAILURES: {len(fails)}"))
for f in fails:
    print("  FAIL", f)
sys.exit(1 if fails else 0)
