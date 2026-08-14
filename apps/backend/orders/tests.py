"""Order reservation-TTL sweep — abandoned unpaid orders must release their stock."""
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.test import TestCase
from django.utils import timezone

from accounts.models import User
from catalog.models import Category, Product
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService, StockCalculationService

from .models import Order, OrderItem, OrderStatus
from .services import release_expired_reservations


class ReservationTTLTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Sugar", brand="VS", unit="1 kg", price=Decimal("50"),
            mrp=Decimal("60"), category=cat, stock_count=None,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10,
        )
        self.user = User.objects.create(phone="+910000000099", name="U")

    def _reserved_pending_order(self):
        order = Order.objects.create(
            user=self.user, payment_method=Order.PaymentMethod.UPI,
            status=OrderStatus.PENDING, stock_state=Order.StockState.RESERVED,
            total=Decimal("100"),
        )
        OrderItem.objects.create(
            order=order, product=self.product, name="Sugar", quantity=2,
            price=Decimal("50"), mrp=Decimal("60"),
        )
        InventoryService.reserve(product=self.product, quantity=2, warehouse=self.wh)
        return order

    def test_stale_unpaid_order_releases_stock(self):
        order = self._reserved_pending_order()
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 8)
        # Backdate beyond the TTL.
        Order.objects.filter(pk=order.pk).update(
            placed_at=timezone.now() - timezone.timedelta(minutes=120)
        )
        cancelled = release_expired_reservations(ttl_minutes=30)
        self.assertEqual(len(cancelled), 1)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CANCELLED)
        self.assertEqual(order.stock_state, Order.StockState.RELEASED)
        # Reservation freed → full stock available again, on-hand untouched.
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 10)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 10)

    def test_fresh_unpaid_order_kept(self):
        order = self._reserved_pending_order()
        cancelled = release_expired_reservations(ttl_minutes=30)
        self.assertEqual(cancelled, [])
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.PENDING)
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 8)


class ZoneRoutingTests(TestCase):
    """Z3 — orders route to the serviceable store; credit is zone-gated; hard
    serviceability enforcement is opt-in."""

    # Square over central Bengaluru ([lng, lat]).
    SQUARE = {
        "type": "Polygon",
        "coordinates": [[
            [77.55, 12.95], [77.65, 12.95], [77.65, 13.00],
            [77.55, 13.00], [77.55, 12.95],
        ]],
    }

    def setUp(self):
        from addresses.models import Address
        from cart.services import get_cart, upsert_item
        from stores.models import Store
        from zones.models import Zone

        self.upsert_item = upsert_item
        self.get_cart = get_cart

        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Rice", brand="VS", unit="1 kg", price=Decimal("50"),
            mrp=Decimal("60"), category=cat, stock_count=None,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=20,
        )
        self.store = Store.objects.create(
            code="S1", name="BLR Store", warehouse=self.wh,
            status=Store.Status.ACTIVE,
        )
        self.zone = Zone.objects.create(
            code="Z1", name="BLR Central", polygon_geojson=self.SQUARE,
            store=self.store, is_active=True, credit_enabled=True, priority=5,
        )
        self.user = User.objects.create(
            phone="+910000000077", name="Cust", kyc_status="verified",
            credit_enabled=True,
        )
        # Inside the polygon.
        self.address_in = Address.objects.create(
            user=self.user, name="Cust", phone="9000000077", line1="MG Rd",
            latitude=Decimal("12.97"), longitude=Decimal("77.60"), pincode="560001",
        )
        # Outside every polygon.
        self.address_out = Address.objects.create(
            user=self.user, name="Cust", phone="9000000077", line1="Nowhere",
            latitude=Decimal("20.0"), longitude=Decimal("80.0"), pincode="999999",
        )

    def _add_to_cart(self, qty=1):
        cart = self.get_cart(self.user)
        self.upsert_item(cart, self.product, None, qty)

    def test_order_routed_to_store(self):
        from zones.models import ZoneEvent

        from .services import place_order

        self._add_to_cart()
        order = place_order(
            self.user, address=self.address_in,
            payment_method=Order.PaymentMethod.COD,
        )
        self.assertEqual(order.store_id, self.store.id)
        self.assertEqual(order.zone_id, self.zone.id)
        self.assertTrue(
            ZoneEvent.objects.filter(type="order_routed", zone=self.zone).exists()
        )

    def test_checkout_is_idempotent_on_key(self):
        """A repeat checkout with the same Idempotency-Key (network retry / double
        tap) returns the SAME order, never a second one."""
        from .services import place_order

        self._add_to_cart()
        o1 = place_order(
            self.user, address=self.address_in,
            payment_method=Order.PaymentMethod.COD, idempotency_key="co_DUP",
        )
        o2 = place_order(
            self.user, address=self.address_in,
            payment_method=Order.PaymentMethod.COD, idempotency_key="co_DUP",
        )
        self.assertEqual(o1.id, o2.id)
        self.assertEqual(Order.objects.filter(user=self.user).count(), 1)

    def test_two_checkouts_for_last_unit_block_oversell(self):
        """Two customers checking out the last unit: the first reserves it, the
        second is blocked at checkout — no oversell, no phantom second order."""
        from addresses.models import Address
        from inventory.services import StockCalculationService

        from .services import CheckoutError, place_order

        # Exactly one sellable unit at the serving store.
        InventoryService.adjust(self.product, set=1, warehouse=self.wh)

        self._add_to_cart(qty=1)
        o1 = place_order(self.user, address=self.address_in,
                         payment_method=Order.PaymentMethod.COD)
        self.assertEqual(o1.stock_state, Order.StockState.RESERVED)
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 0)

        # Second customer wants the same last unit → blocked, transaction rolls back.
        u2 = User.objects.create(phone="+910000000078", name="Cust2")
        a2 = Address.objects.create(
            user=u2, name="Cust2", phone="9000000078", line1="MG Rd",
            latitude=Decimal("12.97"), longitude=Decimal("77.60"), pincode="560001")
        self.upsert_item(self.get_cart(u2), self.product, None, 1)
        with self.assertRaises(CheckoutError):
            place_order(u2, address=a2, payment_method=Order.PaymentMethod.COD)

        # One reservation only; on-hand untouched; no order created for u2.
        self.assertEqual(StockCalculationService.available(self.product, self.wh), 0)
        self.assertEqual(StockCalculationService.on_hand(self.product, self.wh), 1)
        self.assertEqual(Order.objects.filter(user=u2).count(), 0)

    # ── Reversal / reconciliation: cancel must undo every side effect ──
    def test_cancel_cod_order_releases_reserved_stock(self):
        from inventory.services import StockCalculationService

        from .services import cancel_order, place_order

        before = StockCalculationService.available(self.product, self.wh)
        self._add_to_cart(qty=3)
        order = place_order(self.user, address=self.address_in,
                            payment_method=Order.PaymentMethod.COD)
        self.assertEqual(
            StockCalculationService.available(self.product, self.wh), before - 3)

        order = cancel_order(order)
        self.assertEqual(order.status, OrderStatus.CANCELLED)
        self.assertEqual(order.stock_state, Order.StockState.RELEASED)
        # Reservation fully released — exactly one release per reservation.
        self.assertEqual(
            StockCalculationService.available(self.product, self.wh), before)

    def test_credit_order_does_not_charge_until_delivered(self):
        """The ledger stays untouched at checkout — the debt is only posted
        once the order is actually delivered (see delivery.services /
        orders.services.advance_status). credit_used still records what the
        order WILL cost, and counts against the limit via
        pending_credit_exposure, but nothing is on the books yet."""
        from credit.services import ensure_account

        from .services import cancel_order, pending_credit_exposure, place_order

        acct = ensure_account(self.user)
        acct.credit_limit = Decimal("10000")
        acct.save(update_fields=["credit_limit"])

        self._add_to_cart(qty=1)
        order = place_order(self.user, address=self.address_in,
                            payment_method=Order.PaymentMethod.CREDIT)
        self.assertEqual(order.credit_used, order.total)
        acct.refresh_from_db()
        self.assertEqual(acct.outstanding, Decimal("0.00"))  # nothing charged yet
        self.assertEqual(acct.entries.count(), 0)  # no ledger entry at all
        self.assertEqual(pending_credit_exposure(self.user), order.total)

        # Cancelling a not-yet-delivered credit order never touched the ledger
        # in the first place, so there is nothing to reverse.
        cancel_order(order)
        acct.refresh_from_db()
        self.assertEqual(acct.outstanding, Decimal("0.00"))
        self.assertEqual(acct.entries.count(), 0)
        self.assertEqual(pending_credit_exposure(self.user), Decimal("0.00"))

    def test_pending_credit_exposure_blocks_overlapping_orders(self):
        """Two in-flight credit orders that would together exceed the limit —
        neither has been delivered, so `outstanding` alone can't catch this;
        it's still literally zero."""
        from credit.services import ensure_account

        from .services import CheckoutError, place_order

        acct = ensure_account(self.user)
        acct.credit_limit = Decimal("10000")
        acct.save(update_fields=["credit_limit"])

        self._add_to_cart(qty=1)
        first = place_order(self.user, address=self.address_in,
                            payment_method=Order.PaymentMethod.CREDIT)
        self.assertEqual(first.status, OrderStatus.CONFIRMED)

        # Cap the limit at 1.5x what the first order cost. Nothing has posted
        # to the ledger (outstanding is still 0), but the first order is
        # already committed, so a same-size second one must still be refused.
        acct.refresh_from_db()
        acct.credit_limit = first.credit_used + (first.credit_used / 2)
        acct.save(update_fields=["credit_limit"])

        self._add_to_cart(qty=1)
        with self.assertRaises(CheckoutError) as ctx:
            place_order(self.user, address=self.address_in,
                       payment_method=Order.PaymentMethod.CREDIT)
        self.assertEqual(ctx.exception.code, "LIMIT_EXCEEDED")

    def test_double_cancel_is_rejected_no_double_reversal(self):
        from .services import CheckoutError, cancel_order, place_order

        self._add_to_cart(qty=2)
        order = place_order(self.user, address=self.address_in,
                            payment_method=Order.PaymentMethod.COD)
        cancel_order(order)
        # Second cancel (double-tap / admin race) is rejected, so stock isn't
        # released twice.
        with self.assertRaises(CheckoutError):
            cancel_order(order)

    def test_cannot_cancel_delivered_order(self):
        from .services import CheckoutError, cancel_order, place_order

        self._add_to_cart(qty=1)
        order = place_order(self.user, address=self.address_in,
                            payment_method=Order.PaymentMethod.COD)
        Order.objects.filter(pk=order.pk).update(status=OrderStatus.DELIVERED)
        with self.assertRaises(CheckoutError):
            cancel_order(order)  # delivered → return flow, not cancel

    def test_credit_blocked_in_credit_disabled_zone(self):
        from .services import CheckoutError, place_order

        self.zone.credit_enabled = False
        self.zone.save(update_fields=["credit_enabled"])
        self._add_to_cart()
        with self.assertRaises(CheckoutError):
            place_order(
                self.user, address=self.address_in,
                payment_method=Order.PaymentMethod.CREDIT,
            )

    def test_cod_allowed_in_credit_disabled_zone(self):
        from .services import place_order

        self.zone.credit_enabled = False
        self.zone.save(update_fields=["credit_enabled"])
        self._add_to_cart()
        order = place_order(
            self.user, address=self.address_in,
            payment_method=Order.PaymentMethod.COD,
        )
        self.assertEqual(order.status, OrderStatus.CONFIRMED)

    def test_enforcement_flag_rejects_unserviceable_address(self):
        from system.models import FeatureFlag

        from .services import CheckoutError, place_order

        FeatureFlag.objects.create(key="zone_enforcement", enabled=True)
        self._add_to_cart()
        with self.assertRaises(CheckoutError):
            place_order(
                self.user, address=self.address_out,
                payment_method=Order.PaymentMethod.COD,
            )

    def test_unserviceable_allowed_when_enforcement_off(self):
        from .services import place_order

        self._add_to_cart()
        order = place_order(
            self.user, address=self.address_out,
            payment_method=Order.PaymentMethod.COD,
        )
        # No zone resolved → no store, but the order still goes through.
        self.assertIsNone(order.store_id)
        self.assertIsNone(order.zone_id)


class AdminOrdersTests(TestCase):
    """Admin Orders module — dashboard, list (filters/sort), detail, lifecycle."""

    def setUp(self):
        from decimal import Decimal

        from rest_framework.test import APIClient

        self.admin = User.objects.create(phone="+919888888070", name="Admin", role="admin")
        self.agent = User.objects.create(phone="+919777777070", name="Agent", role="agent")
        self.customer = User.objects.create(phone="+919000000070", name="Cust", role="customer")
        self.order = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.COD,
            status=OrderStatus.CONFIRMED, total=Decimal("500"),
        )
        OrderItem.objects.create(
            order=self.order, product=None, name="Rice", quantity=2,
            price=Decimal("250"), mrp=Decimal("300"),
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_dashboard(self):
        r = self.client.get("/api/v1/admin/orders/dashboard")
        self.assertEqual(r.status_code, 200)
        self.assertIn("revenueToday", r.json()["data"])

    def test_list_and_filter(self):
        r = self.client.get("/api/v1/admin/orders", {"status": "confirmed"})
        rows = r.json()["data"]
        self.assertTrue(any(row["code"] == self.order.code for row in rows))
        self.assertEqual(rows[0]["items"], 1)

    def test_detail_sections(self):
        r = self.client.get(f"/api/v1/admin/orders/{self.order.code}")
        data = r.json()["data"]
        for k in ("header", "customer", "items", "totals", "payment", "delivery", "timeline"):
            self.assertIn(k, data)

    def test_status_transition(self):
        r = self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/status",
            {"status": "packed"}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "packed")
        self.assertTrue(self.order.timeline.filter(status="packed").exists())

    def test_assign_agent(self):
        r = self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/assign-agent",
            {"agentId": str(self.agent.id)}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.order.refresh_from_db()
        self.assertEqual(self.order.delivery.agent_id, self.agent.id)

    def test_assign_agent_creates_a_real_delivery_task(self):
        """assign_agent() used to touch ONLY the legacy DeliveryAssignment
        relation — no DeliveryTask was ever created, so the agent app (which
        reads delivery_tasks, not DeliveryAssignment) never actually received
        the dispatch. It now goes through delivery.services.manual_assign."""
        from delivery.models import DeliveryTask
        from notifications.models import Notification

        r = self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/assign-agent",
            {"agentId": str(self.agent.id)}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        task = DeliveryTask.objects.filter(order=self.order, agent=self.agent).first()
        self.assertIsNotNone(task)
        self.assertEqual(task.status, "assigned")
        self.assertTrue(
            Notification.objects.filter(user=self.agent, type="delivery").exists())

    def test_bad_status_rejected(self):
        r = self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/status",
            {"status": "nonsense"}, format="json",
        )
        self.assertEqual(r.status_code, 400)

    def test_delivered_is_blocked_from_raw_status_write(self):
        """Only the agent's own OTP + photo verification
        (delivery.services.complete_delivery) may mark an order delivered —
        not this admin panel, even for a super-admin."""
        self.order.status = OrderStatus.OUT_FOR_DELIVERY
        self.order.save(update_fields=["status"])
        r = self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/status",
            {"status": "delivered"}, format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["error"]["code"], "status_requires_guarded_flow")
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "out_for_delivery")

    def test_returned_is_blocked_from_raw_status_write(self):
        """"Returned" has its own guarded subsystem (returns.admin_service —
        refund + stock reversal); writing the status directly must not create
        an order that LOOKS returned with no return record and no refund."""
        self.order.status = OrderStatus.DELIVERED
        self.order.save(update_fields=["status"])
        r = self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/status",
            {"status": "returned"}, format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "delivered")

    def test_list_and_queues_show_the_real_delivery_task_agent(self):
        """Regression for the same `order.delivery` stale-relation bug fixed
        in order_detail() this session — `_summary()` (which powers both the
        admin Orders list and the Packing & Dispatch kanban) must read the
        real DeliveryTask, not the near-always-empty legacy DeliveryAssignment."""
        from delivery.models import DeliveryTask

        DeliveryTask.objects.create(order=self.order, agent=self.agent, status="out_for_delivery")
        r = self.client.get("/api/v1/admin/orders", {"status": "confirmed"})
        row = next(row for row in r.json()["data"] if row["code"] == self.order.code)
        self.assertEqual(row["agent"], self.agent.name)
        self.assertEqual(row["deliveryStatus"], "out_for_delivery")

        queues = self.client.get("/api/v1/admin/orders/queues").json()["data"]
        qrow = next(
            (o for bucket in ("toPack", "packed", "readyForDispatch", "outForDelivery")
             for o in queues[bucket] if o["code"] == self.order.code),
            None,
        )
        self.assertIsNotNone(qrow)
        self.assertEqual(qrow["agent"], self.agent.name)

    def test_agent_filter_matches_the_real_delivery_task(self):
        """The `agent` list filter used to key off the legacy `delivery__agent_id`
        relation — silently returning nothing for orders whose agent only
        exists on the real DeliveryTask."""
        from delivery.models import DeliveryTask

        DeliveryTask.objects.create(order=self.order, agent=self.agent, status="assigned")
        r = self.client.get("/api/v1/admin/orders", {"agent": str(self.agent.id)})
        rows = r.json()["data"]
        self.assertTrue(any(row["code"] == self.order.code for row in rows))

    def test_queues_buckets(self):
        r = self.client.get("/api/v1/admin/orders/queues")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        # The confirmed order lands in the to-pack bucket.
        self.assertTrue(any(o["code"] == self.order.code for o in data["toPack"]))
        # Advance to packed → moves bucket.
        self.client.post(
            f"/api/v1/admin/orders/{self.order.code}/status",
            {"status": "packed"}, format="json",
        )
        data2 = self.client.get("/api/v1/admin/orders/queues").json()["data"]
        self.assertTrue(any(o["code"] == self.order.code for o in data2["packed"]))


class CheckoutIdempotencyConstraintTests(TestCase):
    """Race-safe checkout: the DB rejects a second order with the same
    (user, idempotency_key), so a concurrent double-submit (double-tap Pay)
    can't create duplicate orders even if it slips past the in-app guard."""

    def setUp(self):
        self.user = User.objects.create(phone="+910000000077", name="Idem")

    def _order(self, key):
        return Order.objects.create(
            user=self.user, payment_method=Order.PaymentMethod.UPI,
            status=OrderStatus.PENDING, total=Decimal("100"), idempotency_key=key,
        )

    def test_duplicate_key_is_rejected(self):
        self._order("co_ABC")
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                self._order("co_ABC")

    def test_blank_keys_are_not_constrained(self):
        # Other paths (POS/admin) may leave the key blank — those stay unconstrained.
        self._order("")
        self._order("")
        self.assertEqual(Order.objects.filter(idempotency_key="").count(), 2)

    def test_same_key_different_users_ok(self):
        other = User.objects.create(phone="+910000000078", name="Other")
        self._order("co_XYZ")
        Order.objects.create(
            user=other, payment_method=Order.PaymentMethod.UPI,
            status=OrderStatus.PENDING, total=Decimal("100"), idempotency_key="co_XYZ",
        )
        self.assertEqual(Order.objects.filter(idempotency_key="co_XYZ").count(), 2)


class ObjectOwnershipSecurityTests(TestCase):
    """IDOR guard (regression): a user must never read or mutate another user's
    order by guessing its code. Locks in the `user=request.user` scoping."""

    def setUp(self):
        from rest_framework.test import APIClient

        self.alice = User.objects.create(phone="+919000000061", name="Alice")
        self.bob = User.objects.create(phone="+919000000062", name="Bob")
        self.order = Order.objects.create(
            user=self.alice, payment_method=Order.PaymentMethod.COD,
            status=OrderStatus.CONFIRMED, total=Decimal("100"),
        )
        self.alice_c = APIClient()
        self.alice_c.force_authenticate(self.alice)
        self.bob_c = APIClient()
        self.bob_c.force_authenticate(self.bob)

    def test_owner_can_read_own_order(self):
        self.assertEqual(
            self.alice_c.get(f"/api/v1/orders/{self.order.code}").status_code, 200)

    def test_other_user_cannot_read_order(self):
        self.assertEqual(
            self.bob_c.get(f"/api/v1/orders/{self.order.code}").status_code, 404)

    def test_other_user_cannot_read_invoice_or_tracking(self):
        self.assertEqual(
            self.bob_c.get(f"/api/v1/orders/{self.order.code}/invoice").status_code, 404)
        self.assertEqual(
            self.bob_c.get(f"/api/v1/orders/{self.order.code}/tracking").status_code, 404)

    def test_other_user_cannot_cancel_order(self):
        self.assertEqual(
            self.bob_c.post(f"/api/v1/orders/{self.order.code}/cancel").status_code, 404)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, OrderStatus.CONFIRMED)  # untouched

    def test_anonymous_cannot_read_order(self):
        from rest_framework.test import APIClient

        self.assertIn(
            APIClient().get(f"/api/v1/orders/{self.order.code}").status_code, (401, 403))


class TrackingLocationTests(TestCase):
    """The order-tracking payload carries the real store + delivery-address
    coordinates so the customer map draws the true route, not a placeholder."""

    def test_tracking_exposes_store_and_destination_coords(self):
        from stores.models import Store

        from .models import Order, OrderTracking
        from .serializers import TrackingSerializer

        user = User.objects.create(phone="+919000000765", name="Cust")
        store = Store.objects.create(
            code="TS1", name="Track Store", status=Store.Status.ACTIVE,
            latitude=Decimal("12.971600"), longitude=Decimal("77.594600"),
        )
        order = Order.objects.create(
            user=user, store=store, payment_method=Order.PaymentMethod.COD,
            status=OrderStatus.CONFIRMED, total=Decimal("100"),
            address_snapshot={"latitude": 12.9200, "longitude": 77.6100,
                              "formatted": "12 MG Rd"},
        )
        tracking, _ = OrderTracking.objects.get_or_create(order=order)
        data = TrackingSerializer(tracking).data
        self.assertAlmostEqual(data["store_lat"], 12.9716, places=4)
        self.assertAlmostEqual(data["store_lng"], 77.5946, places=4)
        self.assertAlmostEqual(data["dest_lat"], 12.92, places=4)
        self.assertAlmostEqual(data["dest_lng"], 77.61, places=4)

    def test_tracking_null_coords_when_absent(self):
        from .models import Order, OrderTracking
        from .serializers import TrackingSerializer

        user = User.objects.create(phone="+919000000766", name="Cust2")
        order = Order.objects.create(
            user=user, payment_method=Order.PaymentMethod.COD,
            status=OrderStatus.CONFIRMED, total=Decimal("100"),
        )
        tracking, _ = OrderTracking.objects.get_or_create(order=order)
        data = TrackingSerializer(tracking).data
        self.assertIsNone(data["store_lat"])
        self.assertIsNone(data["dest_lat"])


class MinimumOrderEnforcementTests(TestCase):
    """A zone's minimum order value was configured, displayed on the bill, and
    then never checked — a zone set to ₹1,000 accepted a ₹300 order. The gate has
    to live on the server: the app's Place Order button is a courtesy, not a
    control (a replayed or crafted request skips it entirely).
    """

    SQUARE = {
        "type": "Polygon",
        "coordinates": [[
            [77.55, 12.95], [77.65, 12.95], [77.65, 13.00],
            [77.55, 13.00], [77.55, 12.95],
        ]],
    }

    def setUp(self):
        from addresses.models import Address
        from cart.services import get_cart, upsert_item
        from stores.models import Store
        from zones.models import Zone

        self.upsert_item, self.get_cart = upsert_item, get_cart
        self.wh = Warehouse.objects.create(name="MinWh", code="MINWH", is_default=True)
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Dal", brand="VS", unit="1 kg", price=Decimal("100"),
            mrp=Decimal("120"), category=cat, stock_count=None,
        )
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh,
            type=InventoryLedger.Type.GRN, quantity=200,
        )
        self.store = Store.objects.create(
            code="MS1", name="Min Store", warehouse=self.wh,
            status=Store.Status.ACTIVE,
        )
        self.zone = Zone.objects.create(
            code="MZ1", name="Min Zone", polygon_geojson=self.SQUARE,
            store=self.store, is_active=True, priority=9,
            min_order=Decimal("1000"),
        )
        self.user = User.objects.create(phone="+910000000088", name="MinCust")
        self.address = Address.objects.create(
            user=self.user, name="MinCust", phone="9000000088", line1="MG Rd",
            latitude=Decimal("12.97"), longitude=Decimal("77.60"), pincode="560001",
        )

    def _order(self, qty):
        from .services import place_order

        self.upsert_item(self.get_cart(self.user), self.product, None, qty)
        return place_order(
            self.user, address=self.address, payment_method=Order.PaymentMethod.COD
        )

    def test_below_minimum_is_refused_with_the_shortfall(self):
        from .services import CheckoutError

        with self.assertRaises(CheckoutError) as ctx:
            self._order(3)  # ₹300 against a ₹1,000 minimum
        self.assertEqual(ctx.exception.code, "MIN_ORDER_NOT_MET")
        self.assertIn("1,000", str(ctx.exception))
        self.assertIn("700", str(ctx.exception))  # the shortfall, spelled out
        self.assertEqual(Order.objects.filter(user=self.user).count(), 0)

    def test_at_the_minimum_is_allowed(self):
        order = self._order(10)  # exactly ₹1,000
        self.assertIsNotNone(order.pk)

    def test_fees_do_not_count_toward_the_minimum(self):
        """Delivery/GST/platform fees are not goods. Counting them would let a
        ₹900 basket clear a ₹1,000 minimum on charges alone."""
        from .services import CheckoutError

        with self.assertRaises(CheckoutError) as ctx:
            self._order(9)  # ₹900 subtotal; total-with-fees exceeds ₹1,000
        self.assertEqual(ctx.exception.code, "MIN_ORDER_NOT_MET")

    def test_zone_without_a_minimum_is_unaffected(self):
        self.zone.min_order = None
        self.zone.save(update_fields=["min_order"])
        # PlatformConfig default is 0, so nothing should gate.
        self.assertIsNotNone(self._order(1).pk)

    def test_api_surfaces_the_actionable_code(self):
        from rest_framework.test import APIClient

        self.upsert_item(self.get_cart(self.user), self.product, None, 2)
        client = APIClient()
        client.force_authenticate(self.user)
        r = client.post(
            "/api/v1/checkout",
            {"addressId": str(self.address.id), "paymentMethod": "cod"},
            format="json",
        )
        self.assertEqual(r.status_code, 400, r.content)
        body = r.json()
        self.assertEqual(body["code"], "MIN_ORDER_NOT_MET")
        self.assertIn("Minimum order value", body["message"])
