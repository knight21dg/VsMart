"""Cash book: collected cash -> agent deposit -> finance verification.

Before this only the collection was recorded. Nothing tracked the physical
notes afterwards, so "how much cash is with agents right now?" was unanswerable
and collected-vs-banked could drift apart forever.
"""
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User

from core.app_errors import AppError

from .cashbook_services import cash_in_hand, create_deposit, reconciliation
from .models import CashCollection, CashDeposit


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


class CashBookTests(TestCase):
    def setUp(self):
        self.agent = User.objects.create(phone="+919000003001", name="Ravi",
                                         role="agent")
        self.agent2 = User.objects.create(phone="+919000003002", name="Sita",
                                          role="agent")
        self.admin = User.objects.create(phone="+919000003003", name="Fin",
                                         role="admin")
        self.customer = User.objects.create(phone="+919000003004", name="Cust",
                                            role="customer")
        self.agent_client = APIClient()
        self.agent_client.force_authenticate(self.agent)
        self.staff = APIClient()
        self.staff.force_authenticate(self.admin)

    def _collection(self, amount="500", agent=None, status=None):
        return CashCollection.objects.create(
            user=self.customer,
            agent=agent or self.agent,
            amount=Decimal(amount),
            collected_amount=Decimal(amount),
            status=status or CashCollection.Status.COLLECTED,
            collected_at=timezone.now(),
        )

    # ── cash in hand ──
    def test_collected_cash_shows_as_in_hand_until_deposited(self):
        self._collection("500")
        self._collection("300")
        rows = cash_in_hand()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["amount"], Decimal("800"))
        self.assertEqual(rows[0]["collections"], 2)

    def test_depositing_clears_it_from_in_hand(self):
        c1 = self._collection("500")
        self._collection("300")
        create_deposit(self.agent, amount="500", method="bank",
                       collection_ids=[c1.id])
        rows = cash_in_hand()
        self.assertEqual(rows[0]["amount"], Decimal("300"))

    def test_in_hand_is_per_agent(self):
        self._collection("500", agent=self.agent)
        self._collection("900", agent=self.agent2)
        rows = {r["agent"]: r["amount"] for r in cash_in_hand()}
        self.assertEqual(rows["Ravi"], Decimal("500"))
        self.assertEqual(rows["Sita"], Decimal("900"))

    def test_uncollected_tasks_are_not_counted_as_cash(self):
        CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("400"),
            collected_amount=Decimal("0"),
            status=CashCollection.Status.ASSIGNED,
        )
        self.assertEqual(cash_in_hand(), [])

    # ── deposit creation ──
    def test_agent_declares_a_deposit(self):
        c = self._collection("500")
        r = self.agent_client.post("/api/v1/agent/cash", {
            "amount": "500", "method": "bank", "reference": "SLIP-1",
            "collectionIds": [c.id],
        }, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        deposit = CashDeposit.objects.get()
        self.assertEqual(deposit.status, CashDeposit.Status.PENDING)
        c.refresh_from_db()
        self.assertEqual(c.deposit_id, deposit.id)

    def test_the_same_collection_cannot_be_banked_twice(self):
        """Otherwise the same cash is counted in two deposits."""
        c = self._collection("500")
        create_deposit(self.agent, amount="500", method="bank",
                       collection_ids=[c.id])
        with self.assertRaises(Exception):
            create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id])

    def test_cannot_bank_another_agents_collection(self):
        c = self._collection("500", agent=self.agent2)
        with self.assertRaises(Exception):
            create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id])

    def test_zero_deposit_is_refused(self):
        r = self.agent_client.post("/api/v1/agent/cash",
                                   {"amount": "0", "method": "bank"},
                                   format="json")
        self.assertEqual(r.status_code, 400)

    # ── verification ──
    def test_verifying_a_matching_deposit(self):
        c = self._collection("500")
        d = create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id])
        r = self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify",
                            {"countedAmount": "500"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        d.refresh_from_db()
        self.assertEqual(d.status, CashDeposit.Status.VERIFIED)
        self.assertEqual(d.shortfall, Decimal("0.00"))
        self.assertEqual(d.verified_by_id, self.admin.id)

    def test_a_short_count_is_recorded_as_a_visible_shortfall(self):
        """The difference must stay attributable, not be quietly adjusted away."""
        c = self._collection("500")
        d = create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id])
        self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify",
                        {"countedAmount": "450"}, format="json")
        d.refresh_from_db()
        self.assertEqual(d.status, CashDeposit.Status.SHORT)
        self.assertEqual(d.shortfall, Decimal("50.00"))
        self.assertEqual(d.amount, Decimal("500"))   # declared figure preserved

    def test_verifying_without_a_count_accepts_the_declared_amount(self):
        d = create_deposit(self.agent, amount="500", method="bank")
        self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify", {},
                        format="json")
        d.refresh_from_db()
        self.assertEqual(d.status, CashDeposit.Status.VERIFIED)

    def test_a_deposit_cannot_be_reviewed_twice(self):
        d = create_deposit(self.agent, amount="500", method="bank")
        self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify", {},
                        format="json")
        r = self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify", {},
                            format="json")
        self.assertEqual(r.status_code, 409)

    def test_rejecting_returns_the_cash_to_the_agents_hands(self):
        """The money didn't arrive — it must show as still outstanding, not vanish."""
        c = self._collection("500")
        d = create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id])
        self.assertEqual(cash_in_hand(), [])
        r = self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/reject",
                            {"reason": "Never reached the bank"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        d.refresh_from_db()
        self.assertEqual(d.status, CashDeposit.Status.REJECTED)
        self.assertEqual(cash_in_hand()[0]["amount"], Decimal("500"))

    def test_rejecting_requires_a_reason(self):
        d = create_deposit(self.agent, amount="500", method="bank")
        r = self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/reject", {},
                            format="json")
        self.assertEqual(r.status_code, 400)

    # ── reconciliation ──
    def test_reconciliation_shows_the_whole_chain(self):
        c1 = self._collection("500")
        c2 = self._collection("300")
        d = create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c1.id])
        self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify",
                        {"countedAmount": "480"}, format="json")

        summary = reconciliation()
        self.assertEqual(summary["collected"], Decimal("800"))
        self.assertEqual(summary["declared"], Decimal("500"))
        self.assertEqual(summary["verified"], Decimal("480"))
        self.assertEqual(summary["shortfall"], Decimal("20"))
        self.assertEqual(summary["inHand"], Decimal("300"))   # c2 still held
        self.assertIsNotNone(c2.id)

    def test_rejected_deposits_are_excluded_from_declared(self):
        d = create_deposit(self.agent, amount="500", method="bank")
        self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/reject",
                        {"reason": "no show"}, format="json")
        self.assertEqual(reconciliation()["declared"], Decimal("0.00"))

    # ── agent view + access ──
    def test_agent_sees_only_their_own_cash(self):
        self._collection("500", agent=self.agent)
        self._collection("900", agent=self.agent2)
        data = _data(self.agent_client.get("/api/v1/agent/cash"))
        self.assertEqual(Decimal(str(data["inHand"])), Decimal("500"))
        self.assertEqual(len(data["collections"]), 1)

    def test_customers_cannot_reach_the_cash_book(self):
        c = APIClient()
        c.force_authenticate(self.customer)
        for url in ("/api/v1/admin/cash/deposits",
                    "/api/v1/admin/cash/reconciliation",
                    "/api/v1/admin/cash/in-hand"):
            self.assertEqual(c.get(url).status_code, 403, url)

    def test_deposit_detail_traces_back_to_the_customers_who_paid(self):
        c = self._collection("500")
        d = create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id])
        data = _data(self.staff.get(f"/api/v1/admin/cash/deposits/{d.id}"))
        self.assertEqual(len(data["collections"]), 1)
        self.assertEqual(data["collections"][0]["customerName"], "Cust")

    def test_every_state_change_is_audited(self):
        from accounts.models import AuditLog

        c = self._collection("500")
        d = create_deposit(self.agent, amount="500", method="bank",
                           collection_ids=[c.id], actor=self.agent)
        self.staff.post(f"/api/v1/admin/cash/deposits/{d.id}/verify",
                        {"countedAmount": "500"}, format="json")
        actions = set(AuditLog.objects.values_list("action", flat=True))
        self.assertIn("cash.deposit.create", actions)
        self.assertIn("cash.deposit.verified", actions)


class PaymentReceiptTests(TestCase):
    """Credit repayments had no document at all — the app's Download Receipt
    only showed a snackbar."""

    def setUp(self):
        from .models import Payment

        self.customer = User.objects.create(phone="+919000003010", name="Meena",
                                            role="customer")
        self.other = User.objects.create(phone="+919000003011", name="Other",
                                         role="customer")
        self.admin = User.objects.create(phone="+919000003012", name="A",
                                         role="admin")
        self.payment = Payment.objects.create(
            user=self.customer, purpose=Payment.Purpose.REPAYMENT,
            amount=Decimal("1250.50"), method=Payment.Method.UPI,
            status=Payment.Status.SUCCESS, gateway_payment_id="pay_XYZ",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.customer)

    def test_customer_gets_a_real_pdf(self):
        r = self.client.get(f"/api/v1/payments/{self.payment.id}/receipt")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "application/pdf")
        self.assertTrue(r.content.startswith(b"%PDF"))
        self.assertGreater(len(r.content), 1000)

    def test_another_customers_receipt_is_not_reachable(self):
        c = APIClient()
        c.force_authenticate(self.other)
        r = c.get(f"/api/v1/payments/{self.payment.id}/receipt")
        self.assertEqual(r.status_code, 404)

    def test_an_incomplete_payment_has_no_receipt(self):
        from .models import Payment

        pending = Payment.objects.create(
            user=self.customer, purpose=Payment.Purpose.ORDER,
            amount=Decimal("100"), method=Payment.Method.UPI,
            status=Payment.Status.PENDING,
        )
        r = self.client.get(f"/api/v1/payments/{pending.id}/receipt")
        self.assertEqual(r.status_code, 409)

    def test_admin_can_pull_any_receipt_for_support(self):
        staff = APIClient()
        staff.force_authenticate(self.admin)
        r = staff.get(f"/api/v1/admin/payments/{self.payment.id}/receipt")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.content.startswith(b"%PDF"))

    def test_a_customer_cannot_use_the_admin_receipt_route(self):
        r = self.client.get(f"/api/v1/admin/payments/{self.payment.id}/receipt")
        self.assertEqual(r.status_code, 403)


from django.test import override_settings as _override


# UNTRUSTED mock: the link must stay unpaid so the deposit is genuinely
# awaiting payment — exactly the state an agent cancels out of.
@_override(PAYMENTS_TRUST_MOCK_GATEWAY=False)
class OnlineHandoverCancelTests(TestCase):
    """Agent-initiated cancel of an unpaid online hand-over: the reserved cash
    must return to in-hand immediately — backing out used to leave the deposit
    INITIATED with the collections stuck on it."""

    def setUp(self):
        from accounts.models import AgentProfile, User
        from stores.models import Store

        self.store = Store.objects.create(name="S1", code="S1", status="active")
        self.agent = User.objects.create(
            phone="+919777777600", name="Agent D", role="agent")
        AgentProfile.objects.create(
            user=self.agent, code="AGD", store=self.store)
        self.customer = User.objects.create(
            phone="+919000000600", role="customer")
        self.collection = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=Decimal("500"),
            collected_amount=Decimal("500"),
            status=CashCollection.Status.COLLECTED,
            collected_at=timezone.now())
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def _start(self):
        from payments.cashbook_services import start_online_handover

        return start_online_handover(
            self.agent, collection_ids=[self.collection.id])

    def test_cancel_frees_the_cash_back_to_in_hand(self):
        from payments.cashbook_services import cash_in_hand

        result = self._start()
        deposit_id = result[0].id  # start returns (deposit, link_state)
        r = self.client.post(f"/api/v1/agent/cash/online/{deposit_id}/cancel")
        self.assertEqual(r.status_code, 200, getattr(r, "data", r))
        self.assertEqual(r.data["status"], "cancelled")
        self.collection.refresh_from_db()
        self.assertIsNone(self.collection.deposit_id)
        rows = cash_in_hand(agent=self.agent)
        self.assertEqual(rows[0]["amount"], Decimal("500"))

    def test_cancel_is_idempotent(self):
        result = self._start()
        deposit_id = result[0].id  # start returns (deposit, link_state)
        self.client.post(f"/api/v1/agent/cash/online/{deposit_id}/cancel")
        r = self.client.post(f"/api/v1/agent/cash/online/{deposit_id}/cancel")
        self.assertEqual(r.status_code, 200)

    def test_another_agents_deposit_cannot_be_cancelled(self):
        from accounts.models import User

        result = self._start()
        deposit_id = result[0].id  # start returns (deposit, link_state)
        other = User.objects.create(phone="+919777777601", role="agent")
        self.client.force_authenticate(other)
        r = self.client.post(f"/api/v1/agent/cash/online/{deposit_id}/cancel")
        self.assertEqual(r.status_code, 404)


class DeclaredAmountMustMatchCollectionsTests(TestCase):
    """A physical hand-over's declared amount must equal the collections it claims.

    Claiming a collection is what removes its cash from `cash_in_hand`. Nothing
    checked the declared figure against the rows, so an agent could attach
    ₹5,000 of collections while declaring ₹500: all of it left the exposure
    figure, the deposit booked ₹500, and finance counting ₹500 marked it
    VERIFIED (counted >= declared) — the missing ₹4,500 invisible at every step.
    The ONLINE hand-over path already refused this by deriving the amount from
    the rows; the physical path trusted the client.
    """

    def setUp(self):
        self.agent = User.objects.create(
            phone="+919000004001", name="Ravi", role="agent")
        self.customer = User.objects.create(
            phone="+919000004002", name="Cust", role="customer")

    def _collection(self, amount):
        return CashCollection.objects.create(
            user=self.customer, agent=self.agent,
            amount=Decimal(amount), collected_amount=Decimal(amount),
            status=CashCollection.Status.COLLECTED, collected_at=timezone.now(),
        )

    def test_a_matching_declaration_is_accepted(self):
        a, b = self._collection("500"), self._collection("300")
        d = create_deposit(self.agent, amount="800", method="bank",
                           collection_ids=[a.id, b.id])
        self.assertEqual(d.amount, Decimal("800"))
        self.assertEqual(cash_in_hand(), [])

    def test_under_declaring_is_refused_and_nothing_is_claimed(self):
        a, b = self._collection("500"), self._collection("300")
        with self.assertRaises(AppError) as ctx:
            create_deposit(self.agent, amount="100", method="bank",
                           collection_ids=[a.id, b.id])
        self.assertIn("total ₹800", str(ctx.exception))
        # Atomic: the whole deposit rolls back, so the cash is still in hand.
        self.assertEqual(cash_in_hand()[0]["amount"], Decimal("800"))
        self.assertEqual(CashDeposit.objects.count(), 0)

    def test_over_declaring_is_refused_too(self):
        """An inflated declaration would book cash the collections don't back."""
        a = self._collection("500")
        with self.assertRaises(AppError):
            create_deposit(self.agent, amount="900", method="bank",
                           collection_ids=[a.id])
        self.assertEqual(cash_in_hand()[0]["amount"], Decimal("500"))

    def test_a_deposit_with_no_collections_keeps_a_free_amount(self):
        """A loose top-up has nothing to reconcile against, so it stays open."""
        self._collection("500")
        d = create_deposit(self.agent, amount="120", method="office")
        self.assertEqual(d.amount, Decimal("120"))
        # Nothing was claimed, so the collection is still in hand.
        self.assertEqual(cash_in_hand()[0]["amount"], Decimal("500"))
