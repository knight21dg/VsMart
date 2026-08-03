"""VS Credit ledger integrity (Sprint 7): the credit limit can never be exceeded
(even under concurrent purchases), Outstanding == Σ ledger, and the ledger is
append-only. The account had no automated tests before this."""
from decimal import Decimal

from django.db.models import Sum
from django.test import TestCase

from accounts.models import User

from .models import CreditAccount, CreditLedgerEntry
from .services import (
    CreditError,
    apply_refund,
    apply_repayment,
    debit_purchase,
    ensure_account,
    reconcile,
)


class CreditLedgerTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(
            phone="+919000000500", name="Cr",
            kyc_status="verified", credit_enabled=True,
        )
        self.account = ensure_account(self.user)
        self.account.credit_limit = Decimal("1000")
        self.account.save(update_fields=["credit_limit"])

    def _outstanding(self):
        self.account.refresh_from_db()
        return self.account.outstanding

    # ── the P0: limit enforced under the lock ──
    def test_purchase_cannot_exceed_limit(self):
        debit_purchase(self.account, Decimal("800"))
        # The second 800 would push outstanding to 1600 > 1000 — rejected under the
        # account row lock even though the pre-lock check sees a stale balance.
        with self.assertRaises(CreditError):
            debit_purchase(self.account, Decimal("800"))
        self.assertEqual(self._outstanding(), Decimal("800"))
        self.assertEqual(self.account.available, Decimal("200"))

    def test_available_never_negative(self):
        debit_purchase(self.account, Decimal("1000"))  # exactly at the limit
        self.account.refresh_from_db()
        self.assertEqual(self.account.available, Decimal("0"))
        with self.assertRaises(CreditError):
            debit_purchase(self.account, Decimal("1"))  # over by one rupee

    # ── invariant: Outstanding == Purchases − Repayments ──
    def test_outstanding_equals_purchases_minus_repayments(self):
        debit_purchase(self.account, Decimal("800"))
        apply_repayment(self.account, Decimal("300"))
        self.assertEqual(self._outstanding(), Decimal("500"))
        ledger_sum = self.account.entries.aggregate(s=Sum("amount"))["s"]
        self.assertEqual(self._outstanding(), ledger_sum)  # cache == Σ ledger

    def test_refund_decreases_outstanding_and_writes_ledger(self):
        debit_purchase(self.account, Decimal("800"))
        apply_refund(self.account, Decimal("200"))
        self.assertEqual(self._outstanding(), Decimal("600"))
        self.assertEqual(self.account.available, Decimal("400"))
        self.assertTrue(
            self.account.entries.filter(type=CreditLedgerEntry.Type.REFUND).exists())

    def test_overpayment_clamps_outstanding_at_zero(self):
        debit_purchase(self.account, Decimal("300"))
        apply_repayment(self.account, Decimal("500"))  # repay more than owed
        self.assertEqual(self._outstanding(), Decimal("0"))  # never negative

    # ── append-only ledger ──
    def test_ledger_is_append_only(self):
        entry = debit_purchase(self.account, Decimal("100"))
        entry.amount = Decimal("999")
        with self.assertRaises(ValueError):
            entry.save()
        with self.assertRaises(ValueError):
            entry.delete()

    def test_reconcile_rebuilds_outstanding_from_ledger(self):
        debit_purchase(self.account, Decimal("400"))
        apply_repayment(self.account, Decimal("100"))
        CreditAccount.objects.filter(pk=self.account.pk).update(
            outstanding=Decimal("9999"))  # corrupt the cache
        self.account.refresh_from_db()
        self.assertEqual(reconcile(self.account), Decimal("300"))
        self.account.refresh_from_db()
        self.assertEqual(self.account.outstanding, Decimal("300"))

    def test_ineligible_user_cannot_purchase(self):
        self.user.kyc_status = "pending"
        self.user.save(update_fields=["kyc_status"])
        with self.assertRaises(CreditError):
            debit_purchase(self.account, Decimal("100"))
