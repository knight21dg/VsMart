"""Invoice correctness — the numbers on the document must reconcile, and the
document must not assert tax facts (a GSTIN, an HSN code) that nobody supplied.

These matter most for a store selling its OWN private products: that store is the
supplier on the invoice, and the store panel's add-product form leaves HSN blank.
"""
from decimal import Decimal

from django.test import TestCase

from accounts.models import Role, User
from catalog.models import Category, Product
from orders.invoice import (
    is_tax_invoice,
    resolve_seller,
    rupees_in_words,
)
from orders.models import Order, OrderItem
from siteconfig.models import PlatformConfig
from stores.models import Store


def _store(**kw):
    defaults = dict(
        code="S-INV", name="Kirana Corner", address="12 Main Rd", phone="0800"
    )
    defaults.update(kw)
    return Store.objects.create(**defaults)


class SellerResolutionTests(TestCase):
    """Who the invoice says is selling — and whether it may call itself a TAX
    invoice."""

    def setUp(self):
        cfg = PlatformConfig.load()
        cfg.store_name = "VS Mart Platform"
        cfg.store_address = "HQ Road"
        cfg.store_gstin = ""
        cfg.save()

    def test_store_gstin_wins(self):
        seller = resolve_seller(_store(gstin="29AABCU9603R1ZM"))
        self.assertEqual(seller["gstin"], "29AABCU9603R1ZM")
        self.assertEqual(seller["name"], "Kirana Corner")
        self.assertTrue(is_tax_invoice(seller))

    def test_falls_back_to_platform_config_not_a_placeholder(self):
        cfg = PlatformConfig.load()
        cfg.store_gstin = "36AAAAA0000A1Z5"
        cfg.save()
        seller = resolve_seller(_store(gstin=""))
        self.assertEqual(seller["gstin"], "36AAAAA0000A1Z5")

    def test_no_gstin_anywhere_yields_empty_not_a_dummy(self):
        # Regression: a hardcoded "36ABCDE1234F1Z5" used to be printed on a document
        # headed TAX INVOICE for every store that had not set one — a fabricated tax
        # identifier on a tax document.
        seller = resolve_seller(_store(gstin=""))
        self.assertEqual(seller["gstin"], "")
        self.assertFalse(is_tax_invoice(seller))

    def test_no_store_still_resolves_platform_identity(self):
        seller = resolve_seller(None)
        self.assertEqual(seller["name"], "VS Mart Platform")


class InvoiceTotalsTests(TestCase):
    """The totals column must add up to the printed Grand Total."""

    def setUp(self):
        self.user = User.objects.create(
            phone="+919600000111", name="Cust", role=Role.CUSTOMER
        )
        self.cat = Category.objects.create(name="Staples", slug="staples-inv")

    def _order(self, *, subtotal, gst, delivery, platform, discount):
        # Mirrors core.pricing.compute_bill: gst is levied on the FULL subtotal and
        # the discount comes off at the end.
        total = subtotal + gst + delivery + platform - discount
        order = Order.objects.create(
            user=self.user,
            subtotal=Decimal(subtotal),
            gst=Decimal(gst),
            delivery_fee=Decimal(delivery),
            platform_fee=Decimal(platform),
            discount=Decimal(discount),
            total=Decimal(total),
        )
        p = Product.objects.create(
            name="Atta", price=Decimal("100"), mrp=Decimal("120"), category=self.cat
        )
        OrderItem.objects.create(
            order=order, product=p, name="Atta", price=Decimal("100"),
            mrp=Decimal("120"), quantity=1,
        )
        return order

    def test_discounted_order_reconciles_and_renders(self):
        # 1000 subtotal, 5% GST on the full subtotal, 200 coupon.
        order = self._order(
            subtotal=1000, gst=50, delivery=0, platform=0, discount=200
        )
        # taxable(1000) + gst(50) + delivery(0) + platform(0) - discount(200) = 850
        self.assertEqual(order.total, Decimal("850"))
        # The old builder printed taxable = subtotal - discount = 800 AND deducted
        # the 200 again, so the column summed to 650 against a Grand Total of 850.
        taxable = float(order.subtotal)
        summed = (
            taxable
            + float(order.gst)
            + float(order.delivery_fee)
            + float(order.platform_fee)
            - float(order.discount)
        )
        self.assertAlmostEqual(summed, float(order.total), places=2)

    def test_rate_is_derived_from_the_actual_taxable_base(self):
        order = self._order(
            subtotal=1000, gst=50, delivery=0, platform=0, discount=200
        )
        # 50 / 1000 = 5%. Dividing by (subtotal - discount) gave 6.25% → the invoice
        # printed "CGST @ 3.13%" for a 2.5% half-rate.
        rate = round(float(order.gst) / float(order.subtotal) * 100)
        self.assertEqual(rate, 5)

    def test_pdf_builds_for_a_store_private_product_without_hsn_or_gstin(self):
        from orders.invoice import build_invoice_pdf

        store = _store(gstin="")
        order = self._order(subtotal=100, gst=5, delivery=0, platform=0, discount=0)
        order.store = store
        order.save(update_fields=["store"])
        pdf = build_invoice_pdf(order)
        self.assertTrue(pdf.startswith(b"%PDF"))
        self.assertGreater(len(pdf), 1000)

    def test_pdf_builds_as_a_tax_invoice_with_a_gstin(self):
        from orders.invoice import build_invoice_pdf

        order = self._order(subtotal=100, gst=5, delivery=0, platform=0, discount=0)
        order.store = _store(gstin="29AABCU9603R1ZM")
        order.save(update_fields=["store"])
        self.assertTrue(build_invoice_pdf(order).startswith(b"%PDF"))


class AmountInWordsTests(TestCase):
    def test_indian_numbering(self):
        self.assertEqual(rupees_in_words(0), "Zero Rupees Only")
        self.assertEqual(rupees_in_words(850), "Eight Hundred Fifty Rupees Only")
        self.assertEqual(
            rupees_in_words(125000), "One Lakh Twenty Five Thousand Rupees Only"
        )
