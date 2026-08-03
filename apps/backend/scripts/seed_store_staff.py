"""Seed Store-Admin panel staff for the dev store so you can log into the panel.

Creates (idempotently) a manager + cashier + inventory + custom staff member at
the first active store (STORE-BLR-01 from setup_local). All use OTP login with the
dev OTP 123456.

    .venv/Scripts/python.exe scripts/seed_store_staff.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from accounts.models import Role, User  # noqa: E402
from inventory.models import Warehouse  # noqa: E402
from storeops.models import StoreStaff  # noqa: E402
from storeops.permissions_catalog import default_permissions_for  # noqa: E402
from stores.models import Store  # noqa: E402

# Ensure there is a store with a warehouse.
store = Store.objects.filter(status="active").order_by("code").first()
if store is None:
    wh = Warehouse.objects.create(name="Demo Store", code="WH-STORE-DEMO", is_active=True)
    store = Store.objects.create(code="STORE-DEMO", name="VS Mart Demo", status="active",
                                 warehouse=wh, address="Demo Street", phone="0800000000")
elif store.warehouse_id is None:
    store.warehouse = Warehouse.objects.create(
        name=store.name, code=f"WH-{store.code}", is_active=True
    )
    store.save(update_fields=["warehouse"])

# Phones are stored in E.164 — the OTP flow normalizes "9100000001" → "+919100000001".
# Seeding the canonical form means the panel login (where staff type the 10-digit
# number) resolves to exactly these users.
STAFF = [
    ("+919100000001", "Ravi (Store Manager)", "manager", "Store Manager", "manager@thevsmart.com"),
    ("+919100000002", "Asha (Cashier)", "cashier", "Cashier", "cashier@thevsmart.com"),
    ("+919100000003", "Manoj (Inventory)", "inventory", "Inventory Staff", "inventory@thevsmart.com"),
    ("+919100000004", "Priya (Helper)", "custom", "Floor Assistant", "assistant@thevsmart.com"),
]

# Default password for the seeded staff so they can use the email+password web login.
# Change this in production.
STAFF_PASSWORD = "VsMart@2026"

# Clean up any rows seeded earlier with the un-normalized phone format.
_legacy = ["9100000001", "9100000002", "9100000003", "9100000004"]
_legacy_users = User.objects.filter(phone__in=_legacy)
StoreStaff.objects.filter(user__in=_legacy_users).delete()
_legacy_users.filter(role=Role.STORE_STAFF).delete()

print(f"Seeding staff for store {store.code} — {store.name}")
for phone, name, role, title, email in STAFF:
    user, _ = User.objects.get_or_create(
        phone=phone, defaults={"name": name, "role": Role.STORE_STAFF}
    )
    if user.role == Role.CUSTOMER:
        user.role = Role.STORE_STAFF
    if not user.name:
        user.name = name
    user.email = email
    # Email + password so staff can use the store-admin web login (OTP still works too).
    user.set_password(STAFF_PASSWORD)
    user.save()
    perms = [] if role == "manager" else default_permissions_for(role)
    # A small custom example: floor assistant can view orders + customers only.
    if role == "custom":
        perms = ["dashboard.view", "orders.view", "customers.view"]
    staff, created = StoreStaff.objects.get_or_create(
        user=user, defaults={
            "store": store, "staff_role": role, "permissions": perms, "title": title,
        }
    )
    if not created:
        staff.store = store
        staff.staff_role = role
        staff.permissions = perms
        staff.title = title
        staff.is_active = True
        staff.save()
    print(f"  {phone}  {role:<10} {title}  ({len(staff.effective_permissions())} perms)")

print(f"\nStore-Admin web login: email + password — password = {STAFF_PASSWORD!r}.")
print("  e.g. manager@thevsmart.com / " + STAFF_PASSWORD)
print("Phone OTP (123456) for any phone above still works as well.")
