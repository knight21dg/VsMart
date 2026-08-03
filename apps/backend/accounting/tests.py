"""General ledger: the invariants that make it auditable.

Debits equal credits, posted entries are immutable, source postings are
idempotent, and the reports are derived from the journal rather than guessed.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User

from .chart import seed
from .models import Account, JournalEntry
from .services import (
    account_ledger,
    balance_sheet,
    post_entry,
    profit_and_loss,
    reverse_entry,
    trial_balance,
)


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


class LedgerCoreTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        seed()

    def setUp(self):
        self.today = date(2026, 7, 1)

    def _sale(self, amount="1000", when=None):
        return post_entry(
            entry_date=when or self.today,
            narration="Cash sale",
            lines=[
                {"account": "1000", "debit": amount},
                {"account": "4000", "credit": amount},
            ],
        )

    # ── the balancing invariant ──
    def test_a_balanced_entry_posts(self):
        entry = self._sale()
        self.assertEqual(entry.status, JournalEntry.Status.POSTED)
        self.assertTrue(entry.is_balanced)
        self.assertEqual(entry.lines.count(), 2)

    def test_an_unbalanced_entry_is_refused(self):
        with self.assertRaises(Exception):
            post_entry(
                entry_date=self.today, narration="Bad",
                lines=[
                    {"account": "1000", "debit": "1000"},
                    {"account": "4000", "credit": "900"},
                ],
            )
        self.assertEqual(JournalEntry.objects.count(), 0)

    def test_a_line_cannot_be_both_debit_and_credit(self):
        with self.assertRaises(Exception):
            post_entry(
                entry_date=self.today, narration="Bad",
                lines=[
                    {"account": "1000", "debit": "100", "credit": "100"},
                    {"account": "4000", "credit": "100"},
                ],
            )

    def test_a_single_line_entry_is_refused(self):
        with self.assertRaises(Exception):
            post_entry(entry_date=self.today, narration="Half",
                       lines=[{"account": "1000", "debit": "100"}])

    def test_a_zero_entry_is_refused(self):
        with self.assertRaises(Exception):
            post_entry(
                entry_date=self.today, narration="Nothing",
                lines=[
                    {"account": "1000", "debit": "0"},
                    {"account": "4000", "credit": "0"},
                ],
            )

    def test_an_unknown_account_is_refused(self):
        with self.assertRaises(Exception):
            post_entry(
                entry_date=self.today, narration="Ghost",
                lines=[
                    {"account": "9999", "debit": "100"},
                    {"account": "4000", "credit": "100"},
                ],
            )

    def test_an_archived_account_cannot_be_posted_to(self):
        Account.objects.filter(code="4900").update(is_active=False)
        with self.assertRaises(Exception):
            post_entry(
                entry_date=self.today, narration="Archived",
                lines=[
                    {"account": "1000", "debit": "100"},
                    {"account": "4900", "credit": "100"},
                ],
            )

    # ── idempotency ──
    def test_the_same_source_posts_once(self):
        """A retried webhook must not book the money twice."""
        first = post_entry(
            entry_date=self.today, narration="Payment 7",
            source_module="payment", source_ref=7,
            lines=[{"account": "1100", "debit": "500"},
                   {"account": "4000", "credit": "500"}],
        )
        second = post_entry(
            entry_date=self.today, narration="Payment 7 again",
            source_module="payment", source_ref=7,
            lines=[{"account": "1100", "debit": "500"},
                   {"account": "4000", "credit": "500"}],
        )
        self.assertEqual(first.id, second.id)
        self.assertEqual(JournalEntry.objects.count(), 1)

    def test_different_sources_both_post(self):
        post_entry(entry_date=self.today, narration="A",
                   source_module="payment", source_ref=1,
                   lines=[{"account": "1100", "debit": "10"},
                          {"account": "4000", "credit": "10"}])
        post_entry(entry_date=self.today, narration="B",
                   source_module="payment", source_ref=2,
                   lines=[{"account": "1100", "debit": "10"},
                          {"account": "4000", "credit": "10"}])
        self.assertEqual(JournalEntry.objects.count(), 2)

    def test_manual_entries_are_not_deduplicated(self):
        """Two identical manual entries are two real transactions."""
        self._sale()
        self._sale()
        self.assertEqual(JournalEntry.objects.count(), 2)

    # ── immutability / reversal ──
    def test_reversal_mirrors_the_original_and_nets_to_zero(self):
        entry = self._sale("1000")
        reversal = reverse_entry(entry, reason="Booked in error")

        entry.refresh_from_db()
        self.assertEqual(entry.status, JournalEntry.Status.REVERSED)
        self.assertEqual(reversal.reverses_id, entry.id)

        cash = Account.objects.get(code="1000")
        # Original excluded (REVERSED), reversal included (POSTED).
        self.assertEqual(account_ledger(cash)["closing"], Decimal("-1000.00"))

    def test_an_entry_cannot_be_reversed_twice(self):
        entry = self._sale()
        reverse_entry(entry)
        entry.refresh_from_db()
        with self.assertRaises(Exception):
            reverse_entry(entry)

    # ── trial balance ──
    def test_trial_balance_always_balances(self):
        self._sale("1000")
        self._sale("250")
        post_entry(entry_date=self.today, narration="Rent",
                   lines=[{"account": "5500", "debit": "300"},
                          {"account": "1100", "credit": "300"}])
        tb = trial_balance()
        self.assertTrue(tb["balanced"], tb)
        self.assertEqual(tb["totalDebit"], tb["totalCredit"])

    def test_trial_balance_respects_as_of(self):
        self._sale("1000", when=date(2026, 6, 1))
        self._sale("500", when=date(2026, 7, 15))
        tb = trial_balance(as_of=date(2026, 6, 30))
        cash = next(r for r in tb["rows"] if r["code"] == "1000")
        self.assertEqual(cash["debit"], Decimal("1000.00"))

    # ── reports ──
    def test_profit_and_loss_is_income_less_expenses(self):
        self._sale("1000")
        post_entry(entry_date=self.today, narration="Salaries",
                   lines=[{"account": "5400", "debit": "400"},
                          {"account": "1100", "credit": "400"}])
        pnl = profit_and_loss()
        self.assertEqual(pnl["totalIncome"], Decimal("1000.00"))
        self.assertEqual(pnl["totalExpenses"], Decimal("400.00"))
        self.assertEqual(pnl["netProfit"], Decimal("600.00"))

    def test_profit_and_loss_windows_by_date(self):
        self._sale("1000", when=date(2026, 6, 1))
        self._sale("500", when=date(2026, 7, 1))
        pnl = profit_and_loss(date_from=date(2026, 7, 1), date_to=date(2026, 7, 31))
        self.assertEqual(pnl["totalIncome"], Decimal("500.00"))

    def test_balance_sheet_balances_with_retained_earnings(self):
        """Assets == liabilities + equity + this period's profit."""
        post_entry(entry_date=self.today, narration="Capital",
                   lines=[{"account": "1100", "debit": "5000"},
                          {"account": "3000", "credit": "5000"}])
        self._sale("1000")
        bs = balance_sheet()
        self.assertEqual(bs["totalAssets"], Decimal("6000.00"))
        self.assertEqual(bs["retainedEarnings"], Decimal("1000.00"))
        self.assertTrue(bs["balanced"], bs)

    def test_account_ledger_runs_a_balance(self):
        self._sale("100")
        self._sale("250")
        cash = Account.objects.get(code="1000")
        led = account_ledger(cash)
        self.assertEqual([r["balance"] for r in led["rows"]],
                         [Decimal("100.00"), Decimal("350.00")])
        self.assertEqual(led["closing"], Decimal("350.00"))

    def test_account_ledger_opening_balance_from_prior_period(self):
        self._sale("100", when=date(2026, 6, 1))
        self._sale("50", when=date(2026, 7, 1))
        cash = Account.objects.get(code="1000")
        led = account_ledger(cash, date_from=date(2026, 7, 1))
        self.assertEqual(led["opening"], Decimal("100.00"))
        self.assertEqual(led["closing"], Decimal("150.00"))


class ChartSeedTests(TestCase):
    def test_seed_is_idempotent(self):
        first = seed()
        self.assertGreater(first, 0)
        self.assertEqual(seed(), 0)

    def test_account_types_have_the_right_normal_side(self):
        seed()
        self.assertTrue(Account.objects.get(code="1000").is_debit_normal)   # asset
        self.assertTrue(Account.objects.get(code="5400").is_debit_normal)   # expense
        self.assertFalse(Account.objects.get(code="4000").is_debit_normal)  # income
        self.assertFalse(Account.objects.get(code="2000").is_debit_normal)  # liability


class LedgerApiTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        seed()

    def setUp(self):
        self.admin = User.objects.create(phone="+919000004001", name="Fin",
                                         role="admin")
        self.customer = User.objects.create(phone="+919000004002", name="Cust",
                                            role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_customers_cannot_reach_the_ledger(self):
        c = APIClient()
        c.force_authenticate(self.customer)
        for url in ("/api/v1/admin/accounting/accounts",
                    "/api/v1/admin/accounting/journal",
                    "/api/v1/admin/accounting/trial-balance",
                    "/api/v1/admin/accounting/pnl",
                    "/api/v1/admin/accounting/balance-sheet"):
            self.assertEqual(c.get(url).status_code, 403, url)

    def test_posting_a_balanced_entry_through_the_api(self):
        r = self.client.post("/api/v1/admin/accounting/journal/post", {
            "entryDate": "2026-07-01",
            "narration": "Owner capital",
            "lines": [
                {"accountCode": "1100", "debit": "5000"},
                {"accountCode": "3000", "credit": "5000"},
            ],
        }, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        self.assertEqual(JournalEntry.objects.count(), 1)

    def test_the_api_refuses_an_unbalanced_entry(self):
        r = self.client.post("/api/v1/admin/accounting/journal/post", {
            "entryDate": "2026-07-01",
            "narration": "Wrong",
            "lines": [
                {"accountCode": "1100", "debit": "5000"},
                {"accountCode": "3000", "credit": "4000"},
            ],
        }, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "GL_UNBALANCED")

    def test_reversal_through_the_api(self):
        entry = post_entry(
            entry_date=date(2026, 7, 1), narration="Sale",
            lines=[{"account": "1000", "debit": "100"},
                   {"account": "4000", "credit": "100"}],
        )
        r = self.client.post(
            f"/api/v1/admin/accounting/journal/{entry.id}/reverse",
            {"reason": "Duplicate"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        entry.refresh_from_db()
        self.assertEqual(entry.status, JournalEntry.Status.REVERSED)

    def test_reports_render(self):
        post_entry(entry_date=date(2026, 7, 1), narration="Sale",
                   lines=[{"account": "1000", "debit": "100"},
                          {"account": "4000", "credit": "100"}])
        tb = _data(self.client.get("/api/v1/admin/accounting/trial-balance"))
        self.assertTrue(tb["balanced"])
        pnl = _data(self.client.get("/api/v1/admin/accounting/pnl"))
        self.assertEqual(Decimal(str(pnl["netProfit"])), Decimal("100.00"))
        bs = _data(self.client.get("/api/v1/admin/accounting/balance-sheet"))
        self.assertTrue(bs["balanced"])


class AutoPostingTests(TestCase):
    """Real money events must land in the ledger without anyone remembering to."""

    @classmethod
    def setUpTestData(cls):
        seed()

    def setUp(self):
        self.agent = User.objects.create(phone="+919000004010", name="Ravi",
                                         role="agent")
        self.admin = User.objects.create(phone="+919000004011", name="Fin",
                                         role="admin")

    def test_a_verified_cash_deposit_is_booked(self):
        from payments.cashbook_services import create_deposit, verify_deposit

        deposit = create_deposit(self.agent, amount="500", method="bank")
        verify_deposit(deposit, self.admin, counted_amount="500")

        entry = JournalEntry.objects.get(source_module="cash_deposit")
        self.assertTrue(entry.is_balanced)
        codes = {line.account.code for line in entry.lines.all()}
        self.assertEqual(codes, {"1100", "1010"})   # bank in, agent cash out

    def test_a_short_deposit_books_the_shortfall_as_an_expense(self):
        from payments.cashbook_services import create_deposit, verify_deposit

        deposit = create_deposit(self.agent, amount="500", method="bank")
        verify_deposit(deposit, self.admin, counted_amount="450")

        entry = JournalEntry.objects.get(source_module="cash_deposit")
        self.assertTrue(entry.is_balanced)
        by_code = {line.account.code: line for line in entry.lines.all()}
        self.assertEqual(by_code["1100"].debit, Decimal("450.00"))
        self.assertEqual(by_code["5600"].debit, Decimal("50.00"))   # shortage
        self.assertEqual(by_code["1010"].credit, Decimal("500.00"))

    def test_a_ledger_failure_never_breaks_the_business_action(self):
        """Bookkeeping is fail-soft: a counted deposit stays counted even if the
        chart of accounts is missing."""
        from payments.cashbook_services import create_deposit, verify_deposit
        from payments.models import CashDeposit

        Account.objects.all().delete()
        deposit = create_deposit(self.agent, amount="500", method="bank")
        verify_deposit(deposit, self.admin, counted_amount="500")

        deposit.refresh_from_db()
        self.assertEqual(deposit.status, CashDeposit.Status.VERIFIED)
        self.assertEqual(JournalEntry.objects.count(), 0)

    def test_supplier_invoice_and_payment_are_booked(self):
        from inventory.ap_services import approve_invoice, record_payment
        from inventory.models import PurchaseInvoice, Supplier

        supplier = Supplier.objects.create(name="Acme Foods")
        invoice = PurchaseInvoice.objects.create(
            supplier=supplier, invoice_number="INV-1",
            invoice_date=date(2026, 7, 1),
            subtotal=Decimal("1000"), tax=Decimal("50"), total=Decimal("1050"),
        )
        approve_invoice(invoice, self.admin)

        booked = JournalEntry.objects.get(source_module="purchase_invoice")
        self.assertTrue(booked.is_balanced)
        by_code = {line.account.code: line for line in booked.lines.all()}
        self.assertEqual(by_code["1300"].debit, Decimal("1000.00"))   # inventory
        self.assertEqual(by_code["1400"].debit, Decimal("50.00"))     # GST input
        self.assertEqual(by_code["2000"].credit, Decimal("1050.00"))  # payable

        record_payment(invoice, amount="1050", method="bank", actor=self.admin)
        paid = JournalEntry.objects.get(source_module="vendor_payment")
        self.assertTrue(paid.is_balanced)
        by_code = {line.account.code: line for line in paid.lines.all()}
        self.assertEqual(by_code["2000"].debit, Decimal("1050.00"))
        self.assertEqual(by_code["1100"].credit, Decimal("1050.00"))

    def test_a_draft_invoice_is_not_a_liability_yet(self):
        from inventory.models import PurchaseInvoice, Supplier

        supplier = Supplier.objects.create(name="Draft Co")
        PurchaseInvoice.objects.create(
            supplier=supplier, invoice_number="INV-2",
            invoice_date=date(2026, 7, 1),
            subtotal=Decimal("100"), total=Decimal("100"),
        )
        self.assertFalse(
            JournalEntry.objects.filter(source_module="purchase_invoice").exists()
        )

    def test_the_ledger_still_balances_after_real_events(self):
        from inventory.ap_services import approve_invoice, record_payment
        from inventory.models import PurchaseInvoice, Supplier
        from payments.cashbook_services import create_deposit, verify_deposit

        deposit = create_deposit(self.agent, amount="800", method="bank")
        verify_deposit(deposit, self.admin, counted_amount="780")

        supplier = Supplier.objects.create(name="Acme")
        invoice = PurchaseInvoice.objects.create(
            supplier=supplier, invoice_number="INV-9",
            invoice_date=date(2026, 7, 1),
            subtotal=Decimal("500"), tax=Decimal("25"), total=Decimal("525"),
        )
        approve_invoice(invoice, self.admin)
        record_payment(invoice, amount="525", method="bank", actor=self.admin)

        tb = trial_balance()
        self.assertTrue(tb["balanced"], tb)


class LedgerDateWindowTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        seed()

    def test_future_dated_entries_are_excluded_from_an_as_of_report(self):
        today = date(2026, 7, 1)
        post_entry(entry_date=today, narration="Now",
                   lines=[{"account": "1000", "debit": "100"},
                          {"account": "4000", "credit": "100"}])
        post_entry(entry_date=today + timedelta(days=40), narration="Later",
                   lines=[{"account": "1000", "debit": "900"},
                          {"account": "4000", "credit": "900"}])
        pnl = profit_and_loss(date_to=today)
        self.assertEqual(pnl["totalIncome"], Decimal("100.00"))
