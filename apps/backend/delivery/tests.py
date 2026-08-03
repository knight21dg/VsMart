import io
import tempfile
from decimal import Decimal

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.utils import timezone
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from core.app_errors import AppError
from inventory.models import InventoryLedger, Warehouse
from inventory.services import InventoryService, StockCalculationService
from mediastore.models import MediaAsset
from orders.models import Order, OrderItem, OrderStatus

from . import services
from .models import DeliveryEarnings, DeliveryTask

DEST = (Decimal("12.975000"), Decimal("77.600000"))
FAR = (Decimal("13.500000"), Decimal("78.500000"))


def _order(customer, *, method=Order.PaymentMethod.COD, total="300", reserved=False):
    order = Order.objects.create(
        user=customer, payment_method=method, status=OrderStatus.PACKED,
        total=Decimal(total), stock_state=(
            Order.StockState.RESERVED if reserved else Order.StockState.NONE),
        address_snapshot={"name": "Cust", "phone": "+919000000090",
                          "formatted": "42, Indiranagar", "pincode": "560038",
                          "latitude": float(DEST[0]), "longitude": float(DEST[1])},
    )
    return order


class DeliveryLifecycleTests(TestCase):
    def setUp(self):
        self.agent = User.objects.create(phone="+919777777090", name="Agent A", role="agent")
        self.customer = User.objects.create(phone="+919000000090", name="Cust", role="customer")
        self.order = _order(self.customer)
        # Auto-assign creates the task (agent has no profile → eligible).
        self.task = services.auto_assign(self.order)

    def test_auto_assignment(self):
        self.assertIsNotNone(self.task)
        self.assertEqual(self.task.agent_id, self.agent.id)
        self.assertEqual(self.task.status, "assigned")
        self.assertTrue(self.task.assignments.filter(action="auto_assigned").exists())

    def test_no_status_skipping(self):
        services.accept(self.task, self.agent)
        # ACCEPTED → OUT_FOR_DELIVERY is not allowed (must pick up first).
        with self.assertRaises(AppError) as ctx:
            services.out_for_delivery(self.task, self.agent)
        self.assertEqual(ctx.exception.code, "INVALID_DELIVERY_TRANSITION")

    def test_geofence_blocks_far_arrival(self):
        self._advance_to_out()
        with self.assertRaises(AppError) as ctx:
            services.arrive(self.task, self.agent, FAR[0], FAR[1])
        self.assertEqual(ctx.exception.code, "DELIVERY_LOCATION_MISMATCH")

    def test_otp_lockout(self):
        self._advance_to_out()
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        for _ in range(2):
            with self.assertRaises(AppError) as ctx:
                services.verify_otp(self.task, self.agent, "000000")
            self.assertEqual(ctx.exception.code, "INVALID_DELIVERY_OTP")
        with self.assertRaises(AppError) as ctx:
            services.verify_otp(self.task, self.agent, "000000")
        self.assertEqual(ctx.exception.code, "MANUAL_VERIFICATION_REQUIRED")
        self.task.refresh_from_db()
        self.assertTrue(self.task.manual_verification_required)

    def test_completion_guard_requires_otp_then_photo(self):
        self._advance_to_out()
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        self.task.refresh_from_db()
        otp = self.task.delivery_otp.code
        # No OTP yet → blocked.
        with self.assertRaises(AppError) as ctx:
            services.complete_delivery(self.task, self.agent)
        self.assertEqual(ctx.exception.code, "DELIVERY_OTP_REQUIRED")
        services.verify_otp(self.task, self.agent, otp)
        # OTP ok but no photo → blocked.
        with self.assertRaises(AppError) as ctx:
            services.complete_delivery(self.task, self.agent)
        self.assertEqual(ctx.exception.code, "DELIVERY_PHOTO_REQUIRED")

    def test_happy_path_delivers_and_pays(self):
        self._advance_to_out()
        services.log_location(self.agent, DEST[0], DEST[1], task=self.task)
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        self.task.refresh_from_db()
        otp = self.task.delivery_otp.code
        services.verify_otp(self.task, self.agent, otp)
        services.add_evidence(self.task, self.agent, "pod/photo.jpg",
                              lat=DEST[0], lng=DEST[1])
        services.complete_delivery(self.task, self.agent)
        self.task.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.task.status, "delivered")
        self.assertEqual(self.order.status, "delivered")
        self.assertTrue(DeliveryEarnings.objects.filter(task=self.task, released=True).exists())
        # Live tracking was mirrored for the customer.
        from orders.models import OrderTracking
        self.assertTrue(OrderTracking.objects.filter(order=self.order).exists())

    def _advance_to_out(self):
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        self.task.refresh_from_db()


class DeliveryCreditCaptureTests(TestCase):
    """A credit order's debt is only posted to the ledger once the agent
    actually completes delivery — not at checkout. See
    orders.services.place_order / pending_credit_exposure / advance_status."""

    def setUp(self):
        self.agent = User.objects.create(phone="+919777777091", name="Agent B", role="agent")
        self.customer = User.objects.create(phone="+919000000091", name="Cust B", role="customer")
        self.order = _order(self.customer, method=Order.PaymentMethod.CREDIT, total="300")
        self.order.credit_used = self.order.total
        self.order.save(update_fields=["credit_used"])
        self.task = services.auto_assign(self.order)

    def _deliver(self):
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        self.task.refresh_from_db()
        services.verify_otp(self.task, self.agent, self.task.delivery_otp.code)
        services.add_evidence(self.task, self.agent, "pod/photo.jpg",
                              lat=DEST[0], lng=DEST[1])
        services.complete_delivery(self.task, self.agent)

    def test_credit_untouched_before_delivery(self):
        from credit.services import ensure_account

        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        acct = ensure_account(self.customer)
        self.assertEqual(acct.outstanding, Decimal("0.00"))

    def test_credit_charged_on_delivery(self):
        from credit.models import CreditLedgerEntry
        from credit.services import ensure_account

        self._deliver()
        acct = ensure_account(self.customer)
        acct.refresh_from_db()
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "delivered")
        self.assertEqual(acct.outstanding, Decimal("300.00"))
        self.assertTrue(acct.entries.filter(
            type=CreditLedgerEntry.Type.PURCHASE, order=self.order).exists())

    def test_delivery_charges_even_over_limit(self):
        """Once physically delivered, the debt is recorded regardless of the
        account's current limit — the goods already changed hands."""
        from credit.models import CreditAccount
        from credit.services import ensure_account

        acct = ensure_account(self.customer)
        acct.credit_limit = Decimal("1")  # far below the order's ₹300
        acct.save(update_fields=["credit_limit"])
        self._deliver()
        acct.refresh_from_db()
        self.assertEqual(acct.outstanding, Decimal("300.00"))
        self.assertEqual(acct.status, CreditAccount.Status.ACTIVE)


class DeliveryFailureReturnTests(TestCase):
    def setUp(self):
        self.wh = Warehouse.objects.create(name="Main", code="MAIN", is_default=True)
        cat, _ = Category.objects.get_or_create(name="Grocery", slug="grocery")
        self.product = Product.objects.create(
            name="Rice", brand="VS", unit="1 kg", price=Decimal("50"),
            mrp=Decimal("60"), category=cat, stock_count=100, available_count=100)
        InventoryService.post_movement(
            product=self.product, warehouse=self.wh, type=InventoryLedger.Type.GRN,
            quantity=10)
        self.agent = User.objects.create(phone="+919777777091", name="Agent B", role="agent")
        self.customer = User.objects.create(phone="+919000000091", name="Cust2", role="customer")
        self.order = _order(self.customer, method=Order.PaymentMethod.CREDIT,
                            total="300", reserved=True)
        OrderItem.objects.create(order=self.order, product=self.product, name="Rice",
                                 quantity=2, price=Decimal("50"), mrp=Decimal("60"))
        InventoryService.reserve(product=self.product, quantity=2, warehouse=self.wh)
        self.task = services.auto_assign(self.order)

    def test_failed_then_return_to_store_restores_stock(self):
        before = StockCalculationService.available(self.product, self.wh)  # reservation held
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        services.fail_delivery(self.task, self.agent,
                               reason_code="FAILED_CUSTOMER_UNREACHABLE", note="No answer")
        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "failed")
        self.assertTrue(self.task.attempts.exists())
        # Admin returns it to store → reservation freed (+2), order cancelled.
        services.return_to_store(self.task, by=self.customer)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "cancelled")
        self.assertEqual(StockCalculationService.available(self.product, self.wh), before + 2)


class AdminDeliveryTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919888888090", name="Admin", role="admin")
        self.agent = User.objects.create(phone="+919777777092", name="Agent A", role="agent")
        self.agent2 = User.objects.create(phone="+919777777093", name="Agent B", role="agent")
        self.customer = User.objects.create(phone="+919000000092", name="Cust", role="customer")
        self.order = _order(self.customer)
        self.task = DeliveryTask.objects.create(
            order=self.order, agent=self.agent, status="out_for_delivery",
            out_for_delivery_at=timezone.now())
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_dashboard(self):
        r = self.client.get("/api/v1/admin/delivery/dashboard")
        self.assertEqual(r.status_code, 200)

    def test_reassign_opens_new_task(self):
        r = self.client.post(f"/api/v1/admin/delivery/{self.task.id}/reassign",
                             {"agentId": str(self.agent2.id)}, format="json")
        self.assertEqual(r.status_code, 200)
        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "reassigned")
        self.assertTrue(DeliveryTask.objects.filter(
            order=self.order, agent=self.agent2, status="assigned").exists())

    def test_command_center(self):
        r = self.client.get("/api/v1/admin/delivery/command-center")
        self.assertEqual(r.status_code, 200)
        self.assertIn("kpis", r.json()["data"])

    def test_manual_assign(self):
        order2 = _order(self.customer)
        r = self.client.post("/api/v1/admin/delivery/assign",
                             {"orderCode": order2.code, "agentId": str(self.agent.id)},
                             format="json")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(DeliveryTask.objects.filter(order=order2, agent=self.agent).exists())


def _png_upload(name="pod.png", w=400, h=300, color=(40, 120, 200)):
    img = Image.new("RGB", (w, h), color)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(prefix="vsmart-pod-"),
                   MEDIA_INTERNAL_REDIRECT_PREFIX="")
class PodPhotoMediaTests(TestCase):
    """The POD photo is ingested through the self-hosted media engine and served
    through a permission-gated endpoint (customer / delivering agent / staff)."""

    def setUp(self):
        self.agent = User.objects.create(phone="+919000100010", name="Agent", role="agent")
        self.other_agent = User.objects.create(phone="+919000100011", name="Other", role="agent")
        self.customer = User.objects.create(phone="+919000100012", name="Cust", role="customer")
        self.stranger = User.objects.create(phone="+919000100013", name="Stranger", role="customer")
        self.admin = User.objects.create(phone="+919000100014", name="Admin", role="admin")
        self.order = _order(self.customer)
        self.task = DeliveryTask.objects.create(
            order=self.order, agent=self.agent, status="reached",
            reached_at=timezone.now())
        self.client = APIClient()

    # ── upload ──
    def test_service_stores_pod_photo_as_media_asset(self):
        before = MediaAsset.objects.count()
        ev = services.add_evidence(self.task, self.agent, photo=_png_upload())
        self.assertEqual(MediaAsset.objects.count(), before + 1)
        asset = MediaAsset.objects.get(pk=ev.file_key)
        self.assertEqual(asset.category, "pod")
        self.assertEqual(asset.visibility, "private")
        self.assertEqual(asset.owner_id, self.customer.id)
        self.task.refresh_from_db()
        self.assertEqual(self.task.photo_key, str(asset.id))

    def test_photo_endpoint_uploads_via_multipart(self):
        self.client.force_authenticate(self.agent)
        resp = self.client.post(
            f"/api/v1/deliveries/{self.task.id}/photo",
            {"photo": _png_upload()}, format="multipart")
        self.assertEqual(resp.status_code, 200)
        self.task.refresh_from_db()
        self.assertTrue(self.task.photo_key)
        self.assertTrue(MediaAsset.objects.filter(pk=self.task.photo_key).exists())

    def test_legacy_json_photo_key_still_works(self):
        # Back-compat: a loose string key with no file upload.
        self.client.force_authenticate(self.agent)
        resp = self.client.post(
            f"/api/v1/deliveries/{self.task.id}/photo",
            {"photo_key": "pod/legacy.jpg"}, format="json")
        self.assertEqual(resp.status_code, 200)
        self.task.refresh_from_db()
        self.assertEqual(self.task.photo_key, "pod/legacy.jpg")
        self.assertFalse(MediaAsset.objects.exists())

    # ── gated serving ──
    def _attach_photo(self):
        services.add_evidence(self.task, self.agent, photo=_png_upload())
        self.task.refresh_from_db()

    def test_customer_can_fetch_photo(self):
        self._attach_photo()
        self.client.force_authenticate(self.customer)
        resp = self.client.get(f"/api/v1/deliveries/{self.task.id}/proof-photo")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp["Content-Type"], "image/webp")

    def test_agent_can_fetch_photo(self):
        self._attach_photo()
        self.client.force_authenticate(self.agent)
        resp = self.client.get(f"/api/v1/deliveries/{self.task.id}/proof-photo")
        self.assertEqual(resp.status_code, 200)

    def test_staff_can_fetch_photo(self):
        self._attach_photo()
        self.client.force_authenticate(self.admin)
        resp = self.client.get(f"/api/v1/deliveries/{self.task.id}/proof-photo")
        self.assertEqual(resp.status_code, 200)

    def test_stranger_is_forbidden(self):
        self._attach_photo()
        self.client.force_authenticate(self.stranger)
        resp = self.client.get(f"/api/v1/deliveries/{self.task.id}/proof-photo")
        self.assertEqual(resp.status_code, 403)
        self.assertEqual(resp.json()["code"], "INSUFFICIENT_PERMISSIONS")

    def test_other_agent_is_forbidden(self):
        self._attach_photo()
        self.client.force_authenticate(self.other_agent)
        resp = self.client.get(f"/api/v1/deliveries/{self.task.id}/proof-photo")
        self.assertEqual(resp.status_code, 403)

    def test_missing_photo_gives_404(self):
        # No photo attached to this task.
        self.client.force_authenticate(self.customer)
        resp = self.client.get(f"/api/v1/deliveries/{self.task.id}/proof-photo")
        self.assertEqual(resp.status_code, 404)
        self.assertEqual(resp.json()["code"], "NOT_FOUND")


class LiveTrackingPublishTests(TestCase):
    """Only the order's CURRENT, LIVE delivery task may drive the customer-facing
    tracking row. A closed or superseded task that keeps pinging used to overwrite
    it — leaking the rider's position after the trip and showing the wrong rider's
    phone number after a reassignment."""

    def setUp(self):
        self.agent = User.objects.create(
            phone="+919777777200", name="Agent Live", role="agent")
        self.customer = User.objects.create(
            phone="+919000000200", name="Cust Live", role="customer")
        self.order = _order(self.customer)
        self.task = services.auto_assign(self.order)

    def _tracking(self):
        from orders.models import OrderTracking
        return OrderTracking.objects.filter(order=self.order).first()

    def _advance_to_out(self):
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)

    def test_live_task_publishes_position(self):
        self._advance_to_out()
        services.log_location(self.agent, DEST[0], DEST[1], task=self.task)
        t = self._tracking()
        self.assertEqual(t.latitude, DEST[0])
        self.assertEqual(t.longitude, DEST[1])

    def test_closed_task_ping_does_not_move_the_customer_pin(self):
        """Post-delivery location leak: the agent's phone keeps posting after the
        trip ends, and the customer watched them drive away."""
        self._advance_to_out()
        services.log_location(self.agent, DEST[0], DEST[1], task=self.task)

        self.task.status = DeliveryTask.Status.DELIVERED
        self.task.save(update_fields=["status"])
        services.log_location(self.agent, FAR[0], FAR[1], task=self.task)

        t = self._tracking()
        self.assertEqual(t.latitude, DEST[0], "closed task overwrote live coords")
        self.assertEqual(t.longitude, DEST[1])

    def test_superseded_task_cannot_overwrite_the_new_riders_identity(self):
        """The reassignment case: the customer must never be shown — and never
        phone — an agent who is no longer bringing their order."""
        self._advance_to_out()
        old_task = self.task

        new_agent = User.objects.create(
            phone="+919777777201", name="Agent New", role="agent")
        old_task.status = DeliveryTask.Status.REASSIGNED
        old_task.save(update_fields=["status"])
        new_task = DeliveryTask.objects.create(
            order=self.order, agent=new_agent,
            status=DeliveryTask.Status.OUT_FOR_DELIVERY, attempt_no=2)
        services._seed_tracking_identity(new_task)

        services.log_location(self.agent, FAR[0], FAR[1], task=old_task)

        t = self._tracking()
        self.assertEqual(t.agent_phone, new_agent.phone)
        self.assertEqual(t.agent_name, "Agent New")
        self.assertNotEqual(t.latitude, FAR[0])

        # The current rider still publishes normally.
        services.log_location(new_agent, DEST[0], DEST[1], task=new_task)
        self.assertEqual(self._tracking().latitude, DEST[0])

    def test_raw_ping_is_still_recorded_for_audit_when_suppressed(self):
        from .models import DeliveryLocation
        self._advance_to_out()
        self.task.status = DeliveryTask.Status.DELIVERED
        self.task.save(update_fields=["status"])
        services.log_location(self.agent, FAR[0], FAR[1], task=self.task)
        self.assertTrue(
            DeliveryLocation.objects.filter(task=self.task, latitude=FAR[0]).exists())


class TrackingReadIsSideEffectFreeTests(TestCase):
    """`GET /orders/<code>/tracking` used to get_or_create, so viewing (or the
    app's poll) wrote a row for every order ever opened."""

    def setUp(self):
        self.customer = User.objects.create(
            phone="+919000000210", name="Cust Read", role="customer")
        self.order = _order(self.customer)
        self.client = APIClient()
        self.client.force_authenticate(self.customer)

    def test_get_does_not_create_a_tracking_row(self):
        from orders.models import OrderTracking
        r = self.client.get(f"/api/v1/orders/{self.order.code}/tracking")
        self.assertEqual(r.status_code, 200)
        self.assertFalse(OrderTracking.objects.filter(order=self.order).exists())

    def test_get_still_returns_route_endpoints_before_assignment(self):
        r = self.client.get(f"/api/v1/orders/{self.order.code}/tracking")
        self.assertEqual(r.status_code, 200)
        # `r.data` is pre-render, so keys are snake_case (the camelCase renderer
        # runs on the way out to the app).
        self.assertIsNotNone(r.data["dest_lat"])
        self.assertEqual(r.data["agent_phone"], "")


class GpsPrecisionTests(TestCase):
    """Device GPS doubles carry ~15 decimal places. The arrive/location/photo
    serializers used a strict 6-dp DecimalField and REJECTED them — a rider
    standing at the door was told "the information entered isn't valid". The
    server now quantizes to 6 dp (≈11 cm) instead of refusing the delivery."""

    def setUp(self):
        self.agent = User.objects.create(
            phone="+919777777300", name="Agent GPS", role="agent")
        self.customer = User.objects.create(
            phone="+919000000300", name="Cust GPS", role="customer")
        self.order = _order(self.customer)
        self.task = services.auto_assign(self.order)
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def test_arrive_accepts_full_precision_device_coordinates(self):
        r = self.client.post(
            f"/api/v1/deliveries/{self.task.id}/arrive",
            # Raw Geolocator-style doubles, near the destination.
            {"latitude": 12.975000123456789, "longitude": 77.60000098765432},
            format="json",
        )
        self.assertEqual(r.status_code, 200, r.data)
        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "reached")

    def test_far_arrival_is_still_geofenced_not_a_validation_error(self):
        r = self.client.post(
            f"/api/v1/deliveries/{self.task.id}/arrive",
            {"latitude": 13.500000123456789, "longitude": 78.50000098765432},
            format="json",
        )
        self.assertEqual(r.data["error"]["code"], "DELIVERY_LOCATION_MISMATCH")

    def test_junk_coordinates_still_fail_validation(self):
        r = self.client.post(
            f"/api/v1/deliveries/{self.task.id}/arrive",
            {"latitude": "not-a-number", "longitude": 77.6},
            format="json",
        )
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.data["error"]["code"], "VALIDATION_ERROR")

    def test_location_ping_accepts_full_precision(self):
        r = self.client.post(
            "/api/v1/deliveries/location",
            {"latitude": 12.975000999999999, "longitude": 77.60000012345678,
             "task_id": self.task.id},
            format="json",
        )
        self.assertIn(r.status_code, (200, 201), r.data)


class CustomerDeliveryOtpTests(TestCase):
    """The handover OTP must be readable by the customer on their own tracking
    endpoint WHILE the rider is at the door — it used to exist only as an
    in-app notification, buried in the inbox at the moment the rider asked
    for it."""

    def setUp(self):
        self.agent = User.objects.create(
            phone="+919777777400", name="Agent OTP", role="agent")
        self.customer = User.objects.create(
            phone="+919000000400", name="Cust OTP", role="customer")
        self.order = _order(self.customer)
        self.task = services.auto_assign(self.order)
        self.client = APIClient()
        self.client.force_authenticate(self.customer)

    def _tracking(self):
        return self.client.get(f"/api/v1/orders/{self.order.code}/tracking").data

    def test_no_otp_before_dispatch(self):
        self.assertEqual(self._tracking()["delivery_otp"], "")

    def test_no_otp_yet_while_just_out_for_delivery(self):
        """The OTP is generated on arrival, not when the trip starts — a rider
        who's still en route hasn't earned the customer a handover code yet."""
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        self.task.refresh_from_db()
        self.assertEqual(self._tracking()["delivery_otp"], "")

    def test_otp_appears_once_arrived(self):
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        self.task.refresh_from_db()
        self.assertEqual(
            self._tracking()["delivery_otp"], self.task.delivery_otp.code)

    def test_otp_disappears_after_verification(self):
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        self.task.refresh_from_db()
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        services.verify_otp(self.task, self.agent, self.task.delivery_otp.code)
        self.assertEqual(self._tracking()["delivery_otp"], "")

    def test_locked_otp_is_not_shown(self):
        """After the 3-attempt lockout the code is dead — showing it would tell
        the customer to keep reading out a code that can no longer work."""
        services.accept(self.task, self.agent)
        services.pick_up(self.task, self.agent)
        services.out_for_delivery(self.task, self.agent)
        self.task.refresh_from_db()
        services.arrive(self.task, self.agent, DEST[0], DEST[1])
        for _ in range(3):
            try:
                services.verify_otp(self.task, self.agent, "000000")
            except AppError:
                pass
        self.assertEqual(self._tracking()["delivery_otp"], "")

    def test_another_customer_cannot_read_the_otp(self):
        other = User.objects.create(phone="+919000000401", role="customer")
        self.client.force_authenticate(other)
        r = self.client.get(f"/api/v1/orders/{self.order.code}/tracking")
        self.assertEqual(r.status_code, 404)


class AdminDeliveryStatusGuardTests(TestCase):
    """The admin Delivery Control Center's "Mark Delivered" used to write
    task.status="delivered" raw — no OTP, no photo, no geofence — and (now
    that delivery is what triggers the credit debit + stock fulfilment)
    would let an admin charge a customer and release stock for a delivery
    nobody proved happened. Only delivery.services.complete_delivery() may
    reach "delivered" now."""

    def setUp(self):
        self.admin = User.objects.create(phone="+919888888500", name="Admin", role="admin")
        self.agent = User.objects.create(phone="+919777777500", name="Agent", role="agent")
        self.customer = User.objects.create(phone="+919000000500", name="Cust", role="customer")
        self.order = _order(self.customer)
        self.task = services.auto_assign(self.order)
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_admin_cannot_mark_delivered(self):
        r = self.client.post(f"/api/v1/admin/delivery/{self.task.id}/status",
                             {"status": "delivered"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.task.refresh_from_db()
        self.order.refresh_from_db()
        self.assertNotEqual(self.task.status, "delivered")
        self.assertNotEqual(self.order.status, "delivered")

    def test_admin_can_still_mark_out_for_delivery_and_failed(self):
        r = self.client.post(f"/api/v1/admin/delivery/{self.task.id}/status",
                             {"status": "started"}, format="json")
        self.assertEqual(r.status_code, 200, r.data)
        self.order.refresh_from_db()
        self.assertEqual(self.order.status, "out_for_delivery")
