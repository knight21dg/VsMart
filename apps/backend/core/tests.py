"""Cross-cutting API contract tests for the error/response layer."""
from django.db import IntegrityError
from django.db.models import ProtectedError
from django.test import TestCase, RequestFactory

from accounts.models import User
from core.exceptions import api_exception_handler
from orders.models import Order


class DatabaseIntegrityErrorTests(TestCase):
    """`ProtectedError` and `IntegrityError` are Django exceptions, not DRF ones.

    Before this they fell straight past the DRF exception handler and were
    rendered as a bare 500 "We hit a temporary problem on our end." — so an admin
    who tried to delete a customer that still had orders was told the *server*
    was broken, when the truth ("orders still reference this record") was sitting
    right there in the exception. Both now map to a 409 that says what happened.
    """

    def setUp(self):
        self.rf = RequestFactory()
        self.request = self.rf.delete("/api/v1/admin/customers/1")
        self.request.user = User.objects.create(
            phone="+919000000901", name="Admin", role="admin"
        )
        self.context = {"request": self.request}

    def _handle(self, exc):
        response = api_exception_handler(exc, self.context)
        self.assertIsNotNone(response)
        return response

    def test_protected_error_becomes_409_naming_the_blockers(self):
        customer = User.objects.create(
            phone="+919000000902", name="Cust", role="customer"
        )
        order = Order.objects.create(user=customer)
        exc = ProtectedError("protected", {order})

        response = self._handle(exc)

        self.assertEqual(response.status_code, 409)
        self.assertFalse(response.data["success"])
        self.assertEqual(response.data["code"], "RECORD_IN_USE")
        # The message names what is actually blocking the delete.
        self.assertIn("order", response.data["message"].lower())
        self.assertIn("can't be deleted", response.data["message"])

    def test_protected_error_without_objects_still_explains_itself(self):
        response = self._handle(ProtectedError("protected", set()))

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["code"], "RECORD_IN_USE")
        self.assertIn("depend on it", response.data["message"])

    def test_unique_violation_becomes_409_duplicate(self):
        response = self._handle(
            IntegrityError("UNIQUE constraint failed: stores_store.code")
        )

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["code"], "DUPLICATE_RECORD")
        self.assertIn("already exists", response.data["message"])

    def test_non_unique_integrity_error_stays_a_server_error(self):
        """A NOT NULL / FK integrity failure is a genuine bug, not user error —
        it must not be dressed up as "already exists"."""
        response = self._handle(
            IntegrityError("NOT NULL constraint failed: stores_store.name")
        )

        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.data["code"], "SYSTEM_ERROR")

    def test_error_body_never_leaks_the_raw_exception(self):
        response = self._handle(
            IntegrityError("NOT NULL constraint failed: stores_store.name")
        )
        self.assertNotIn("stores_store", str(response.data))


class DependentPluralisationTests(TestCase):
    def test_plurals(self):
        from core.exceptions import obj_meta_plural

        self.assertEqual(obj_meta_plural("order"), "orders")
        self.assertEqual(obj_meta_plural("box"), "boxes")
        self.assertEqual(obj_meta_plural("category"), "categories")
        self.assertEqual(obj_meta_plural("day"), "days")


class InventoryErrorTests(TestCase):
    """`InventoryError` is a bare Exception raised throughout
    `inventory.services` — oversell, a pack-less movement on a product sold by
    pack, an adjustment below zero. It is not a DRF exception, so every one of
    those guards reached the operator as a 500 "We hit a temporary problem on
    our end.", hiding a message that was already exactly what they needed.
    """

    def setUp(self):
        self.rf = RequestFactory()
        self.request = self.rf.post("/api/v1/inventory/transfer")
        self.request.user = User.objects.create(
            phone="+919000000921", name="Admin", role="admin"
        )
        self.context = {"request": self.request}

    def test_an_inventory_rule_becomes_a_409_carrying_its_own_message(self):
        from inventory.services import InventoryError

        response = api_exception_handler(
            InventoryError("Rice is sold by pack — name a variant (1 kg, 5 kg)."),
            self.context,
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data["code"], "INVENTORY_RULE")
        # The service's sentence survives — that is the whole point.
        self.assertIn("sold by pack", response.data["message"])
        self.assertIn("1 kg", response.data["message"])

    def test_a_message_less_inventory_error_still_says_something_useful(self):
        from inventory.services import InventoryError

        response = api_exception_handler(InventoryError(), self.context)
        self.assertEqual(response.status_code, 409)
        self.assertTrue(response.data["message"])
        self.assertNotIn("temporary problem", response.data["message"])

    def test_it_is_not_retryable(self):
        """A refused stock move is a decision, not a blip — offering "retry"
        invites the operator to mash the button."""
        from inventory.services import InventoryError

        response = api_exception_handler(InventoryError("nope"), self.context)
        self.assertFalse(response.data["retryable"])
