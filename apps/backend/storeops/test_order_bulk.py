"""Bulk order status: one bad order must not cost the operator the other 29.

Confirming the morning's orders one at a time was 60 clicks and 30 round trips.
The sweep commits each order independently and reports per-order outcomes, so a
single already-dispatched order is skipped and named rather than failing the batch.
"""
from decimal import Decimal

from django.test import TestCase

from orders.models import Order, OrderStatus
from storeops.tests import _data, client_for, mk_staff, mk_store

from accounts.models import Role, User

BULK = "/api/v1/store/orders/bulk-status"


class BulkOrderStatusTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.customer = User.objects.create(
            phone="+919880000001", name="Cust", role=Role.CUSTOMER)

    def _order(self, status=OrderStatus.PENDING, store=None):
        return Order.objects.create(
            user=self.customer, subtotal=Decimal("100"), total=Decimal("100"),
            status=status, store=store if store is not None else self.store,
        )

    def test_confirms_every_selected_order(self):
        codes = [self._order().code for _ in range(3)]
        d = _data(self.mgr.post(BULK, {"status": "confirmed", "codes": codes},
                                format="json"))
        self.assertEqual(d["updatedCount"], 3)
        self.assertEqual(d["failedCount"], 0)
        for c in codes:
            self.assertEqual(Order.objects.get(code=c).status, OrderStatus.CONFIRMED)

    def test_one_bad_order_does_not_sink_the_batch(self):
        good = [self._order().code for _ in range(2)]
        # Already delivered — the state machine refuses to move it to confirmed.
        bad = self._order(status=OrderStatus.DELIVERED).code
        d = _data(self.mgr.post(BULK, {"status": "confirmed", "codes": good + [bad]},
                                format="json"))

        self.assertEqual(d["updatedCount"], 2)
        self.assertEqual(d["failedCount"], 1)
        self.assertEqual(d["failed"][0]["code"], bad)
        for c in good:
            self.assertEqual(Order.objects.get(code=c).status, OrderStatus.CONFIRMED)
        self.assertEqual(Order.objects.get(code=bad).status, OrderStatus.DELIVERED)

    def test_another_stores_order_is_reported_not_touched(self):
        other = self._order(store=mk_store())
        d = _data(self.mgr.post(BULK, {"status": "confirmed", "codes": [other.code]},
                                format="json"))
        self.assertEqual(d["updatedCount"], 0)
        self.assertEqual(d["failedCount"], 1)
        other.refresh_from_db()
        self.assertEqual(other.status, OrderStatus.PENDING)

    def test_agent_owned_statuses_are_refused(self):
        code = self._order().code
        r = self.mgr.post(BULK, {"status": "delivered", "codes": [code]}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_empty_selection_is_rejected(self):
        r = self.mgr.post(BULK, {"status": "confirmed", "codes": []}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_a_cashier_without_orders_manage_cannot_sweep(self):
        cashier = client_for(mk_staff(self.store, "cashier", perms=["orders.view"]))
        code = self._order().code
        r = cashier.post(BULK, {"status": "confirmed", "codes": [code]}, format="json")
        self.assertEqual(r.status_code, 403)
