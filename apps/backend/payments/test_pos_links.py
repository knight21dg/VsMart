"""Counter payments: the till may only mark a sale paid on the gateway's word.

`POSPayment.Method.UPI/CARD` existed only as tender *labels* — the cashier typed
a reference and the sale was booked as paid with nothing verifying that money had
moved. These lock down the replacement: a Razorpay payment link the customer pays
from their own phone, polled until the gateway confirms it.
"""
from decimal import Decimal

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import User

from .models import Payment, PaymentEvent
from .pos_link_services import create_counter_link, poll_counter_link


# The mock gateway only self-settles where it is explicitly trusted (dev/CI).
TRUSTED = override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=True)
UNTRUSTED = override_settings(PAYMENTS_TRUST_MOCK_GATEWAY=False)


class CounterLinkTests(TestCase):
    def setUp(self):
        self.cashier = User.objects.create(phone="+919000006001", name="Cashier",
                                           role="staff")
        self.customer = User.objects.create(phone="+919000006002", name="Cust",
                                            role="customer")

    # ── creation ──
    @UNTRUSTED
    def test_a_link_creates_a_pending_payment_row(self):
        """The row exists from the start so an abandoned link is still visible
        in the ledger rather than vanishing."""
        payment, link = create_counter_link(
            amount="250", store=None, cashier=self.cashier, customer=self.customer,
        )
        self.assertEqual(payment.status, Payment.Status.PENDING)
        self.assertEqual(payment.amount, Decimal("250"))
        self.assertTrue(payment.gateway_order_id)
        self.assertTrue(link["short_url"])

    @UNTRUSTED
    def test_zero_and_negative_amounts_are_refused(self):
        for bad in ("0", "-10", None):
            with self.assertRaises(Exception):
                create_counter_link(amount=bad, store=None, cashier=self.cashier)

    @UNTRUSTED
    def test_creation_is_recorded_as_an_event(self):
        payment, _ = create_counter_link(amount="100", store=None,
                                         cashier=self.cashier)
        self.assertTrue(
            PaymentEvent.objects.filter(payment=payment,
                                        status=Payment.Status.PENDING).exists()
        )

    # ── the core guarantee ──
    @UNTRUSTED
    def test_an_untrusted_mock_never_self_settles(self):
        """A keyless production-like environment must not be able to mark a real
        sale paid without a gateway."""
        payment, _ = create_counter_link(amount="500", store=None,
                                         cashier=self.cashier)
        self.assertEqual(payment.status, Payment.Status.PENDING)

        poll_counter_link(payment, by=self.cashier)
        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.PENDING)

    @TRUSTED
    def test_a_trusted_mock_settles_so_dev_can_run_the_flow(self):
        payment, _ = create_counter_link(amount="500", store=None,
                                         cashier=self.cashier)
        self.assertEqual(payment.status, Payment.Status.SUCCESS)

    # ── polling ──
    @TRUSTED
    def test_polling_is_idempotent(self):
        payment, _ = create_counter_link(amount="500", store=None,
                                         cashier=self.cashier)
        poll_counter_link(payment, by=self.cashier)
        poll_counter_link(payment, by=self.cashier)
        payment.refresh_from_db()
        self.assertEqual(payment.status, Payment.Status.SUCCESS)
        # One capture event, not three.
        self.assertEqual(
            PaymentEvent.objects.filter(payment=payment,
                                        status=Payment.Status.SUCCESS).count(), 1)

    @UNTRUSTED
    def test_polling_a_payment_with_no_link_is_refused(self):
        payment = Payment.objects.create(
            user=self.customer, purpose=Payment.Purpose.ORDER,
            amount=Decimal("10"), method=Payment.Method.UPI,
            status=Payment.Status.PENDING,
        )
        with self.assertRaises(Exception):
            poll_counter_link(payment)

    @TRUSTED
    def test_a_settled_payment_is_booked_to_the_ledger(self):
        from accounting.chart import seed
        from accounting.models import JournalEntry

        seed()
        payment, _ = create_counter_link(amount="500", store=None,
                                         cashier=self.cashier)
        entry = JournalEntry.objects.filter(source_module="payment",
                                            source_ref=str(payment.id)).first()
        self.assertIsNotNone(entry, "counter payment should hit the GL")
        self.assertTrue(entry.is_balanced)


class CounterLinkApiTests(TestCase):
    """Store-scoped access: only a cashier with pos.operate may raise a charge."""

    def setUp(self):
        self.customer = User.objects.create(phone="+919000006010", name="Cust",
                                            role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.customer)

    def test_a_customer_cannot_raise_a_counter_charge(self):
        r = self.client.post("/api/v1/store/pos/payment-link",
                             {"amount": "100"}, format="json")
        self.assertIn(r.status_code, (401, 403))

    def test_a_customer_cannot_poll_a_counter_charge(self):
        r = self.client.get("/api/v1/store/pos/payment-link/1")
        self.assertIn(r.status_code, (401, 403, 404))
