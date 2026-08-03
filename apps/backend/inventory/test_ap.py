"""Accounts payable: supplier invoices, vendor payments, payables aging.

Before this the procurement loop had no closing end — stock could be received
but the liability was never recorded, so there was no payables balance at all.
"""
from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User

from .ap_services import payables_aging, record_payment
from .models import PurchaseInvoice, Supplier


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


class AccountsPayableTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919000002001", name="Fin", role="admin")
        self.staff = APIClient()
        self.staff.force_authenticate(self.admin)
        self.supplier = Supplier.objects.create(name="Acme Foods")
        self.today = timezone.localdate()

    def _invoice(self, total="1000", number="INV-1", due_days=30, status=None):
        inv = PurchaseInvoice.objects.create(
            supplier=self.supplier, invoice_number=number,
            invoice_date=self.today, due_date=self.today + timedelta(days=due_days),
            subtotal=Decimal(total), total=Decimal(total),
            status=status or PurchaseInvoice.Status.AWAITING,
        )
        return inv

    def _pay(self, inv, amount, **body):
        return self.staff.post(
            f"/api/v1/admin/procurement/invoices/{inv.id}/payments",
            {"amount": amount, "method": "bank", **body}, format="json",
        )

    # ── creation ──
    def test_create_invoice_via_api(self):
        r = self.staff.post("/api/v1/admin/procurement/invoices", {
            "supplierId": self.supplier.id, "invoiceNumber": "INV-9",
            "invoiceDate": self.today.isoformat(), "total": "500", "subtotal": "500",
        }, format="json")
        self.assertEqual(r.status_code, 201, r.json())
        self.assertEqual(PurchaseInvoice.objects.get().status,
                         PurchaseInvoice.Status.DRAFT)

    def test_the_same_supplier_bill_cannot_be_entered_twice(self):
        """Otherwise the same invoice gets paid twice."""
        self._invoice(number="DUP-1")
        with self.assertRaises(Exception):
            self._invoice(number="DUP-1")

    def test_a_zero_total_invoice_is_refused(self):
        r = self.staff.post("/api/v1/admin/procurement/invoices", {
            "supplierId": self.supplier.id, "invoiceNumber": "INV-0",
            "invoiceDate": self.today.isoformat(), "total": "0", "subtotal": "0",
        }, format="json")
        self.assertEqual(r.status_code, 400)

    def test_due_date_cannot_precede_the_invoice_date(self):
        r = self.staff.post("/api/v1/admin/procurement/invoices", {
            "supplierId": self.supplier.id, "invoiceNumber": "INV-B",
            "invoiceDate": self.today.isoformat(),
            "dueDate": (self.today - timedelta(days=1)).isoformat(),
            "total": "100", "subtotal": "100",
        }, format="json")
        self.assertEqual(r.status_code, 400)

    # ── payment ──
    def test_partial_payment_moves_the_balance_and_status(self):
        inv = self._invoice(total="1000")
        r = self._pay(inv, "400")
        self.assertEqual(r.status_code, 201, r.json())
        inv.refresh_from_db()
        self.assertEqual(inv.amount_paid, Decimal("400"))
        self.assertEqual(inv.balance_due, Decimal("600"))
        self.assertEqual(inv.status, PurchaseInvoice.Status.PARTIAL)

    def test_paying_the_balance_marks_it_paid(self):
        inv = self._invoice(total="1000")
        self._pay(inv, "1000")
        inv.refresh_from_db()
        self.assertEqual(inv.status, PurchaseInvoice.Status.PAID)
        self.assertEqual(inv.balance_due, Decimal("0"))

    def test_overpayment_is_refused(self):
        """A negative balance reads as a credit note nobody issued."""
        inv = self._invoice(total="1000")
        self._pay(inv, "800")
        r = self._pay(inv, "300")
        self.assertEqual(r.status_code, 400)
        inv.refresh_from_db()
        self.assertEqual(inv.amount_paid, Decimal("800"))

    def test_a_draft_invoice_cannot_be_paid(self):
        inv = self._invoice(status=PurchaseInvoice.Status.DRAFT)
        self.assertEqual(self._pay(inv, "100").status_code, 409)

    def test_a_cancelled_invoice_cannot_be_paid(self):
        inv = self._invoice(status=PurchaseInvoice.Status.CANCELLED)
        self.assertEqual(self._pay(inv, "100").status_code, 409)

    def test_zero_or_negative_payment_is_refused(self):
        inv = self._invoice()
        self.assertEqual(self._pay(inv, "0").status_code, 400)
        self.assertEqual(self._pay(inv, "-50").status_code, 400)

    # ── transitions ──
    def test_approve_moves_draft_into_payables(self):
        inv = self._invoice(status=PurchaseInvoice.Status.DRAFT)
        r = self.staff.post(
            f"/api/v1/admin/procurement/invoices/{inv.id}/approve", {}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        inv.refresh_from_db()
        self.assertEqual(inv.status, PurchaseInvoice.Status.AWAITING)

    def test_cannot_cancel_an_invoice_that_has_been_paid(self):
        """The payment really happened — correct it with a credit note, don't erase it."""
        inv = self._invoice()
        self._pay(inv, "100")
        r = self.staff.post(
            f"/api/v1/admin/procurement/invoices/{inv.id}/cancel", {}, format="json")
        self.assertEqual(r.status_code, 409)

    # ── aging ──
    def test_aging_buckets_by_days_past_due(self):
        self._invoice(total="100", number="A", due_days=30)      # current
        self._invoice(total="200", number="B", due_days=-10)     # 1-30
        self._invoice(total="300", number="C", due_days=-45)     # 31-60
        self._invoice(total="400", number="D", due_days=-120)    # 90+
        aging = payables_aging()
        buckets = {b["bucket"]: b["amount"] for b in aging["buckets"]}
        self.assertEqual(buckets["current"], Decimal("100"))
        self.assertEqual(buckets["1-30"], Decimal("200"))
        self.assertEqual(buckets["31-60"], Decimal("300"))
        self.assertEqual(buckets["90+"], Decimal("400"))
        self.assertEqual(aging["totalOutstanding"], Decimal("1000"))

    def test_aging_counts_only_the_unpaid_balance(self):
        inv = self._invoice(total="1000", due_days=-5)
        record_payment(inv, amount=Decimal("600"), method="bank")
        self.assertEqual(payables_aging()["totalOutstanding"], Decimal("400"))

    def test_paid_and_cancelled_invoices_drop_out_of_payables(self):
        inv = self._invoice(total="100")
        record_payment(inv, amount=Decimal("100"), method="cash")
        self._invoice(total="500", number="X",
                      status=PurchaseInvoice.Status.CANCELLED)
        self.assertEqual(payables_aging()["totalOutstanding"], Decimal("0"))

    def test_an_invoice_with_no_due_date_still_counts_as_owed(self):
        """Otherwise money owed silently vanishes from the total."""
        PurchaseInvoice.objects.create(
            supplier=self.supplier, invoice_number="NODUE",
            invoice_date=self.today, total=Decimal("250"), subtotal=Decimal("250"),
            status=PurchaseInvoice.Status.AWAITING,
        )
        aging = payables_aging()
        self.assertEqual(aging["totalOutstanding"], Decimal("250"))
        buckets = {b["bucket"]: b["amount"] for b in aging["buckets"]}
        self.assertEqual(buckets["current"], Decimal("250"))

    def test_aging_groups_by_supplier(self):
        other = Supplier.objects.create(name="Beta Traders")
        self._invoice(total="100", number="S1")
        PurchaseInvoice.objects.create(
            supplier=other, invoice_number="S2", invoice_date=self.today,
            total=Decimal("900"), subtotal=Decimal("900"),
            status=PurchaseInvoice.Status.AWAITING,
        )
        rows = payables_aging()["bySupplier"]
        self.assertEqual(rows[0]["supplier"], "Beta Traders")   # largest first
        self.assertEqual(rows[0]["amount"], Decimal("900"))

    # ── detail + access ──
    def test_detail_includes_payment_history(self):
        inv = self._invoice()
        self._pay(inv, "250", reference="UTR123")
        data = _data(self.staff.get(f"/api/v1/admin/procurement/invoices/{inv.id}"))
        self.assertEqual(len(data["payments"]), 1)
        self.assertEqual(data["payments"][0]["reference"], "UTR123")

    def test_customers_cannot_touch_payables(self):
        customer = User.objects.create(phone="+919000002002", name="C", role="customer")
        c = APIClient()
        c.force_authenticate(customer)
        inv = self._invoice()
        self.assertEqual(c.get("/api/v1/admin/procurement/invoices").status_code, 403)
        self.assertEqual(c.get("/api/v1/admin/procurement/payables").status_code, 403)
        self.assertEqual(
            c.post(f"/api/v1/admin/procurement/invoices/{inv.id}/payments",
                   {"amount": "1", "method": "cash"}, format="json").status_code, 403)
