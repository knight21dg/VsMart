"""The producers billing.Invoice / billing.Receipt / credit.Statement never had.

Each model had a complete read + PDF pipeline and ZERO rows in production,
because no code ever created one — the same dead-wiring class as the dispatch
engine. These tests pin the producers and their idempotency.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase

from accounts.models import User
from billing.models import Invoice, Receipt
from billing.services import invoice_for_order, receipt_for_payment
from catalog.models import Category, Product
from credit.models import CreditAccount, CreditLedgerEntry, Statement
from credit.statement_services import close_billing_cycles, close_cycles_for_account
from orders.models import Order, OrderItem, OrderStatus
from payments.models import Payment


class InvoiceProducerTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919005500001", role="customer")
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        product = Product.objects.create(
            name="Rice", price=Decimal("100"), mrp=Decimal("120"), category=cat)
        self.order = Order.objects.create(
            user=self.user, status=OrderStatus.DELIVERED,
            subtotal=Decimal("200"), gst=Decimal("36"), total=Decimal("236"))
        OrderItem.objects.create(
            order=self.order, product=product, name="Rice",
            quantity=2, price=Decimal("100"), mrp=Decimal("120"))

    def test_invoice_row_is_created_with_items(self):
        invoice = invoice_for_order(self.order)
        self.assertEqual(invoice.status, Invoice.Status.ISSUED)
        self.assertEqual(invoice.amount, Decimal("236"))
        self.assertEqual(invoice.gst, Decimal("36"))
        self.assertEqual(invoice.items.count(), 1)
        self.assertTrue(invoice.number.startswith("INV"))

    def test_idempotent_per_order(self):
        first = invoice_for_order(self.order)
        again = invoice_for_order(self.order)
        self.assertEqual(first.pk, again.pk)
        self.assertEqual(Invoice.objects.filter(order=self.order).count(), 1)


class ReceiptProducerTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919005500002", role="customer")
        self.payment = Payment.objects.create(
            user=self.user, purpose="repayment", amount=Decimal("500"),
            method="upi", status=Payment.Status.SUCCESS)

    def test_receipt_row_is_created(self):
        receipt = receipt_for_payment(self.payment)
        self.assertEqual(receipt.amount, Decimal("500"))
        self.assertEqual(receipt.method, "upi")
        self.assertTrue(receipt.number.startswith("RCP"))

    def test_idempotent_per_payment(self):
        first = receipt_for_payment(self.payment)
        again = receipt_for_payment(self.payment)
        self.assertEqual(first.pk, again.pk)


class StatementGenerationTests(TestCase):
    """The billing-cycle closer. Windows are complete calendar cycles; the run is
    idempotent; overdue statements age."""

    def setUp(self):
        self.user = User.objects.create(phone="+919005500003", role="customer")
        self.account = CreditAccount.objects.create(
            user=self.user, credit_limit=Decimal("10000"))

    def _entry(self, type_, amount, when: date):
        entry = CreditLedgerEntry.objects.create(
            account=self.account, type=type_, amount=Decimal(amount),
            balance_after=Decimal("0"))
        # created_at is auto_now_add — backdate it for window math.
        CreditLedgerEntry.objects.filter(pk=entry.pk).update(
            created_at=f"{when.isoformat()}T10:00:00+05:30")
        return entry

    def test_closes_a_complete_month_with_correct_rollup(self):
        self._entry("purchase", "1000", date(2026, 6, 5))
        self._entry("repayment", "-400", date(2026, 6, 20))

        created = close_cycles_for_account(self.account, today=date(2026, 7, 22))

        self.assertEqual(len(created), 1)
        s = created[0]
        self.assertEqual((s.period_start, s.period_end),
                         (date(2026, 6, 1), date(2026, 6, 30)))
        self.assertEqual(s.purchases, Decimal("1000"))
        self.assertEqual(s.payments, Decimal("400"))
        self.assertEqual(s.closing_balance, Decimal("600"))
        self.assertEqual(s.status, Statement.Status.OPEN)
        self.assertEqual(s.due_date, date(2026, 6, 30) + timedelta(days=10))

    def test_idempotent_rerun_creates_nothing_new(self):
        self._entry("purchase", "1000", date(2026, 6, 5))
        close_cycles_for_account(self.account, today=date(2026, 7, 22))
        again = close_cycles_for_account(self.account, today=date(2026, 7, 22))
        self.assertEqual(again, [])
        self.assertEqual(self.account.statements.count(), 1)

    def test_incomplete_current_window_is_not_billed(self):
        self._entry("purchase", "1000", date(2026, 7, 10))
        created = close_cycles_for_account(self.account, today=date(2026, 7, 22))
        self.assertEqual(created, [])

    def test_carried_balance_spawns_a_statement_even_without_new_activity(self):
        """Money owed must keep appearing on paper until it is paid."""
        self._entry("purchase", "1000", date(2026, 5, 5))
        created = close_cycles_for_account(self.account, today=date(2026, 7, 22))
        # May (activity) and June (carried 1000, no activity).
        self.assertEqual(len(created), 2)
        june = created[1]
        self.assertEqual(june.opening_balance, Decimal("1000"))
        self.assertEqual(june.closing_balance, Decimal("1000"))

    def test_fully_paid_window_closes_as_paid(self):
        self._entry("purchase", "1000", date(2026, 6, 5))
        self._entry("repayment", "-1000", date(2026, 6, 25))
        created = close_cycles_for_account(self.account, today=date(2026, 7, 22))
        self.assertEqual(created[0].status, Statement.Status.PAID)

    def test_overdue_marking_ages_the_book(self):
        self._entry("purchase", "1000", date(2026, 5, 5))
        result = close_billing_cycles(today=date(2026, 7, 22))
        self.assertGreaterEqual(result["statements"], 1)
        # May's due date (Jun 9) is long past → overdue.
        self.assertTrue(Statement.objects.filter(
            account=self.account, status=Statement.Status.OVERDUE).exists())

    def test_weekly_cycle_uses_weekly_windows(self):
        self.account.billing_cycle = CreditAccount.BillingCycle.WEEKLY
        self.account.save(update_fields=["billing_cycle"])
        self._entry("purchase", "700", date(2026, 7, 7))  # Tue of week Jul 6–12

        created = close_cycles_for_account(self.account, today=date(2026, 7, 22))

        self.assertGreaterEqual(len(created), 1)
        first = created[0]
        self.assertEqual((first.period_start, first.period_end),
                         (date(2026, 7, 6), date(2026, 7, 12)))
        self.assertEqual(first.due_date, date(2026, 7, 12) + timedelta(days=5))
