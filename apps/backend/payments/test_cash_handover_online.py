"""Online cash hand-over: an agent sends collected cash to their store via a
Razorpay link instead of physically carrying the notes in.

The invariants under test:
  * the same cash can't be handed over twice — reserving on INITIATED removes it
    from "in hand" immediately, and a physical deposit can't then claim it;
  * a confirmed online hand-over settles straight to VERIFIED (the gateway is the
    proof the money moved — there is nothing to count);
  * a dead link releases the reservation, so the cash reappears in hand;
  * an agent with no managing store can't route an online hand-over;
  * reconciliation counts an in-flight (INITIATED) hand-over as neither declared
    nor in-hand double-counted.
"""
from decimal import Decimal

from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from accounting.chart import seed as seed_chart
from accounts.models import AgentProfile, User
from stores.models import Store

from .cashbook_services import (
    confirm_online_handover,
    create_deposit,
    reconciliation,
    start_online_handover,
    sweep_stale_handovers,
    undeposited_collections,
)
from .models import CashCollection, CashDeposit

TRUSTED = override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
UNTRUSTED = override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=False)


class OnlineHandoverTests(TestCase):
    def setUp(self):
        seed_chart()  # so the GL posting on a verified hand-over has accounts
        self.store = Store.objects.create(
            code="S1", name="MG Road", address="12 MG Road",
            phone="+918000000001", gstin="29ABCDE1234F1Z5",
        )
        self.agent = User.objects.create(
            phone="+919000004001", name="Ravi", role="agent")
        AgentProfile.objects.create(user=self.agent, code="AG1", store=self.store)
        self.customer = User.objects.create(
            phone="+919000004009", name="Cust", role="customer")

        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def _collection(self, amount="500", agent=None):
        return CashCollection.objects.create(
            user=self.customer, agent=agent or self.agent,
            amount=Decimal(amount), collected_amount=Decimal(amount),
            status=CashCollection.Status.COLLECTED, collected_at=timezone.now(),
        )

    def _in_hand(self):
        return sum((c.collected_amount for c in undeposited_collections(self.agent)),
                   Decimal("0.00"))

    # ── happy path ──
    @TRUSTED
    def test_confirmed_online_handover_verifies_and_routes_to_store(self):
        c1 = self._collection("500")
        c2 = self._collection("300")
        deposit, payment, link = start_online_handover(
            self.agent, collection_ids=[c1.id, c2.id])

        # Trusted mock reports the link paid, so start() confirms in-line.
        self.assertEqual(deposit.status, CashDeposit.Status.VERIFIED)
        self.assertEqual(deposit.amount, Decimal("800"))
        self.assertEqual(deposit.store_id, self.store.id)
        self.assertEqual(deposit.method, CashDeposit.Method.UPI)
        self.assertEqual(deposit.verified_amount, Decimal("800"))
        self.assertTrue(deposit.reference)          # gateway payment id
        self.assertEqual(payment.purpose, "handover")
        # cash is now handed over — nothing left in hand.
        self.assertEqual(self._in_hand(), Decimal("0.00"))

    @UNTRUSTED
    def test_unpaid_link_reserves_but_does_not_verify(self):
        c1 = self._collection("500")
        deposit, payment, link = start_online_handover(
            self.agent, collection_ids=[c1.id])
        self.assertEqual(deposit.status, CashDeposit.Status.INITIATED)
        # Reserved: the money has left "in hand" even though it isn't banked yet.
        self.assertEqual(self._in_hand(), Decimal("0.00"))
        self.assertTrue(link["short_url"])

    # ── double-spend protection ──
    @UNTRUSTED
    def test_reserved_cash_cannot_also_be_handed_over_in_person(self):
        c1 = self._collection("500")
        start_online_handover(self.agent, collection_ids=[c1.id])
        # The physical path must not be able to claim the same, now-reserved, cash.
        with self.assertRaises(Exception):
            create_deposit(self.agent, amount="500", method="office",
                           collection_ids=[c1.id])

    @UNTRUSTED
    def test_cancelled_link_releases_the_cash(self):
        c1 = self._collection("500")
        deposit, payment, _ = start_online_handover(
            self.agent, collection_ids=[c1.id])
        self.assertEqual(self._in_hand(), Decimal("0.00"))

        # Simulate the gateway reporting the link dead. The service persists the
        # cancellation and returns it (it must not raise — see the service note).
        from unittest.mock import patch
        with patch("payments.cashbook_services.get_gateway") as gw:
            gw.return_value.fetch_payment_link.return_value = {"status": "cancelled"}
            result = confirm_online_handover(deposit, by=self.agent)

        self.assertEqual(result.status, CashDeposit.Status.CANCELLED)
        deposit.refresh_from_db()
        self.assertEqual(deposit.status, CashDeposit.Status.CANCELLED)
        # Cash is back with the agent.
        self.assertEqual(self._in_hand(), Decimal("500"))

    # ── stale-handover sweep (the agent never came back to confirm) ──
    @UNTRUSTED
    def test_sweep_cancels_a_stale_dead_link(self):
        from unittest.mock import patch

        c1 = self._collection("500")
        deposit, _, _ = start_online_handover(self.agent, collection_ids=[c1.id])
        CashDeposit.objects.filter(id=deposit.id).update(
            created_at=timezone.now() - timezone.timedelta(minutes=45))

        with patch("payments.cashbook_services.get_gateway") as gw:
            gw.return_value.fetch_payment_link.return_value = {"status": "expired"}
            summary = sweep_stale_handovers(older_than_minutes=30)

        self.assertEqual(summary, {"checked": 1, "verified": 0, "cancelled": 1, "errors": 0})
        deposit.refresh_from_db()
        self.assertEqual(deposit.status, CashDeposit.Status.CANCELLED)
        self.assertEqual(self._in_hand(), Decimal("500"))  # cash returned

    @UNTRUSTED
    def test_sweep_settles_a_stale_link_that_was_actually_paid(self):
        """The agent paid but the app never got a chance to confirm (killed,
        crashed, no network on return) — the sweep must recover the money,
        not just wipe the hand-over because it's old."""
        from unittest.mock import patch

        c1 = self._collection("500")
        deposit, _, _ = start_online_handover(self.agent, collection_ids=[c1.id])
        CashDeposit.objects.filter(id=deposit.id).update(
            created_at=timezone.now() - timezone.timedelta(minutes=45))

        with patch("payments.cashbook_services.get_gateway") as gw:
            gw.return_value.fetch_payment_link.return_value = {
                "status": "paid", "payment_id": "pay_swept123",
            }
            summary = sweep_stale_handovers(older_than_minutes=30)

        self.assertEqual(summary, {"checked": 1, "verified": 1, "cancelled": 0, "errors": 0})
        deposit.refresh_from_db()
        self.assertEqual(deposit.status, CashDeposit.Status.VERIFIED)
        self.assertEqual(deposit.verified_amount, Decimal("500"))

    @UNTRUSTED
    def test_sweep_leaves_a_recent_handover_alone(self):
        """Must never race an agent who is still mid-payment."""
        from unittest.mock import patch

        c1 = self._collection("500")
        deposit, _, _ = start_online_handover(self.agent, collection_ids=[c1.id])
        # created "now" — well inside the window.

        with patch("payments.cashbook_services.get_gateway") as gw:
            gw.return_value.fetch_payment_link.return_value = {"status": "cancelled"}
            summary = sweep_stale_handovers(older_than_minutes=30)

        self.assertEqual(summary, {"checked": 0, "verified": 0, "cancelled": 0, "errors": 0})
        deposit.refresh_from_db()
        self.assertEqual(deposit.status, CashDeposit.Status.INITIATED)

    @UNTRUSTED
    def test_sweep_survives_one_bad_row_and_continues(self):
        from unittest.mock import patch

        c1 = self._collection("300")
        c2 = self._collection("200")
        d1, _, _ = start_online_handover(self.agent, collection_ids=[c1.id])
        d2, _, _ = start_online_handover(self.agent, collection_ids=[c2.id])
        CashDeposit.objects.filter(id__in=[d1.id, d2.id]).update(
            created_at=timezone.now() - timezone.timedelta(minutes=45))

        def flaky_fetch(link_id):
            if link_id == d1.payment.gateway_order_id:
                raise ConnectionError("gateway unreachable")
            return {"status": "expired"}

        with patch("payments.cashbook_services.get_gateway") as gw:
            gw.return_value.fetch_payment_link.side_effect = flaky_fetch
            summary = sweep_stale_handovers(older_than_minutes=30)

        self.assertEqual(summary, {"checked": 2, "verified": 0, "cancelled": 1, "errors": 1})
        d1.refresh_from_db()
        d2.refresh_from_db()
        self.assertEqual(d1.status, CashDeposit.Status.INITIATED)  # untouched
        self.assertEqual(d2.status, CashDeposit.Status.CANCELLED)

    # ── guards ──
    def test_agent_without_store_cannot_go_online(self):
        loner = User.objects.create(phone="+919000004077", name="Solo",
                                    role="agent")
        AgentProfile.objects.create(user=loner, code="AG9", store=None)
        c = CashCollection.objects.create(
            user=self.customer, agent=loner, amount=Decimal("200"),
            collected_amount=Decimal("200"),
            status=CashCollection.Status.COLLECTED, collected_at=timezone.now(),
        )
        with self.assertRaises(Exception) as ctx:
            start_online_handover(loner, collection_ids=[c.id])
        self.assertEqual(ctx.exception.code, "CASH_HANDOVER_STORE_MISSING")

    @UNTRUSTED
    def test_amount_is_derived_from_collections_not_the_client(self):
        c1 = self._collection("500")
        deposit, _, _ = start_online_handover(self.agent, collection_ids=[c1.id])
        # Even though the app never sends an amount, the link is for the real held
        # figure.
        self.assertEqual(deposit.amount, Decimal("500"))

    @UNTRUSTED
    def test_confirm_is_idempotent_when_already_verified(self):
        c1 = self._collection("500")
        deposit, payment, _ = start_online_handover(
            self.agent, collection_ids=[c1.id])
        # Force it verified as if already confirmed.
        deposit.status = CashDeposit.Status.VERIFIED
        deposit.verified_amount = deposit.amount
        deposit.save(update_fields=["status", "verified_amount"])
        again = confirm_online_handover(deposit, by=self.agent)
        self.assertEqual(again.status, CashDeposit.Status.VERIFIED)

    # ── reconciliation ──
    @UNTRUSTED
    def test_initiated_handover_is_not_counted_as_declared(self):
        c1 = self._collection("500")
        start_online_handover(self.agent, collection_ids=[c1.id])
        recon = reconciliation(agent=self.agent)
        # Money reserved but not arrived: not declared, and not still in hand.
        self.assertEqual(recon["declared"], Decimal("0.00"))
        self.assertEqual(recon["inHand"], Decimal("0.00"))

    @TRUSTED
    def test_confirmed_handover_counts_as_declared_and_verified(self):
        c1 = self._collection("500")
        start_online_handover(self.agent, collection_ids=[c1.id])
        recon = reconciliation(agent=self.agent)
        self.assertEqual(recon["declared"], Decimal("500"))
        self.assertEqual(recon["verified"], Decimal("500"))

    # ── API surface ──
    @TRUSTED
    def test_online_endpoint_returns_link_and_channel(self):
        c1 = self._collection("500")
        r = self.client.post(
            "/api/v1/agent/cash/online",
            {"collectionIds": [c1.id]}, format="json")
        self.assertEqual(r.status_code, 201)
        data = r.json()["data"]
        self.assertEqual(data["channel"], "online")
        self.assertIn("payment", data)
        self.assertIn("shortUrl", data["payment"])

    @UNTRUSTED
    def test_confirm_endpoint_is_scoped_to_owner(self):
        other = User.objects.create(phone="+919000004055", name="Mallory",
                                    role="agent")
        AgentProfile.objects.create(user=other, code="AG5", store=self.store)
        c1 = self._collection("500")
        deposit, _, _ = start_online_handover(self.agent, collection_ids=[c1.id])

        thief = APIClient()
        thief.force_authenticate(other)
        r = thief.post(f"/api/v1/agent/cash/online/{deposit.id}/confirm",
                       {}, format="json")
        self.assertEqual(r.status_code, 404)
