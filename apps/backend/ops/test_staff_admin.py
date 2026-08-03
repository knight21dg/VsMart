"""Staff administration must not be able to lock everyone out of the console.

`PATCH /admin/staff/<pk>` accepted any role change and any `is_active` value with
no guards, so a super-admin could deactivate or demote their own account — or the
last remaining super-admin — and leave nobody able to administer the platform.
"""
from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User


def _client(user):
    c = APIClient()
    c.force_authenticate(user)
    return c


class StaffAdminGuardTests(TestCase):
    def setUp(self):
        self.root = User.objects.create(
            phone="+919820000001", name="Root", role=Role.SUPERADMIN)
        self.client_root = _client(self.root)

    def _other_super(self):
        return User.objects.create(
            phone="+919820000002", name="Second", role=Role.SUPERADMIN)

    def test_cannot_deactivate_own_account(self):
        r = self.client_root.patch(
            f"/api/v1/admin/staff/{self.root.id}", {"is_active": False}, format="json")
        self.assertEqual(r.status_code, 400)
        self.root.refresh_from_db()
        self.assertTrue(self.root.is_active)

    def test_cannot_demote_own_account(self):
        r = self.client_root.patch(
            f"/api/v1/admin/staff/{self.root.id}", {"role": Role.ADMIN}, format="json")
        self.assertEqual(r.status_code, 400)
        self.root.refresh_from_db()
        self.assertEqual(self.root.role, Role.SUPERADMIN)

    def test_cannot_remove_the_last_active_superadmin(self):
        other = self._other_super()
        # `other` is not the actor, but they are the only OTHER super-admin, so
        # deactivating them is allowed while root remains.
        r = _client(other).patch(
            f"/api/v1/admin/staff/{self.root.id}", {"is_active": False}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        # Now `other` is the last one standing and cannot be removed.
        self.root.refresh_from_db()
        self.assertFalse(self.root.is_active)
        r2 = _client(other).patch(
            f"/api/v1/admin/staff/{other.id}", {"is_active": False}, format="json")
        self.assertEqual(r2.status_code, 400)

    def test_can_deactivate_a_different_admin(self):
        admin = User.objects.create(
            phone="+919820000003", name="Ops", role=Role.ADMIN)
        r = self.client_root.patch(
            f"/api/v1/admin/staff/{admin.id}", {"is_active": False}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        admin.refresh_from_db()
        self.assertFalse(admin.is_active)

    def test_creating_staff_without_a_phone_is_a_400_not_a_500(self):
        r = self.client_root.post(
            "/api/v1/admin/staff", {"role": Role.ADMIN, "name": "No Phone"},
            format="json")
        self.assertEqual(r.status_code, 400)

    def test_duplicate_phone_is_rejected(self):
        self.client_root.post(
            "/api/v1/admin/staff",
            {"role": Role.ADMIN, "name": "A", "phone": "+919820000009"}, format="json")
        r = self.client_root.post(
            "/api/v1/admin/staff",
            {"role": Role.ADMIN, "name": "B", "phone": "+919820000009"}, format="json")
        self.assertEqual(r.status_code, 400)
