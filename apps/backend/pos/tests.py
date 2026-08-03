"""POS billing invariants — money + stock correctness at the till."""
from decimal import Decimal

from django.test import TestCase

from accounts.models import User
from catalog.models import Category, Product
from credit.models import CreditAccount
from credit.services import ensure_account
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService, StockCalculationService
from siteconfig.models import PlatformConfig

from .models import POSPayment, POSTransaction
from .services import (
    POSError,
    checkout,
    close_session,
    open_session,
    process_return,
    void_transaction,
)

LType = InventoryLedger.Type


def make_product(price="100.00"):
    cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
    return Product.objects.create(
        name="Sugar 1kg", brand="VS", unit="1 kg", price=Decimal(price),
        mrp=Decimal("120.00"), category=cat, stock_count=None,
    )


class POSCheckoutTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.cashier = User.objects.create(phone="+910000000001", name="Cashier",
                                           role="admin")
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=LType.GRN, quantity=100,
        )
        self.session = open_session(cashier=self.cashier, warehouse=self.wh,
                                    opening_cash=Decimal("500"))

    def _sale(self, qty=2, payments=None, **kw):
        return checkout(
            session=self.session,
            lines=[{"product": self.product, "qty": qty}],
            payments=payments if payments is not None else [
                {"method": "cash", "amount": "236.00"}],
            by=self.cashier, **kw,
        )

    def test_cash_sale_decrements_stock_and_posts_ledger(self):
        before = StockCalculationService.on_hand(self.product, self.wh)
        txn = self._sale(qty=2)
        self.assertEqual(txn.payment_status, POSTransaction.PaymentStatus.PAID)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), before - 2)
        self.assertTrue(
            InventoryLedger.objects.filter(product=self.product, type=LType.SALE).exists()
        )

    def test_short_payment_rejected(self):
        with self.assertRaises(POSError):
            self._sale(qty=2, payments=[{"method": "cash", "amount": "100.00"}])

    def test_overpay_cash_returns_change(self):
        txn = self._sale(qty=2, payments=[{"method": "cash", "amount": "500.00"}])
        # 2 × 100 + 18% = 236.00; change = 500 − 236 = 264.00
        self.assertEqual(txn.total, Decimal("236.00"))
        self.assertEqual(txn.change_due, Decimal("264.00"))

    def test_non_cash_cannot_exceed_total(self):
        with self.assertRaises(POSError):
            self._sale(qty=2, payments=[{"method": "card", "amount": "999.00"}])

    def test_idempotent_checkout(self):
        a = self._sale(qty=1, payments=[{"method": "cash", "amount": "118.00"}],
                       idempotency_key="k1")
        b = self._sale(qty=1, payments=[{"method": "cash", "amount": "118.00"}],
                       idempotency_key="k1")
        self.assertEqual(a.pk, b.pk)
        self.assertEqual(
            POSTransaction.objects.filter(idempotency_key="k1").count(), 1
        )

    def test_line_discount_reduces_subtotal(self):
        txn = checkout(
            session=self.session,
            lines=[{"product": self.product, "qty": 1, "discount": Decimal("20")}],
            payments=[{"method": "cash", "amount": "94.40"}], by=self.cashier,
        )
        self.assertEqual(txn.subtotal, Decimal("80.00"))   # 100 − 20
        self.assertEqual(txn.total, Decimal("94.40"))      # 80 + 18%


class POSCreditGateTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.cashier = User.objects.create(phone="+910000000002", name="Cashier",
                                           role="admin")
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=LType.GRN, quantity=50,
        )
        self.session = open_session(cashier=self.cashier, warehouse=self.wh)

    def _customer(self, kyc=True):
        u = User.objects.create(
            phone="+9190000000%02d" % (10 if kyc else 11), name="Cust",
            role="customer", kyc_status="verified" if kyc else "not_started",
            credit_enabled=kyc,
        )
        acc = ensure_account(u)
        acc.credit_limit = Decimal("5000")
        acc.status = CreditAccount.Status.ACTIVE
        acc.save()
        return u

    def test_credit_tender_requires_kyc(self):
        cust = self._customer(kyc=False)
        with self.assertRaises(POSError):
            checkout(
                session=self.session, lines=[{"product": self.product, "qty": 1}],
                payments=[{"method": "credit", "amount": "118.00"}],
                customer=cust, by=self.cashier,
            )

    def test_credit_sale_debits_credit_ledger_by_billed(self):
        cust = self._customer(kyc=True)
        txn = checkout(
            session=self.session, lines=[{"product": self.product, "qty": 1}],
            payments=[{"method": "credit", "amount": "118.00"}],
            customer=cust, by=self.cashier,
        )
        cust.credit_account.refresh_from_db()
        self.assertEqual(txn.credit_used, Decimal("118.00"))
        self.assertEqual(cust.credit_account.outstanding, Decimal("118.00"))


class POSVoidAndReturnTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.cashier = User.objects.create(phone="+910000000003", name="Cashier",
                                           role="admin")
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=LType.GRN, quantity=100,
        )
        self.session = open_session(cashier=self.cashier, warehouse=self.wh)

    def test_void_returns_all_stock_and_flags(self):
        before = StockCalculationService.on_hand(self.product, self.wh)
        txn = checkout(
            session=self.session, lines=[{"product": self.product, "qty": 3}],
            payments=[{"method": "cash", "amount": "354.00"}], by=self.cashier,
        )
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), before - 3)
        void_transaction(txn=txn, session=self.session, reason="error", by=self.cashier)
        txn.refresh_from_db()
        self.assertTrue(txn.is_voided)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), before)

    def test_partial_return_restocks(self):
        before = StockCalculationService.on_hand(self.product, self.wh)
        sale = checkout(
            session=self.session, lines=[{"product": self.product, "qty": 5}],
            payments=[{"method": "cash", "amount": "590.00"}], by=self.cashier,
        )
        process_return(
            session=self.session, original=sale,
            lines=[{"product": self.product, "qty": 2}], refund_method="cash",
            by=self.cashier,
        )
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), before - 3)

    def test_cannot_return_more_than_sold(self):
        sale = checkout(
            session=self.session, lines=[{"product": self.product, "qty": 2}],
            payments=[{"method": "cash", "amount": "236.00"}], by=self.cashier,
        )
        with self.assertRaises(POSError):
            process_return(
                session=self.session, original=sale,
                lines=[{"product": self.product, "qty": 5}], by=self.cashier,
            )


class POSDayClosingTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.cashier = User.objects.create(phone="+910000000004", name="Cashier",
                                           role="admin")
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=LType.GRN, quantity=100,
        )
        self.session = open_session(cashier=self.cashier, warehouse=self.wh,
                                    opening_cash=Decimal("1000"))

    def test_variance_zero_when_counted_matches_expected(self):
        checkout(
            session=self.session, lines=[{"product": self.product, "qty": 2}],
            payments=[{"method": "cash", "amount": "236.00"}], by=self.cashier,
        )
        # expected = opening 1000 + cash sales 236 = 1236
        closing = close_session(session=self.session, counted_cash=Decimal("1236.00"),
                                by=self.cashier)
        self.assertEqual(closing.expected_cash, Decimal("1236.00"))
        self.assertEqual(closing.variance, Decimal("0.00"))


class TaxInclusiveTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        self.cashier = User.objects.create(phone="+910000000005", name="Cashier",
                                           role="admin")
        self.product = make_product(price="118.00")  # MRP incl 18% GST
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=LType.GRN, quantity=50,
        )
        self.session = open_session(cashier=self.cashier, warehouse=self.wh)

    def test_tax_backed_out_when_inclusive(self):
        cfg = PlatformConfig.load()
        cfg.pos_price_tax_inclusive = True
        cfg.save()
        txn = checkout(
            session=self.session, lines=[{"product": self.product, "qty": 1}],
            payments=[{"method": "cash", "amount": "118.00"}], by=self.cashier,
        )
        # 118 inclusive → net 100.00, tax 18.00, total stays 118.00
        self.assertEqual(txn.total, Decimal("118.00"))
        self.assertEqual(txn.subtotal, Decimal("100.00"))
        self.assertEqual(txn.tax, Decimal("18.00"))


class POSReceiptPdfTests(TestCase):
    """The 80mm thermal receipt PDF renders for a real transaction."""

    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main2", code="MAIN2", is_default=True)
        self.cashier = User.objects.create(phone="+910000000091", name="Cashier",
                                           role="admin")
        self.product = make_product()
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=LType.GRN, quantity=50,
        )
        self.session = open_session(cashier=self.cashier, warehouse=self.wh,
                                    opening_cash=Decimal("500"))

    def test_receipt_pdf_renders(self):
        from .receipt_pdf import build_pos_receipt_pdf

        txn = checkout(
            session=self.session,
            lines=[{"product": self.product, "qty": 2}],
            payments=[{"method": "cash", "amount": "300.00"}],
            by=self.cashier,
        )
        pdf = build_pos_receipt_pdf(txn)
        self.assertGreater(len(pdf), 500)
        self.assertTrue(pdf.startswith(b"%PDF"))
