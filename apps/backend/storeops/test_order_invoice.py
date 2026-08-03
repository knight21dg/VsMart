"""Store staff can pull an online order's invoice — and only for their OWN store."""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from orders.models import Order

from .tests import _seq, client_for, mk_staff, mk_store


def _customer():
    return User.objects.create(
        phone=f"+91{9800000000 + next(_seq)}", name="Cust", role=Role.CUSTOMER
    )


class StoreOrderInvoiceTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.other = mk_store()
        self.mgr = client_for(mk_staff(self.store, role="manager"))
        self.order = Order.objects.create(
            user=_customer(),
            store=self.store,
            subtotal=Decimal("100"),
            gst=Decimal("5"),
            total=Decimal("105"),
        )

    def test_staff_can_download_their_stores_invoice(self):
        r = self.mgr.get(f"/api/v1/store/orders/{self.order.code}/invoice")
        self.assertEqual(r.status_code, 200, r.content[:300])
        self.assertEqual(r["Content-Type"], "application/pdf")
        self.assertIn("attachment", r["Content-Disposition"])
        self.assertIn(self.order.code, r["Content-Disposition"])
        self.assertTrue(r.content.startswith(b"%PDF"))

    def test_inline_flag_renders_in_browser(self):
        r = self.mgr.get(f"/api/v1/store/orders/{self.order.code}/invoice?inline=1")
        self.assertEqual(r.status_code, 200)
        self.assertIn("inline", r["Content-Disposition"])

    def test_another_stores_order_is_not_reachable(self):
        # The order code is guessable, so scoping is the only thing stopping a
        # neighbouring store from pulling a customer's invoice.
        theirs = Order.objects.create(
            user=_customer(), store=self.other, subtotal=Decimal("10"),
            total=Decimal("10"),
        )
        r = self.mgr.get(f"/api/v1/store/orders/{theirs.code}/invoice")
        self.assertEqual(r.status_code, 404)

    def test_requires_the_orders_view_permission(self):
        limited = client_for(mk_staff(self.store, role="custom", perms=["pos.operate"]))
        r = limited.get(f"/api/v1/store/orders/{self.order.code}/invoice")
        self.assertIn(r.status_code, (403, 404), r.content[:200])

    def test_anonymous_is_rejected(self):
        r = self.client.get(f"/api/v1/store/orders/{self.order.code}/invoice")
        self.assertIn(r.status_code, (401, 403))
