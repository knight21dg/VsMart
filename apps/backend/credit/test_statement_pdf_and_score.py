"""Statement PDF generation + the VS-score factor computation."""
from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User

from .models import CreditAccount, CreditLedgerEntry, Statement
from .views import _score_factors


class StatementPdfTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919003300001", name="Dev Kumar", role="customer")
        self.account = CreditAccount.objects.create(
            user=self.user, credit_limit=Decimal("10000"),
            outstanding=Decimal("2000"))
        today = date(2026, 7, 1)
        self.statement = Statement.objects.create(
            account=self.account, opening_balance=Decimal("0"),
            purchases=Decimal("2000"), payments=Decimal("0"),
            closing_balance=Decimal("2000"),
            period_start=today, period_end=date(2026, 7, 31),
            due_date=date(2026, 8, 10))
        self.client = APIClient()
        self.client.force_authenticate(self.user)

    def test_pdf_endpoint_returns_a_pdf(self):
        r = self.client.get(f"/api/v1/credit/statements/{self.statement.pk}/pdf")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "application/pdf")
        body = b"".join(r.streaming_content) if r.streaming else r.content
        self.assertTrue(body.startswith(b"%PDF"))

    def test_builder_produces_nonempty_bytes(self):
        from .statement_pdf import build_statement_pdf

        pdf = build_statement_pdf(self.statement)
        self.assertTrue(pdf.startswith(b"%PDF"))
        self.assertGreater(len(pdf), 800)

    def test_another_users_statement_is_not_downloadable(self):
        other = User.objects.create(phone="+919003300002", role="customer")
        self.client.force_authenticate(other)
        r = self.client.get(f"/api/v1/credit/statements/{self.statement.pk}/pdf")
        self.assertEqual(r.status_code, 404)


class ScoreFactorTests(TestCase):
    """The factors used to be hardcoded good/fair/good for everyone. They must now
    reflect the account."""

    def _account(self, *, limit="10000", outstanding="0", age_days=200):
        user = User.objects.create(
            phone=f"+9190044{age_days:05d}"[:13], role="customer")
        account = CreditAccount.objects.create(
            user=user, credit_limit=Decimal(limit),
            outstanding=Decimal(outstanding))
        # Back-date creation to exercise the age factor (created_at is auto_now_add).
        CreditAccount.objects.filter(pk=account.pk).update(
            created_at=timezone.now() - timedelta(days=age_days))
        return CreditAccount.objects.get(pk=account.pk)

    def _factor(self, factors, label):
        return next(f["status"] for f in factors if f["label"] == label)

    def test_low_utilization_scores_good(self):
        acc = self._account(limit="10000", outstanding="1000")  # 10%
        self.assertEqual(
            self._factor(_score_factors(acc), "Credit utilization"), "good")

    def test_high_utilization_scores_poor(self):
        acc = self._account(limit="10000", outstanding="9000")  # 90%
        self.assertEqual(
            self._factor(_score_factors(acc), "Credit utilization"), "poor")

    def test_young_account_scores_poor_on_age(self):
        acc = self._account(age_days=10)
        self.assertEqual(
            self._factor(_score_factors(acc), "Account age"), "poor")

    def test_established_account_scores_good_on_age(self):
        acc = self._account(age_days=400)
        self.assertEqual(
            self._factor(_score_factors(acc), "Account age"), "good")

    def test_overdue_statements_drag_repayment_history_down(self):
        acc = self._account()
        Statement.objects.create(
            account=acc, closing_balance=Decimal("0"),
            period_start=date(2026, 1, 1), period_end=date(2026, 1, 31),
            due_date=date(2026, 2, 10), status=Statement.Status.OVERDUE)
        self.assertEqual(
            self._factor(_score_factors(acc), "Repayment history"), "poor")

    def test_all_paid_scores_repayment_history_good(self):
        acc = self._account()
        Statement.objects.create(
            account=acc, closing_balance=Decimal("0"),
            period_start=date(2026, 1, 1), period_end=date(2026, 1, 31),
            due_date=date(2026, 2, 10), status=Statement.Status.PAID)
        self.assertEqual(
            self._factor(_score_factors(acc), "Repayment history"), "good")

    def test_no_history_is_neutral_not_good(self):
        acc = self._account()
        self.assertEqual(
            self._factor(_score_factors(acc), "Repayment history"), "fair")
