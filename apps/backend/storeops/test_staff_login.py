"""A staff member added through the store panel must actually be able to sign in.

`create_staff` used to build a phone-only `User` with no email and no password,
while the panel authenticates with email + password. The row appeared, the toast
said "Staff added", and the person could never log in — with no error anywhere to
explain why.
"""
from django.test import TestCase
from rest_framework.exceptions import ValidationError
from rest_framework.test import APIClient

from accounts.models import Role, User
from inventory.models import Warehouse
from storeops.models import StoreStaff
from storeops.staff_service import create_staff, update_staff
from stores.models import Store

LOGIN = "/api/v1/auth/login"


def _store(code="ST-SL"):
    wh = Warehouse.objects.create(name="WH", code=f"WH-{code}")
    return Store.objects.create(code=code, name="Login Store", status="active", warehouse=wh)


class StaffLoginTests(TestCase):
    def setUp(self):
        self.store = _store()

    def test_created_staff_can_actually_sign_in(self):
        create_staff(
            self.store, phone="+919770000101", name="Cashier One",
            staff_role="cashier", email="cashier1@vsmart.test", password="s3cret-pass",
        )
        r = APIClient().post(
            LOGIN, {"email": "cashier1@vsmart.test", "password": "s3cret-pass"},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.data)

    def test_creating_staff_without_credentials_is_rejected(self):
        """Better a clear error than a staff row nobody can use."""
        with self.assertRaises(ValidationError):
            create_staff(self.store, phone="+919770000102", name="No Creds",
                         staff_role="cashier")
        self.assertFalse(StoreStaff.objects.filter(store=self.store).exists())

    def test_a_short_password_is_rejected(self):
        with self.assertRaises(ValidationError):
            create_staff(self.store, phone="+919770000103", name="Weak",
                         staff_role="cashier", email="weak@vsmart.test", password="short")

    def test_an_email_belonging_to_someone_else_is_rejected(self):
        create_staff(self.store, phone="+919770000104", name="First",
                     staff_role="cashier", email="dup@vsmart.test", password="s3cret-pass")
        with self.assertRaises(ValidationError):
            create_staff(self.store, phone="+919770000105", name="Second",
                         staff_role="cashier", email="dup@vsmart.test", password="s3cret-pass")

    def test_adopting_an_existing_customer_gives_them_credentials(self):
        User.objects.create(phone="+919770000106", name="Walk In", role=Role.CUSTOMER)
        create_staff(self.store, phone="+919770000106", name="Walk In",
                     staff_role="cashier", email="adopted@vsmart.test",
                     password="s3cret-pass")
        r = APIClient().post(
            LOGIN, {"email": "adopted@vsmart.test", "password": "s3cret-pass"},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.data)

    def test_renaming_a_staff_member_actually_renames_them(self):
        staff = create_staff(
            self.store, phone="+919770000107", name="Old Name", staff_role="cashier",
            email="rename@vsmart.test", password="s3cret-pass",
        )
        update_staff(staff, name="New Name")
        staff.user.refresh_from_db()
        self.assertEqual(staff.user.name, "New Name")
