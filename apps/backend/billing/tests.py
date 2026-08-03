import tempfile
from decimal import Decimal

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from accounts.models import User

from .models import Invoice, InvoiceItem
from .services import generate_invoice_pdf

TMP_MEDIA = tempfile.mkdtemp(prefix="vsmart-inv-")

PDF_BYTES = b"%PDF-1.4 fake invoice pdf\n%%EOF\n"


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class InvoicePdfServingTests(TestCase):
    """Invoice PDFs are served only behind an ownership/staff gate, never on a
    guessable unauthenticated path."""

    def setUp(self):
        self.owner = User.objects.create(phone="+919000300301", name="Owner")
        self.stranger = User.objects.create(phone="+919000300302", name="Stranger")
        self.admin = User.objects.create(
            phone="+919000300303", name="Admin", role="admin"
        )
        key = default_storage.save("invoices/test.pdf", ContentFile(PDF_BYTES))
        self.invoice = Invoice.objects.create(
            user=self.owner, amount=Decimal("100.00"), pdf_key=key
        )
        self.blank = Invoice.objects.create(
            user=self.owner, amount=Decimal("50.00"), pdf_key=""
        )
        self.client = APIClient()

    def test_owner_can_fetch_pdf(self):
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/billing/invoices/{self.invoice.pk}/pdf")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "application/pdf")

    def test_staff_admin_can_fetch_pdf(self):
        self.client.force_authenticate(self.admin)
        resp = self.client.get(f"/api/v1/billing/invoices/{self.invoice.pk}/pdf")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "application/pdf")

    def test_stranger_is_forbidden(self):
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/billing/invoices/{self.invoice.pk}/pdf")
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json()["code"], "INSUFFICIENT_PERMISSIONS")

    def test_blank_pdf_key_lazy_generates(self):
        # A blank pdf_key now lazy-generates a real PDF on first fetch.
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/billing/invoices/{self.blank.pk}/pdf")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "application/pdf")
        self.blank.refresh_from_db()
        self.assertTrue(self.blank.pdf_key)

    def test_missing_invoice_404s(self):
        self.client.force_authenticate(self.owner)
        resp = self.client.get("/api/v1/billing/invoices/999999/pdf")
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["code"], "NOT_FOUND")


@override_settings(
    MEDIA_ROOT=tempfile.mkdtemp(prefix="vsmart-invpdf-"),
    MEDIA_INTERNAL_REDIRECT_PREFIX="",
)
class InvoicePdfGenerationTests(TestCase):
    """generate_invoice_pdf renders a real PDF, stores it, and stamps pdf_key;
    the serving endpoint lazy-generates behind the permission gate."""

    def setUp(self):
        self.owner = User.objects.create(phone="+919000300401", name="Owner")
        self.stranger = User.objects.create(phone="+919000300402", name="Stranger")
        self.invoice = Invoice.objects.create(
            user=self.owner,
            amount=Decimal("250.00"),
            gst=Decimal("12.50"),
            status=Invoice.Status.ISSUED,
        )
        InvoiceItem.objects.create(
            invoice=self.invoice, name="Aashirvaad Atta 5kg", quantity=2,
            price=Decimal("60.00"),
        )
        InvoiceItem.objects.create(
            invoice=self.invoice, name="Tata Salt 1kg", quantity=5,
            price=Decimal("26.00"),
        )
        self.client = APIClient()

    def test_generate_sets_pdf_key_and_writes_pdf_file(self):
        key = generate_invoice_pdf(self.invoice)
        self.assertTrue(key)
        self.invoice.refresh_from_db()
        self.assertEqual(self.invoice.pdf_key, key)
        self.assertTrue(default_storage.exists(key))
        with default_storage.open(key, "rb") as fh:
            head = fh.read(5)
        self.assertTrue(head.startswith(b"%PDF"))

    def test_generate_is_idempotent_overwrites_same_key(self):
        key1 = generate_invoice_pdf(self.invoice)
        key2 = generate_invoice_pdf(self.invoice)
        self.assertEqual(key1, key2)
        self.assertTrue(default_storage.exists(key2))

    def test_endpoint_lazy_generates_for_blank_pdf_key(self):
        self.assertEqual(self.invoice.pdf_key, "")
        self.client.force_authenticate(self.owner)
        resp = self.client.get(f"/api/v1/billing/invoices/{self.invoice.pk}/pdf")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "application/pdf")
        self.invoice.refresh_from_db()
        self.assertTrue(self.invoice.pdf_key)
        self.assertTrue(default_storage.exists(self.invoice.pdf_key))

    def test_stranger_blocked_and_no_pdf_generated(self):
        self.assertEqual(self.invoice.pdf_key, "")
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/billing/invoices/{self.invoice.pk}/pdf")
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json()["code"], "INSUFFICIENT_PERMISSIONS")
        # Generation happens AFTER the gate, so a blocked stranger triggers none.
        self.invoice.refresh_from_db()
        self.assertEqual(self.invoice.pdf_key, "")
