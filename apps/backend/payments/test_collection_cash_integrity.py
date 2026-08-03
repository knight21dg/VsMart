"""Cash-in-hand integrity — "in hand" must mean physical notes a field agent is
actually holding, and a store-recorded payment must never double-credit a debt an
agent has already partly recovered.

Both were real defects: the store panel's Collect button booked the FULL original
amount (not the outstanding balance) onto any non-`collected` row, overwrote
`collected_amount`, and attributed the money to a holder — so it surfaced as
cash-in-hand for a collection nobody had visited.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import AgentProfile, User
from credit.services import debit_purchase, ensure_account
from inventory.models import Warehouse
from payments.cashbook_services import cash_in_hand, undeposited_collections
from payments.models import CashCollection
from payments.services import collect_cash
from stores.models import Store


def _customer(phone, outstanding="1000"):
    u = User.objects.create(phone=phone, name="Cust", role="customer",
                            kyc_status="verified", credit_enabled=True)
    acct = ensure_account(u)
    debit_purchase(acct, Decimal(outstanding), note="seed")
    return u, acct


class StoreCounterCollectionTests(TestCase):
    def setUp(self):
        wh = Warehouse.objects.create(name="WH", code="WH1")
        self.store = Store.objects.create(
            code="ST1", name="Main", status="active", warehouse=wh)
        self.agent = User.objects.create(
            phone="+919777700301", name="Agent", role="agent")
        AgentProfile.objects.create(
            user=self.agent, store=self.store, is_available=True, code="AG1")
        self.customer, self.acct = _customer("+919000000301", outstanding="1000")
        self.coll = CashCollection.objects.create(
            user=self.customer, amount=Decimal("1000"))

    def test_store_collection_does_not_count_as_cash_in_hand(self):
        """The customer paid at the counter — that money is at the store, not in
        anyone's pocket, so it must not appear as cash somebody owes a hand-over
        for."""
        collect_cash(self.coll, None, method="cash")
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.status, "collected")
        self.assertEqual(self.coll.collected_amount, Decimal("1000"))
        self.assertTrue(self.coll.collected_at_store)
        self.assertIsNone(self.coll.agent)

        self.assertEqual(list(undeposited_collections()), [])
        self.assertEqual(cash_in_hand(), [])

    def test_store_collection_never_lands_on_a_previous_agents_hands(self):
        """A collection the agent failed to recover, later paid at the counter,
        used to be booked onto that agent's cash-in-hand."""
        self.coll.agent = self.agent
        self.coll.status = CashCollection.Status.FAILED
        self.coll.save(update_fields=["agent", "status"])

        collect_cash(self.coll, self.agent, method="upi")
        self.assertEqual(cash_in_hand(agent=self.agent), [])

    def test_partial_recovery_is_not_double_credited(self):
        """₹300 already recovered by the agent; the store closes out the rest.
        Only the ₹700 balance may be booked — booking ₹1000 credited the
        customer ₹1300 against a ₹1000 debt and erased the agent's ₹300."""
        self.coll.agent = self.agent
        self.coll.collected_amount = Decimal("300")
        self.coll.status = CashCollection.Status.PARTIALLY_COLLECTED
        self.coll.save(update_fields=["agent", "collected_amount", "status"])
        self.acct.refresh_from_db()
        debit_before = self.acct.outstanding

        collect_cash(self.coll, self.agent, method="cash")

        self.coll.refresh_from_db()
        self.acct.refresh_from_db()
        self.assertEqual(self.coll.collected_amount, Decimal("1000"))
        self.assertEqual(self.coll.payment.amount, Decimal("700"))
        # Exactly the outstanding balance was repaid — no more.
        self.assertEqual(self.acct.outstanding, debit_before - Decimal("700"))

    def test_already_collected_is_a_no_op(self):
        collect_cash(self.coll, None)
        first_payment = CashCollection.objects.get(pk=self.coll.pk).payment_id
        collect_cash(self.coll, None)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.payment_id, first_payment)
        self.assertEqual(self.coll.collected_amount, Decimal("1000"))

    def test_agent_collected_cash_still_counts_as_in_hand(self):
        """The genuine case must keep working: an agent physically holding notes
        owes a hand-over."""
        self.coll.agent = self.agent
        self.coll.collected_amount = Decimal("1000")
        self.coll.status = CashCollection.Status.COLLECTED
        self.coll.save(update_fields=["agent", "collected_amount", "status"])

        rows = cash_in_hand(agent=self.agent)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["amount"], Decimal("1000"))


class CollectionAssignmentScopingTests(TestCase):
    """A customer-raised collection must reach an agent of the customer's OWN
    store — assignment used to pool every agent on the platform, so the task
    landed on somebody in another town and the store's own agent saw nothing."""

    def setUp(self):
        wh1 = Warehouse.objects.create(name="WH1", code="WH1")
        wh2 = Warehouse.objects.create(name="WH2", code="WH2")
        self.store = Store.objects.create(
            code="ST1", name="Main", status="active", warehouse=wh1)
        self.other = Store.objects.create(
            code="ST2", name="Far", status="active", warehouse=wh2)

        self.mine = User.objects.create(
            phone="+919777700401", name="Mine", role="agent")
        AgentProfile.objects.create(
            user=self.mine, store=self.store, is_available=True, code="AG1")
        self.theirs = User.objects.create(
            phone="+919777700402", name="Theirs", role="agent")
        AgentProfile.objects.create(
            user=self.theirs, store=self.other, is_available=True, code="AG2")

        self.customer, _ = _customer("+919000000401")

    def _collection(self):
        return CashCollection.objects.create(
            user=self.customer, amount=Decimal("500"))

    def test_assignment_prefers_the_customers_store(self):
        from cashcollections import services

        from addresses.models import Address
        from zones.models import Zone

        zone = Zone.objects.create(
            name="Z1", store=self.store, is_active=True, pincodes=["560001"])
        Address.objects.create(
            user=self.customer, line1="1 Main St", pincode="560001",
            is_default=True)
        self.assertIsNotNone(zone)

        coll = self._collection()
        services.auto_assign(coll)
        coll.refresh_from_db()
        self.assertEqual(coll.agent_id, self.mine.id)

    def test_stranded_collection_is_swept_once_an_agent_comes_on_duty(self):
        from cashcollections import services

        AgentProfile.objects.all().update(is_available=False)
        coll = self._collection()
        self.assertIsNone(services.auto_assign(coll))
        coll.refresh_from_db()
        self.assertIsNone(coll.agent)
        self.assertEqual(coll.status, "requested")

        AgentProfile.objects.filter(user=self.mine).update(is_available=True)
        self.assertEqual(services.assign_orphan_collections(), 1)
        coll.refresh_from_db()
        self.assertEqual(coll.agent_id, self.mine.id)
        self.assertEqual(coll.status, "assigned")
        self.assertIsNotNone(coll.assigned_at)
