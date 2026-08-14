"""Cross-tenant / IDOR authorisation audit.

Every assertion here answers the same question from a different angle: *can an
authenticated caller reach data that isn't theirs by supplying someone else's
id?* Hiding a button is not an answer — each case calls the API directly with a
valid session for the wrong principal.

Existing suites already cover two axes (`storeops.StoreScopeIsolationTests` for
store-vs-store order/inventory/customer reads, and
`orders.ObjectOwnershipSecurityTests` for customer-vs-customer orders). This
covers the axes that were untested: agent-vs-agent task ownership,
customer-vs-customer returns, and the role boundaries between customer / agent /
store staff / admin on privileged and financial endpoints.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import AgentProfile, Role, User
from catalog.models import Category, Product
from delivery.models import DeliveryTask
from inventory.models import Warehouse
from orders.models import Order, OrderStatus
from payments.models import CashCollection
from returns.models import ReturnRequest
from stores.models import Store

#: Anything in this set means "the server refused". 404 is as good as 403 here —
#: better, in fact, since it doesn't confirm the row exists.
DENIED = (401, 403, 404)

_n = iter(range(1, 10_000))


def _phone():
    return f"+91{9500000000 + next(_n)}"


def _client(user):
    c = APIClient()
    c.force_authenticate(user)
    return c


def _agent(name="Rider"):
    user = User.objects.create(phone=_phone(), name=name, role=Role.AGENT)
    AgentProfile.objects.create(user=user, code=f"AG{next(_n)}")
    return user


def _customer(name="Cust"):
    return User.objects.create(phone=_phone(), name=name, role=Role.CUSTOMER)


class AgentVersusAgentTests(TestCase):
    """An agent must not touch another agent's work — the tasks carry real
    money (COD) and real proof-of-delivery."""

    def setUp(self):
        self.a, self.b = _agent("Agent A"), _agent("Agent B")
        self.client_a = _client(self.a)
        customer = _customer()
        self.order = Order.objects.create(
            user=customer, subtotal=Decimal("100"), total=Decimal("100"),
            status=OrderStatus.OUT_FOR_DELIVERY,
        )
        # A task that belongs to agent B.
        self.task_b = DeliveryTask.objects.create(
            order=self.order, agent=self.b, status=DeliveryTask.Status.REACHED
        )
        self.collection_b = CashCollection.objects.create(
            user=customer, agent=self.b, amount=Decimal("500")
        )

    def test_agent_a_cannot_see_agent_bs_delivery(self):
        r = self.client_a.get(f"/api/v1/deliveries/{self.task_b.id}")
        self.assertIn(r.status_code, DENIED, r.content)

    def test_agent_a_cannot_complete_agent_bs_delivery(self):
        r = self.client_a.post(f"/api/v1/deliveries/{self.task_b.id}/complete")
        self.assertIn(r.status_code, DENIED, r.content)
        self.task_b.refresh_from_db()
        self.assertNotEqual(self.task_b.status, DeliveryTask.Status.DELIVERED)

    def test_agent_a_cannot_verify_the_otp_on_agent_bs_delivery(self):
        from delivery.models import DeliveryOTP

        DeliveryOTP.objects.create(task=self.task_b, code="123456")
        r = self.client_a.post(
            f"/api/v1/deliveries/{self.task_b.id}/verify-otp",
            {"code": "123456"}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
        self.task_b.refresh_from_db()
        self.assertFalse(self.task_b.otp_verified)

    def test_agent_a_cannot_fail_agent_bs_delivery(self):
        # A VALID reason code on purpose. An invalid one is rejected by field
        # validation before ownership is ever consulted, so that 400 would prove
        # nothing about authorisation — precisely the weak assertion this suite
        # exists to avoid.
        r = self.client_a.post(
            f"/api/v1/deliveries/{self.task_b.id}/fail",
            {"reasonCode": "FAILED_CUSTOMER_UNREACHABLE"}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
        self.task_b.refresh_from_db()
        self.assertNotEqual(self.task_b.status, DeliveryTask.Status.FAILED)

    def test_agent_a_cannot_collect_agent_bs_cash(self):
        r = self.client_a.post(f"/api/v1/collections/{self.collection_b.id}/collect")
        self.assertIn(r.status_code, DENIED, r.content)
        self.collection_b.refresh_from_db()
        self.assertNotEqual(self.collection_b.status, CashCollection.Status.COLLECTED)

    def test_agent_a_cannot_accept_agent_bs_collection(self):
        r = self.client_a.post(f"/api/v1/collections/{self.collection_b.id}/accept")
        self.assertIn(r.status_code, DENIED, r.content)

    def test_agent_as_task_list_does_not_leak_agent_bs_work(self):
        body = self.client_a.get("/api/v1/deliveries/assigned").content.decode()
        self.assertNotIn(f'"id":{self.task_b.id},', body)


class CustomerVersusCustomerTests(TestCase):
    """A customer must not reach another customer's return, refund or ledger."""

    def setUp(self):
        self.alice, self.bob = _customer("Alice"), _customer("Bob")
        self.bob_c = _client(self.bob)
        self.order = Order.objects.create(
            user=self.alice, subtotal=Decimal("500"), total=Decimal("500"),
            status=OrderStatus.DELIVERED,
        )
        self.ret = ReturnRequest.objects.create(
            user=self.alice, order=self.order, reason="damaged",
            refund_amount=Decimal("500"),
        )

    def test_bob_cannot_read_alices_return(self):
        r = self.bob_c.get(f"/api/v1/returns/{self.ret.code}")
        self.assertIn(r.status_code, DENIED, r.content)

    def test_bob_cannot_raise_a_return_on_alices_order(self):
        r = self.bob_c.post(
            f"/api/v1/orders/{self.order.code}/returns",
            {"reason": "damaged"}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
        self.assertEqual(ReturnRequest.objects.filter(order=self.order).count(), 1)

    def test_bobs_return_list_does_not_include_alices(self):
        body = self.bob_c.get("/api/v1/returns").content.decode()
        self.assertNotIn(self.ret.code, body)

    def test_bob_cannot_decide_a_return_at_all(self):
        """The decision endpoints are staff-only; a customer has no route to
        approve their own refund."""
        for path in (
            f"/api/v1/admin/returns/{self.ret.code}/status",
            f"/api/v1/store/returns/{self.ret.code}/status",
        ):
            r = self.bob_c.post(path, {"status": "refunded"}, format="json")
            self.assertIn(r.status_code, DENIED, f"{path} -> {r.status_code}")
        self.ret.refresh_from_db()
        self.assertEqual(self.ret.status, "requested")

    def test_bob_cannot_read_alices_credit_ledger(self):
        """`/credit/ledger` is a "my ledger" endpoint — it must key on the
        caller, never on a supplied user id."""
        body = self.bob_c.get("/api/v1/credit/ledger", {"user": self.alice.id}).content
        self.assertNotIn(str(self.alice.phone).encode(), body)


class RoleBoundaryTests(TestCase):
    """Role gates on privileged and financial endpoints, called directly."""

    def setUp(self):
        self.customer = _customer()
        self.agent = _agent()
        self.admin = User.objects.create(
            phone=_phone(), name="Admin", role=Role.ADMIN
        )
        self.customer_c, self.agent_c = _client(self.customer), _client(self.agent)
        self.category, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Rice", brand="VS", unit="1", price=Decimal("50"),
            mrp=Decimal("60"), category=self.category, stock_count=None,
        )
        Warehouse.objects.create(name="W", code=f"W{next(_n)}", is_default=True)
        self.store = Store.objects.create(code=f"ST{next(_n)}", name="Store")

    # ── a customer is not staff ──
    def test_customer_cannot_reach_admin_surfaces(self):
        for path in (
            "/api/v1/admin/config",
            "/api/v1/admin/orders",
            "/api/v1/admin/stores",
            "/api/v1/admin/zones",
            "/api/v1/admin/catalog/products",
            "/api/v1/admin/marketing/coupons",
            "/api/v1/admin/kyc/queue",
            "/api/v1/admin/collections",
            "/api/v1/admin/returns",
        ):
            r = self.customer_c.get(path)
            self.assertIn(r.status_code, DENIED, f"{path} -> {r.status_code}")

    def test_customer_cannot_reach_store_surfaces(self):
        for path in ("/api/v1/store/me", "/api/v1/store/orders",
                     "/api/v1/store/inventory", "/api/v1/store/agents/cash"):
            r = self.customer_c.get(path)
            self.assertIn(r.status_code, DENIED, f"{path} -> {r.status_code}")

    def test_customer_cannot_change_a_product_price(self):
        r = self.customer_c.patch(
            f"/api/v1/admin/catalog/products/{self.product.id}",
            {"price": "1"}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
        self.product.refresh_from_db()
        self.assertEqual(self.product.price, Decimal("50"))

    def test_customer_cannot_delete_a_store(self):
        r = self.customer_c.delete(f"/api/v1/admin/stores/{self.store.id}")
        self.assertIn(r.status_code, DENIED, r.content)
        self.assertTrue(Store.objects.filter(pk=self.store.pk).exists())

    def test_customer_cannot_move_the_platform_gst_rate(self):
        r = self.customer_c.patch(
            "/api/v1/admin/config", {"gst_rate": "0"}, format="json"
        )
        self.assertIn(r.status_code, DENIED, r.content)

    # ── an agent is not finance, and not an admin ──
    def test_agent_cannot_reach_financial_admin_surfaces(self):
        for path in (
            "/api/v1/admin/payments",
            "/api/v1/admin/cash/deposits",
            "/api/v1/accounting/trial-balance",
            "/api/v1/admin/config",
        ):
            r = self.agent_c.get(path)
            self.assertIn(r.status_code, DENIED, f"{path} -> {r.status_code}")

    def test_agent_cannot_verify_their_own_cash_deposit(self):
        """Self-verification would let an agent close out a shortfall."""
        from payments.cashbook_services import create_deposit

        deposit = create_deposit(self.agent, amount="500", method="bank")
        r = self.agent_c.post(
            f"/api/v1/admin/cash/deposits/{deposit.id}/verify",
            {"countedAmount": "500"}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
        deposit.refresh_from_db()
        self.assertEqual(deposit.status, "pending")

    def test_agent_cannot_release_a_collection_otp_lockout(self):
        """The supervisor override exists precisely so the agent isn't the one
        deciding their own collection was verified."""
        collection = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("500"),
            manual_verification_required=True,
        )
        r = self.agent_c.post(
            f"/api/v1/admin/collections/{collection.id}/manual-verify", {}, format="json"
        )
        self.assertIn(r.status_code, DENIED, r.content)
        collection.refresh_from_db()
        self.assertFalse(collection.otp_verified)

    def test_agent_cannot_curate_the_customer_home_screen(self):
        r = self.agent_c.post(
            "/api/v1/admin/catalog/home-sections",
            {"section": "popular", "productId": self.product.id}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)

    # ── anonymous ──
    def test_anonymous_cannot_reach_any_privileged_surface(self):
        anon = APIClient()
        for path in ("/api/v1/admin/config", "/api/v1/store/orders",
                     "/api/v1/deliveries/assigned", "/api/v1/orders",
                     "/api/v1/admin/catalog/home-sections"):
            r = anon.get(path)
            self.assertIn(r.status_code, (401, 403), f"{path} -> {r.status_code}")


class StoreVersusStoreFinancialTests(TestCase):
    """Store-scoping on the surfaces the earlier isolation suite didn't reach:
    agent cash, returns and product writes."""

    def setUp(self):
        from storeops.tests import client_for as _c
        from storeops.tests import mk_staff, mk_store

        self.a, self.b = mk_store("A"), mk_store("B")
        self.mgr_a = _c(mk_staff(self.a, "manager"))

        # An agent owned by store B, holding store B's cash.
        self.agent_b = _agent("B Rider")
        self.agent_b.agent_profile.store = self.b
        self.agent_b.agent_profile.save(update_fields=["store"])
        customer = _customer()
        self.collection_b = CashCollection.objects.create(
            user=customer, agent=self.agent_b, amount=Decimal("900"),
            collected_amount=Decimal("900"),
            status=CashCollection.Status.COLLECTED,
        )

        # A return against store B's order.
        order_b = Order.objects.create(
            user=customer, store=self.b, subtotal=Decimal("500"),
            total=Decimal("500"), status=OrderStatus.DELIVERED,
        )
        self.return_b = ReturnRequest.objects.create(
            user=customer, order=order_b, reason="damaged",
            refund_amount=Decimal("500"),
        )

    def test_store_a_does_not_see_store_bs_cash_in_hand(self):
        body = self.mgr_a.get("/api/v1/store/agents/cash").content.decode()
        self.assertNotIn("B Rider", body)

    def test_store_a_cannot_open_store_bs_return(self):
        r = self.mgr_a.get(f"/api/v1/store/returns/{self.return_b.code}")
        self.assertIn(r.status_code, DENIED, r.content)

    def test_store_a_cannot_decide_store_bs_return(self):
        r = self.mgr_a.post(
            f"/api/v1/store/returns/{self.return_b.code}/status",
            {"status": "refunded"}, format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
        self.return_b.refresh_from_db()
        self.assertEqual(self.return_b.status, "requested")

    def test_store_a_cannot_adjust_store_bs_private_product(self):
        """`scoped_product` is what stops one store posting stock movements
        against another store's private item."""
        from catalog.models import Category as C

        cat, _ = C.objects.get_or_create(name="Grocery", slug="grocery")
        private_b = Product.objects.create(
            name="B Private", brand="VS", unit="1", price=Decimal("10"),
            mrp=Decimal("12"), category=cat, origin_store=self.b, stock_count=None,
        )
        r = self.mgr_a.post(
            "/api/v1/store/inventory/adjust",
            {"productId": private_b.id, "quantity": 5, "reason": "found"},
            format="json",
        )
        self.assertIn(r.status_code, DENIED, r.content)
