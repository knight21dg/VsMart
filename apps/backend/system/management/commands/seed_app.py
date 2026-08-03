"""Seed a complete, practical dataset so EVERY customer-facing API returns real
data for the app — one command, idempotent (safe to re-run).

    python manage.py seed_app

It runs the catalog + CMS seeds, ensures a serviceable store/zone with stock,
then populates a demo customer (+919000000001) across every module: addresses,
cart, wishlist, orders in many statuses (+ live tracking), credit (ledger of
every entry type + statement + lending partner), KYC (verified + documents),
payments + cash collection, notifications, loyalty, referrals, support tickets,
returns and reviews.

Log in from the app with phone 9000000001 and OTP 123456 to see it all.
"""
from datetime import timedelta
from decimal import Decimal

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

# A dedicated demo shopper, kept separate from the bare setup_local customer so
# every module seeds fully and deterministically (log in as 9000000007 / 123456).
CUSTOMER_PHONE = "+919000000007"
D = Decimal


class Command(BaseCommand):
    help = "Seed a full demo dataset (catalog + a complete demo customer) for the app."

    def handle(self, *args, **opts):
        # 1) Public catalog, offers, FAQs, CMS pages.
        call_command("seed_demo")
        try:
            call_command("seed_content")
        except Exception as e:  # seed_content is optional
            self.stdout.write(self.style.WARNING(f"seed_content skipped: {e}"))

        # 2) Infrastructure: users, warehouse, store, serviceable zone, stock.
        self._infra()

        # 3) Per-customer data across every module.
        self._customer_data()

        self.stdout.write(self.style.SUCCESS(self._summary()))

    # ── infrastructure ────────────────────────────────────────────────
    def _infra(self):
        from accounts.models import User
        from catalog.models import Product
        from inventory.models import Barcode, InventoryLedger, Warehouse
        from inventory.services import InventoryService, StockCalculationService
        from stores.models import Store
        from zones.models import Zone

        admin, _ = User.objects.get_or_create(
            phone="+919888888888",
            defaults={"name": "VS Store Admin", "role": "admin"},
        )
        self.customer, _ = User.objects.get_or_create(
            phone=CUSTOMER_PHONE,
            defaults={"name": "Demo Shopper", "role": "customer"},
        )
        # Always KYC-verified + credit-enabled so credit cases are exercisable.
        self.customer.name = self.customer.name or "Demo Customer"
        self.customer.kyc_status = "verified"
        self.customer.credit_enabled = True
        self.customer.email = self.customer.email or "demo@vsmart.app"
        self.customer.save()

        warehouse, _ = Warehouse.objects.get_or_create(
            code="MAIN", defaults={"name": "Main Store", "is_default": True}
        )
        store, _ = Store.objects.update_or_create(
            code="STORE-BLR-01",
            defaults={
                "name": "VS Mart Bengaluru Central",
                "address": "MG Road, Bengaluru, Karnataka",
                "latitude": D("12.9750"), "longitude": D("77.6000"),
                "phone": "9000000010", "status": Store.Status.ACTIVE,
                "warehouse": warehouse,
            },
        )
        Zone.objects.update_or_create(
            code="ZONE-BLR-CENTRAL",
            defaults={
                "name": "Bengaluru Central",
                "polygon_geojson": {
                    "type": "Polygon",
                    "coordinates": [[
                        [77.45, 12.85], [77.75, 12.85], [77.75, 13.10],
                        [77.45, 13.10], [77.45, 12.85],
                    ]],
                },
                "store": store, "is_active": True, "credit_enabled": True,
                "estimated_delivery_minutes": 20, "priority": 10,
                "delivery_fee": D("15.00"), "min_order": D("99.00"),
                "free_delivery_threshold": D("199.00"),
            },
        )
        # Stock the first products so live checkout from the app can reserve.
        for p in Product.objects.all()[:14]:
            Barcode.objects.get_or_create(
                code=f"890{p.id:010d}",
                defaults={"product": p, "symbology": "EAN13", "is_primary": True},
            )
            if StockCalculationService.on_hand(p, warehouse) < 50:
                InventoryService.post_movement(
                    product=p, warehouse=warehouse, type=InventoryLedger.Type.GRN,
                    quantity=100, unit_cost=p.price, ref_type="seed",
                    note="seed_app stock", created_by=admin,
                )
        self.store = store

    # ── per-customer data ─────────────────────────────────────────────
    def _customer_data(self):
        self._addresses()
        self._cart_and_wishlist()
        orders = self._orders()
        self._credit(orders)
        self._kyc()
        self._notifications()
        self._loyalty()
        self._referrals()
        self._support()
        self._returns(orders)
        self._reviews()

    def _products(self, n=6):
        from catalog.models import Product
        return list(Product.objects.filter(is_active=True).order_by("id")[:n])

    def _addresses(self):
        from addresses.models import Address
        u = self.customer
        if Address.objects.filter(user=u).exists():
            return
        Address.objects.create(
            user=u, label="Home", name="Demo Customer", phone=CUSTOMER_PHONE,
            line1="42, 3rd Cross, Indiranagar", village="Indiranagar",
            area="Indiranagar", city="Bengaluru", district="Bengaluru Urban",
            state="Karnataka", pincode="560038",
            latitude=D("12.9719"), longitude=D("77.6412"), is_default=True,
        )
        Address.objects.create(
            user=u, label="Work", name="Demo Customer", phone=CUSTOMER_PHONE,
            line1="VS Mart HQ, MG Road", village="Bengaluru", area="MG Road",
            city="Bengaluru", district="Bengaluru Urban", state="Karnataka",
            pincode="560001", latitude=D("12.9750"), longitude=D("77.6000"),
        )

    def _cart_and_wishlist(self):
        from cart.models import Cart, CartItem, WishlistItem
        u = self.customer
        products = self._products(6)
        cart, _ = Cart.objects.get_or_create(user=u)
        if not cart.items.exists():
            for p in products[:3]:
                CartItem.objects.create(
                    cart=cart, product=p, quantity=2, price_snapshot=p.price
                )
        for p in products[3:6]:
            WishlistItem.objects.get_or_create(user=u, product=p)

    def _orders(self):
        from orders.models import Order, OrderItem, OrderStatusEvent, OrderTracking
        u = self.customer
        existing = list(Order.objects.filter(user=u).order_by("id"))
        if existing:
            return existing

        products = self._products(6)
        snap = {
            "name": "Demo Customer", "phone": CUSTOMER_PHONE,
            "formatted": "42, 3rd Cross, Indiranagar, Bengaluru, Karnataka 560038",
            "pincode": "560038",
        }
        now = timezone.now()
        # (status, payment_method, payment_status, days_ago, item_slice, timeline, tracking)
        specs = [
            ("delivered", "upi", "paid", 6, products[0:3],
             ["placed", "confirmed", "packed", "out_for_delivery", "delivered"], None),
            ("delivered", "credit", "paid", 12, products[2:5],
             ["placed", "confirmed", "packed", "out_for_delivery", "delivered"], None),
            ("out_for_delivery", "cod", "pending", 0, products[1:4],
             ["placed", "confirmed", "packed", "out_for_delivery"],
             {"agent": "Ravi Kumar", "lat": D("12.9740"), "lng": D("77.6210"),
              "eta": "12 mins"}),
            ("confirmed", "upi", "paid", 0, products[0:2],
             ["placed", "confirmed"], None),
            ("cancelled", "upi", "refunded", 3, products[3:5],
             ["placed", "cancelled"], None),
            ("returned", "credit", "refunded", 20, products[1:3],
             ["placed", "confirmed", "packed", "out_for_delivery", "delivered",
              "returned"], None),
        ]
        created = []
        for status, method, pay_status, days_ago, items, tl, track in specs:
            subtotal = sum((p.price * 2 for p in items), D("0"))
            gst = (subtotal * D("0.18")).quantize(D("0.01"))
            delivery = D("0.00") if subtotal >= 199 else D("15.00")
            total = subtotal + gst + delivery
            credit_used = total if method == "credit" else D("0.00")
            order = Order.objects.create(
                user=u, status=status, payment_method=method,
                payment_status=pay_status, address_snapshot=snap,
                subtotal=subtotal, gst=gst, delivery_fee=delivery, total=total,
                credit_used=credit_used, store=self.store,
                stock_state="fulfilled" if status == "delivered" else "none",
            )
            for p in items:
                OrderItem.objects.create(
                    order=order, product=p, name=p.name, brand=p.brand,
                    unit=p.unit, image_url=p.image_url, price=p.price,
                    mrp=p.mrp, quantity=2,
                )
            for st in tl:
                OrderStatusEvent.objects.create(order=order, status=st)
            if track:
                OrderTracking.objects.create(
                    order=order, agent_name=track["agent"], latitude=track["lat"],
                    longitude=track["lng"], eta=track["eta"],
                )
            # Backdate (auto_now_add can't be set on create).
            Order.objects.filter(pk=order.pk).update(
                placed_at=now - timedelta(days=days_ago)
            )
            created.append(order)
        return created

    def _credit(self, orders):
        from credit.models import CreditAccount, CreditLedgerEntry, LendingPartner, Statement
        from credit.services import _post, adjust, apply_refund, apply_repayment, debit_purchase, ensure_account
        u = self.customer
        account = ensure_account(u)
        partner, _ = LendingPartner.objects.get_or_create(
            name="VS Finance Partners NBFC",
            defaults={"nbfc_registration_no": "N-14.03268", "is_active": True},
        )
        account.credit_limit = D("25000.00")
        account.vs_score = 742
        account.status = CreditAccount.Status.ACTIVE
        account.billing_cycle = CreditAccount.BillingCycle.MONTHLY
        account.lender = partner
        account.loan_account_number = "VSL00010042"
        account.interest_rate = D("18.00")
        account.sanctioned_limit = D("25000.00")
        account.save()

        # One ledger entry of every type (append-only — seed once).
        if not account.entries.exists():
            debit_purchase(account, D("4200.00"), note="Order VSORD groceries")
            debit_purchase(account, D("1850.00"), note="Order VSORD staples")
            apply_repayment(account, D("3000.00"), note="UPI repayment")
            _post(account, CreditLedgerEntry.Type.FEE, D("49.00"), note="Late fee")
            adjust(account, D("-100.00"), note="Goodwill credit")
            apply_refund(account, D("600.00"), note="Return refund")

        # An open monthly statement so the dashboard shows a real due. Refresh
        # the account so closing_balance reflects the posted ledger outstanding.
        account.refresh_from_db()
        today = timezone.now().date()
        start = today.replace(day=1) - timedelta(days=30)
        end = today.replace(day=1) - timedelta(days=1)
        Statement.objects.update_or_create(
            account=account, period_start=start, period_end=end,
            defaults={
                "period": Statement.Period.MONTHLY,
                "opening_balance": D("0.00"), "purchases": D("6050.00"),
                "payments": D("3000.00"), "fees": D("49.00"),
                "closing_balance": account.outstanding,
                "due_date": today + timedelta(days=7),
                "status": Statement.Status.OPEN,
            },
        )

    def _kyc(self):
        from kyc.models import KycApplication, KycDocument, VerificationStep
        u = self.customer
        app, created = KycApplication.objects.get_or_create(
            user=u,
            defaults={"status": KycApplication.Status.VERIFIED,
                      "submitted_at": timezone.now() - timedelta(days=20),
                      "reviewed_at": timezone.now() - timedelta(days=19)},
        )
        if created:
            docs = [
                ("aadhaar", "XXXX XXXX 1234"),
                ("pan", "ABCDXXXXXF"),
                ("selfie", ""),
                ("residence", ""),
            ]
            for typ, masked in docs:
                KycDocument.objects.create(
                    application=app, type=typ, number_masked=masked,
                    status="approved",
                )
                VerificationStep.objects.get_or_create(
                    application=app, step=typ, defaults={"status": "approved"}
                )

    def _notifications(self):
        from notifications.models import NotificationPreference
        from notifications.services import notify
        u = self.customer
        NotificationPreference.objects.get_or_create(user=u)
        from notifications.models import Notification
        if Notification.objects.filter(user=u).exists():
            return
        items = [
            ("order", "Order delivered", "Your order VSORD100000 was delivered. Enjoy!"),
            ("payment", "Payment due soon", "₹3,099 is due on your VS Credit in 7 days."),
            ("credit", "Credit approved", "Your VS Credit limit is now ₹25,000."),
            ("offer", "Weekend offer", "Flat 20% off on fresh fruits & vegetables."),
            ("order", "Out for delivery", "Ravi is on the way with your order."),
        ]
        for i, (typ, title, body) in enumerate(items):
            n = notify(u, type=typ, title=title, body=body)
            # Mark the two oldest as read.
            if n and i >= 3:
                n.read_at = timezone.now()
                n.save(update_fields=["read_at"])

    def _loyalty(self):
        from loyalty.models import PointsLedgerEntry
        from loyalty.services import post
        u = self.customer
        if PointsLedgerEntry.objects.filter(user=u).exists():
            return
        post(u, "earn", 120, note="Order VSORD100000", ref_type="order", ref_id="VSORD100000")
        post(u, "earn", 90, note="Order VSORD100001", ref_type="order", ref_id="VSORD100001")
        post(u, "redeem", -50, note="Redeemed to wallet")

    def _referrals(self):
        from accounts.models import User
        from referrals.models import Referral
        u = self.customer
        Referral.objects.get_or_create(
            referrer=u, code=f"VS{u.id:05d}",
            defaults={"reward": D("100.00"), "status": Referral.Status.PENDING},
        )
        # A completed referral so `referredCount` is non-zero.
        friend, _ = User.objects.get_or_create(
            phone="+919000000099",
            defaults={"name": "Referred Friend", "role": "customer"},
        )
        Referral.objects.get_or_create(
            referrer=u, code=f"VS{u.id:05d}F1",
            defaults={"reward": D("100.00"), "referee": friend,
                      "status": Referral.Status.COMPLETED},
        )

    def _support(self):
        from support.models import SupportTicket, TicketMessage
        u = self.customer
        if SupportTicket.objects.filter(user=u).exists():
            return
        t1 = SupportTicket.objects.create(
            user=u, category="Order", subject="Order Issue", priority="high",
            status=SupportTicket.Status.OPEN, order_code="VSORD100002",
        )
        TicketMessage.objects.create(ticket=t1, sender=u,
                                     body="My order is delayed, can you check?")
        t2 = SupportTicket.objects.create(
            user=u, category="Payment", subject="Payment Problem", priority="medium",
            status=SupportTicket.Status.RESOLVED,
        )
        TicketMessage.objects.create(ticket=t2, sender=u,
                                     body="Repayment not reflecting.")
        TicketMessage.objects.create(ticket=t2, sender=u,
                                     body="Resolved now, thanks!")

    def _returns(self, orders):
        from returns.models import ReturnItem, ReturnRequest, ReturnStatus
        u = self.customer
        if ReturnRequest.objects.filter(user=u).exists():
            return
        delivered = next((o for o in orders if o.status == "delivered"), None)
        if not delivered:
            return
        rr = ReturnRequest.objects.create(
            user=u, order=delivered, reason="Damaged item",
            description="One pack arrived damaged.",
            status=ReturnStatus.APPROVED,
            refund_amount=D("180.00"),
        )
        item = delivered.items.first()
        if item:
            ReturnItem.objects.create(
                return_request=rr, product_name=item.name, quantity=1,
                amount=D("180.00"),
            )

    def _reviews(self):
        from reviews.models import Review
        u = self.customer
        products = self._products(4)
        samples = [
            (products[0], 5, "Excellent", "Fresh and well packed."),
            (products[2], 4, "Good value", "Tasty, would buy again."),
        ]
        for p, rating, title, body in samples:
            Review.objects.get_or_create(
                user=u, product=p,
                defaults={"rating": rating, "title": title, "body": body},
            )

    def _summary(self):
        from accounts.models import User
        u = User.objects.get(phone=CUSTOMER_PHONE)
        bar = "=" * 60
        return (
            f"\n{bar}\n  VS MART — DEMO DATA READY (every module populated)\n{bar}\n"
            f"  Log in from the app:  phone 9000000007   OTP 123456\n"
            f"  Customer: {u.name}  ({u.phone})  KYC=verified  credit=on\n"
            f"  Orders: {u.orders.count()}  ·  Credit ledger: "
            f"{u.credit_account.entries.count()}  ·  Addresses: {u.addresses.count()}\n"
            f"  Tickets: {u.tickets.count()}  ·  Notifications: {u.notifications.count()}\n"
            f"{bar}"
        )
