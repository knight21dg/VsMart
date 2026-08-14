"""Store-Admin panel (storeops) tests.

Covers the things the standalone smoke scripts assert, but as isolated TestCases:
membership gate + store-scoped RBAC (incl. read/write permission split), cross-store
isolation (no data leak between stores), staff management, procurement->stock, the
full POS path (session / checkout / idempotency / out-of-stock / catalog), and the
ops endpoints (collections / reports / settings / audit).
"""
import itertools
import json

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import Role, User
from catalog.models import Category, Product
from inventory.models import StockItem, Warehouse
from orders.models import Order
from returns.models import ReturnItem, ReturnRequest
from storeops.models import StoreStaff
from storeops.permissions_catalog import ALL_PERMISSIONS, default_permissions_for
from stores.models import Store

_seq = itertools.count(1)


def _ph():
    return f"+91{9000000000 + next(_seq)}"


def _data(resp):
    return resp.json().get("data", resp.json())


def mk_store(name="Store", status="active"):
    n = next(_seq)
    wh = Warehouse.objects.create(name=f"WH{n}", code=f"WH-{n}", is_active=True)
    store = Store.objects.create(
        code=f"S-{n}", name=f"{name}-{n}", status=status, warehouse=wh,
        address="1 Test Rd", phone="0800",
    )
    return store


def mk_staff(store, role="manager", perms=None, active=True):
    user = User.objects.create(phone=_ph(), name=f"{role} {next(_seq)}", role=Role.STORE_STAFF)
    StoreStaff.objects.create(
        user=user, store=store, staff_role=role, is_active=active,
        permissions=perms if perms is not None else [],
    )
    return user


def client_for(user):
    c = APIClient()
    c.force_authenticate(user)
    return c


def mk_product(price=60, mrp=75):
    n = next(_seq)
    cat, _ = Category.objects.get_or_create(slug=f"cat{n}", defaults={"name": f"Cat{n}"})
    return Product.objects.create(
        name=f"Prod{n}", brand="B", unit="1 kg", price=price, mrp=mrp,
        category=cat, sku=f"SKU-{n}", is_active=True,
    )


def mk_customer():
    return User.objects.create(phone=_ph(), name=f"Cust{next(_seq)}", role=Role.CUSTOMER)


def mk_order(store, customer, **kw):
    n = next(_seq)
    return Order.objects.create(
        user=customer, store=store, code=kw.get("code", f"ORD-{n}"),
        total=kw.get("total", 500), subtotal=kw.get("subtotal", 500),
        status=kw.get("status", "delivered"), payment_method=kw.get("payment_method", "credit"),
        payment_status=kw.get("payment_status", "pending"), credit_used=kw.get("credit_used", 500),
    )


class StoreAccessTests(TestCase):
    """The membership gate + permission enforcement."""

    def setUp(self):
        self.store = mk_store()
        self.manager = mk_staff(self.store, "manager")

    def test_manager_me_holds_all_permissions(self):
        me = _data(client_for(self.manager).get("/api/v1/store/me"))
        self.assertTrue(me["isManager"])
        self.assertEqual(set(me["permissions"]), set(ALL_PERMISSIONS))

    def test_outsider_without_membership_is_blocked(self):
        outsider = mk_customer()
        self.assertEqual(client_for(outsider).get("/api/v1/store/me").status_code, 403)

    def test_inactive_staff_is_blocked(self):
        u = mk_staff(self.store, "cashier", perms=["dashboard.view"], active=False)
        self.assertEqual(client_for(u).get("/api/v1/store/me").status_code, 403)

    def test_inactive_store_is_blocked(self):
        closed = mk_store(status="inactive")
        u = mk_staff(closed, "manager")
        self.assertEqual(client_for(u).get("/api/v1/store/me").status_code, 403)

    def test_cashier_allowed_dashboard_blocked_staff(self):
        cashier = mk_staff(self.store, "cashier", perms=default_permissions_for("cashier"))
        c = client_for(cashier)
        self.assertEqual(c.get("/api/v1/store/dashboard").status_code, 200)  # has dashboard.view
        self.assertEqual(c.get("/api/v1/store/staff").status_code, 403)      # no employees.view

    def test_permission_read_write_split(self):
        # employees.view grants the list (read) but NOT create (needs employees.manage).
        viewer = mk_staff(self.store, "custom", perms=["employees.view"])
        c = client_for(viewer)
        self.assertEqual(c.get("/api/v1/store/staff").status_code, 200)
        r = c.post("/api/v1/store/staff", {"phone": _ph(), "name": "X", "staffRole": "cashier"},
                   format="json")
        self.assertEqual(r.status_code, 403)


class StoreScopeIsolationTests(TestCase):
    """A store user must NEVER see or touch another store's data."""

    def setUp(self):
        self.a = mk_store("A")
        self.b = mk_store("B")
        self.mgr_a = client_for(mk_staff(self.a, "manager"))
        # Distinct products stocked in each store's warehouse.
        self.pa, self.pb = mk_product(), mk_product()
        StockItem.objects.create(product=self.pa, warehouse=self.a.warehouse, quantity=50)
        StockItem.objects.create(product=self.pb, warehouse=self.b.warehouse, quantity=70)
        # A customer + order in each store.
        self.cust_a, self.cust_b = mk_customer(), mk_customer()
        self.ord_a = mk_order(self.a, self.cust_a)
        self.ord_b = mk_order(self.b, self.cust_b)

    def test_orders_scoped_to_own_store(self):
        text = json.dumps(_data(self.mgr_a.get("/api/v1/store/orders")))
        self.assertIn(self.ord_a.code, text)
        self.assertNotIn(self.ord_b.code, text)

    def test_other_store_order_detail_404(self):
        self.assertEqual(self.mgr_a.get(f"/api/v1/store/orders/{self.ord_b.code}").status_code, 404)

    def test_other_store_order_status_404(self):
        r = self.mgr_a.post(f"/api/v1/store/orders/{self.ord_b.code}/status",
                            {"status": "packed"}, format="json")
        self.assertEqual(r.status_code, 404)

    def test_inventory_scoped_to_own_warehouse(self):
        rows = _data(self.mgr_a.get("/api/v1/store/inventory"))
        pids = {r["productId"] for r in rows}
        self.assertIn(str(self.pa.id), pids)
        self.assertNotIn(str(self.pb.id), pids)

    def test_customers_scoped_to_own_store(self):
        text = json.dumps(_data(self.mgr_a.get("/api/v1/store/customers")))
        self.assertIn(self.cust_a.phone, text)
        self.assertNotIn(self.cust_b.phone, text)

    def test_other_store_customer_detail_404(self):
        self.assertEqual(
            self.mgr_a.get(f"/api/v1/store/customers/{self.cust_b.id}").status_code, 404)


class StoreOrderStatusRestrictionTests(TestCase):
    """A store can prep an order up to ready-for-dispatch; from there the
    assigned agent's own OTP + photo completion guard owns the rest."""

    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.customer = mk_customer()

    def _order(self, status):
        return mk_order(self.store, self.customer, status=status,
                        payment_method="cod", credit_used=0)

    def test_store_can_advance_up_to_ready_for_dispatch(self):
        order = self._order("confirmed")
        r = self.mgr.post(f"/api/v1/store/orders/{order.code}/status",
                          {"status": "ready_for_dispatch"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        order.refresh_from_db()
        self.assertEqual(order.status, "ready_for_dispatch")

    def test_store_cannot_set_out_for_delivery(self):
        order = self._order("ready_for_dispatch")
        r = self.mgr.post(f"/api/v1/store/orders/{order.code}/status",
                          {"status": "out_for_delivery"}, format="json")
        self.assertEqual(r.status_code, 400)
        order.refresh_from_db()
        self.assertEqual(order.status, "ready_for_dispatch")

    def test_store_cannot_mark_delivered(self):
        order = self._order("ready_for_dispatch")
        r = self.mgr.post(f"/api/v1/store/orders/{order.code}/status",
                          {"status": "delivered"}, format="json")
        self.assertEqual(r.status_code, 400)
        order.refresh_from_db()
        self.assertEqual(order.status, "ready_for_dispatch")

    def test_store_can_still_cancel(self):
        order = self._order("confirmed")
        r = self.mgr.post(f"/api/v1/store/orders/{order.code}/status",
                          {"status": "cancelled"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())

    def test_store_delivery_task_status_is_no_longer_writable(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        order = self._order("ready_for_dispatch")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        task = DeliveryTask.objects.create(order=order, agent=agent, status="out_for_delivery")
        r = self.mgr.post(f"/api/v1/store/delivery/{task.id}/status",
                          {"status": "delivered"}, format="json")
        self.assertEqual(r.status_code, 400)
        task.refresh_from_db()
        order.refresh_from_db()
        self.assertEqual(task.status, "out_for_delivery")
        self.assertEqual(order.status, "ready_for_dispatch")

    def test_order_detail_surfaces_the_live_delivery_otp_for_staff(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryOTP, DeliveryTask

        order = self._order("out_for_delivery")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        task = DeliveryTask.objects.create(order=order, agent=agent, status="out_for_delivery")
        DeliveryOTP.objects.create(task=task, code="482913", generated_at=None)
        d = _data(self.mgr.get(f"/api/v1/store/orders/{order.code}"))
        self.assertEqual(d["delivery"]["otp"], "482913")

    def test_order_detail_hides_a_verified_otp(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryOTP, DeliveryTask

        order = self._order("out_for_delivery")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        task = DeliveryTask.objects.create(order=order, agent=agent, status="out_for_delivery")
        DeliveryOTP.objects.create(task=task, code="482913", verified=True)
        d = _data(self.mgr.get(f"/api/v1/store/orders/{order.code}"))
        self.assertEqual(d["delivery"]["otp"], "")

    def test_order_detail_surfaces_the_confirmation_photo_url(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        order = self._order("delivered")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        task = DeliveryTask.objects.create(
            order=order, agent=agent, status="delivered", photo_key="9999")
        d = _data(self.mgr.get(f"/api/v1/store/orders/{order.code}"))
        self.assertEqual(d["delivery"]["photoUrl"], f"/deliveries/{task.id}/proof-photo")

    def test_order_detail_photo_url_null_without_a_photo(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        order = self._order("out_for_delivery")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        DeliveryTask.objects.create(order=order, agent=agent, status="out_for_delivery")
        d = _data(self.mgr.get(f"/api/v1/store/orders/{order.code}"))
        self.assertIsNone(d["delivery"]["photoUrl"])

    def test_store_staff_can_load_the_proof_photo(self):
        """The bytes actually come back — not merely "didn't 403".

        This used to assert `status_code not in (403, 404)` against an asset with
        no file behind it, so it passed on the 500 that a missing file produced.
        A missing file is now an honest 404, which turned the weak assertion into
        a failure and exposed that the test had never proven delivery is
        viewable at all. It writes a real file so it does.
        """
        from django.core.files.base import ContentFile
        from django.core.files.storage import default_storage

        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask
        from mediastore.models import MediaAsset

        order = self._order("delivered")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        asset = MediaAsset.objects.create(
            category="delivery_pod", owner=agent, visibility="private",
            content_type="image/webp",
        )
        key = default_storage.save(
            asset.variant_key("medium"), ContentFile(b"proof-bytes")
        )

        task = DeliveryTask.objects.create(
            order=order, agent=agent, status="delivered", photo_key=str(asset.id))
        r = self.mgr.get(f"/api/v1/deliveries/{task.id}/proof-photo")
        self.assertEqual(r.status_code, 200)
        body = b"".join(r.streaming_content)
        # Close before deleting — Windows refuses to unlink a file the
        # FileResponse still holds open.
        r.close()
        self.addCleanup(default_storage.delete, key)
        self.assertEqual(body, b"proof-bytes")

    def test_a_proof_photo_whose_file_is_gone_is_a_404_not_a_500(self):
        """A store manager opening delivery proof for an asset whose bytes have
        been lost must be told the image is gone, not that the server broke."""
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask
        from mediastore.models import MediaAsset

        order = self._order("delivered")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        asset = MediaAsset.objects.create(
            category="delivery_pod", owner=agent, visibility="private",
            content_type="image/webp",
        )
        task = DeliveryTask.objects.create(
            order=order, agent=agent, status="delivered", photo_key=str(asset.id))
        r = self.mgr.get(f"/api/v1/deliveries/{task.id}/proof-photo")
        self.assertEqual(r.status_code, 404, r.content)
        self.assertIn("no longer available", r.json()["message"])

    def test_other_stores_staff_cannot_load_the_proof_photo(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask
        from mediastore.models import MediaAsset

        order = self._order("delivered")
        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", store=self.store)
        asset = MediaAsset.objects.create(
            category="delivery_pod", owner=agent, visibility="private",
            content_type="image/webp",
        )
        task = DeliveryTask.objects.create(
            order=order, agent=agent, status="delivered", photo_key=str(asset.id))
        other_store = mk_store()
        other_mgr = client_for(mk_staff(other_store, "manager"))
        r = other_mgr.get(f"/api/v1/deliveries/{task.id}/proof-photo")
        self.assertEqual(r.status_code, 403)


class StoreStaffTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.manager_user = mk_staff(self.store, "manager")
        self.mgr = client_for(self.manager_user)

    def test_hire_cashier_applies_default_permissions(self):
        created = _data(self.mgr.post("/api/v1/store/staff", {
            "phone": _ph(), "name": "New Cashier", "staffRole": "cashier",
            "email": f"cashier{next(_seq)}@vsmart.test", "password": "s3cret-pass",
        }, format="json"))
        staff = StoreStaff.objects.get(id=created["id"])
        self.assertEqual(staff.staff_role, "cashier")
        self.assertEqual(set(staff.permissions), set(default_permissions_for("cashier")))

    def test_update_permissions(self):
        created = _data(self.mgr.post("/api/v1/store/staff", {
            "phone": _ph(), "name": "C", "staffRole": "cashier",
            "email": f"perm{next(_seq)}@vsmart.test", "password": "s3cret-pass"}, format="json"))
        self.mgr.patch(f"/api/v1/store/staff/{created['id']}",
                       {"permissions": ["dashboard.view", "inventory.view"]}, format="json")
        staff = StoreStaff.objects.get(id=created["id"])
        self.assertEqual(set(staff.permissions), {"dashboard.view", "inventory.view"})

    def test_manager_cannot_deactivate_self(self):
        sid = StoreStaff.objects.get(user=self.manager_user).id
        r = self.mgr.patch(f"/api/v1/store/staff/{sid}", {"isActive": False}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_deactivate_staff_works(self):
        # isActive must actually take effect (camelCase body → field()).
        created = _data(self.mgr.post("/api/v1/store/staff", {
            "phone": _ph(), "name": "C", "staffRole": "cashier",
            "email": f"deact{next(_seq)}@vsmart.test", "password": "s3cret-pass"}, format="json"))
        self.mgr.patch(f"/api/v1/store/staff/{created['id']}", {"isActive": False}, format="json")
        self.assertFalse(StoreStaff.objects.get(id=created["id"]).is_active)

    def test_attendance_check_in(self):
        r = self.mgr.post("/api/v1/store/staff/attendance/check-in", {}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertIsNotNone(_data(r)["checkInAt"])

    def test_my_attendance_reports_server_truth(self):
        """The panel's clock-in button used to keep a local boolean that reset to
        "out" on every remount. It now reads this, so the state has to be real."""
        before = _data(self.mgr.get("/api/v1/store/staff/attendance/me"))
        self.assertFalse(before["clockedIn"])
        self.assertIsNone(before["checkInAt"])

        self.mgr.post("/api/v1/store/staff/attendance/check-in", {}, format="json")
        after = _data(self.mgr.get("/api/v1/store/staff/attendance/me"))
        self.assertTrue(after["clockedIn"])
        self.assertIsNotNone(after["checkInAt"])

        out = _data(self.mgr.post("/api/v1/store/staff/attendance/check-out", {}, format="json"))
        # The write returns the same shape, so the client can trust either.
        self.assertFalse(out["clockedIn"])
        self.assertIsNotNone(out["checkOutAt"])
        self.assertFalse(_data(self.mgr.get("/api/v1/store/staff/attendance/me"))["clockedIn"])

    def test_my_attendance_needs_no_employees_view_permission(self):
        """Everyone may read their own attendance — the roster endpoint's
        `employees.view` gate would lock a cashier out of their own clock."""
        cashier = client_for(mk_staff(self.store, "cashier"))
        self.assertEqual(
            cashier.get("/api/v1/store/staff/attendance/me").status_code, 200
        )


class StoreProcurementInventoryTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.product = mk_product()

    def test_purchase_increases_stock(self):
        r = self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV-1",
            "items": [{"productId": str(self.product.id), "quantity": 100, "unitCost": 40}],
        }, format="json")
        self.assertEqual(r.status_code, 201)
        rows = _data(self.mgr.get("/api/v1/store/inventory"))
        avail = next(x["available"] for x in rows if x["productId"] == str(self.product.id))
        self.assertEqual(avail, 100)

    def test_purchase_allocates_to_the_chosen_pack(self):
        """A pack is its own SKU. Receiving 40×1kg must land on the 1kg bucket —
        not in the variant=NULL pool, where POS can't sell it and every pack still
        reads zero."""
        from catalog.models import ProductVariant
        from inventory.models import GRNItem
        from inventory.services import StockCalculationService

        p = mk_product()
        half = ProductVariant.objects.create(product=p, label="500 g")
        one_kg = ProductVariant.objects.create(product=p, label="1 kg")

        r = self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV-VAR",
            "items": [{"productId": str(p.id), "variantId": str(one_kg.id),
                       "quantity": 40, "unitCost": 30}],
        }, format="json")
        self.assertEqual(r.status_code, 201, r.content)

        self.assertEqual(GRNItem.objects.get(product=p).variant_id, one_kg.id)
        wh = self.store.warehouse
        self.assertEqual(StockCalculationService.available(p, wh, variant=one_kg), 40)
        self.assertEqual(StockCalculationService.available(p, wh, variant=half), 0)
        # Nothing stranded in the unallocated pool.
        self.assertEqual(StockCalculationService.available(p, wh, variant=None), 0)

    def test_purchase_without_pack_is_rejected_for_variant_product(self):
        from catalog.models import ProductVariant
        from inventory.models import GRN

        p = mk_product()
        ProductVariant.objects.create(product=p, label="1 kg")
        r = self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV-NOPACK",
            "items": [{"productId": str(p.id), "quantity": 40, "unitCost": 30}],
        }, format="json")
        self.assertEqual(r.status_code, 400)
        # The operator must be told WHICH line to fix.
        self.assertIn("Line 1", r.content.decode())
        self.assertIn(p.name, r.content.decode())
        # Atomic: no phantom draft GRN left behind.
        self.assertEqual(GRN.objects.count(), 0)

    def test_purchase_rejects_a_foreign_variant(self):
        from catalog.models import ProductVariant

        p, other = mk_product(), mk_product()
        ProductVariant.objects.create(product=p, label="1 kg")
        foreign = ProductVariant.objects.create(product=other, label="1 kg")
        r = self.mgr.post("/api/v1/store/purchases", {
            "items": [{"productId": str(p.id), "variantId": str(foreign.id),
                       "quantity": 5, "unitCost": 10}],
        }, format="json")
        self.assertEqual(r.status_code, 400)

    def test_product_search_exposes_packs_and_matches_barcode(self):
        """The picker can't send a variantId it was never given — and goods-inward
        is a scanning desk, so a scanned code has to find the product."""
        from catalog.models import ProductVariant
        from inventory.models import Barcode

        p = mk_product()
        v = ProductVariant.objects.create(product=p, label="1 kg", sku="SKU-1KG")
        Barcode.objects.create(product=p, variant=v, code="8901234567890")

        rows = _data(self.mgr.get("/api/v1/store/products", {"q": "8901234567890"}))
        hit = next(x for x in rows if x["productId"] == str(p.id))
        self.assertEqual([pack["label"] for pack in hit["variants"]], ["1 kg"])
        self.assertEqual(hit["variants"][0]["barcode"], "8901234567890")
        self.assertEqual(hit["variants"][0]["id"], str(v.id))

    def test_inventory_adjust_set(self):
        StockItem.objects.create(product=self.product, warehouse=self.store.warehouse, quantity=10)
        r = self.mgr.post(f"/api/v1/store/inventory/{self.product.id}/adjust",
                          {"mode": "adjust", "set": 25, "reason": "count"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(_data(r)["onHand"], 25)


class StorePOSTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.product = mk_product(price=60, mrp=75)
        # Seed sellable stock via the proven purchase path, then open a till.
        self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV-POS",
            "items": [{"productId": str(self.product.id), "quantity": 100, "unitCost": 40}],
        }, format="json")
        self.mgr.post("/api/v1/store/pos/session", {"openingCash": 500}, format="json")

    def _available(self):
        rows = _data(self.mgr.get("/api/v1/store/inventory"))
        return next(x["available"] for x in rows if x["productId"] == str(self.product.id))

    def _checkout(self, qty, amount, key=None):
        kw = {"format": "json"}
        if key:
            kw["HTTP_IDEMPOTENCY_KEY"] = key
        return self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "qty": qty}],
            "payments": [{"method": "cash", "amount": amount}],
        }, **kw)

    def test_checkout_decrements_stock(self):
        r = self._checkout(3, 500)
        self.assertEqual(r.status_code, 201)
        self.assertEqual(self._available(), 97)

    def test_a_sub_unit_quantity_is_rejected_not_billed_as_zero(self):
        """0.5 used to bill as ZERO — `int(0.5)` is 0, and 0.5 is truthy so the
        `or 1` fallback never fired. The customer got free goods and the stock
        ledger never moved."""
        before = self._available()
        r = self._checkout(0.5, 500)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self._available(), before)

    def test_a_fractional_quantity_is_rejected_rather_than_truncated(self):
        before = self._available()
        r = self._checkout(1.35, 500)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(self._available(), before)

    def test_a_zero_or_negative_quantity_is_rejected(self):
        before = self._available()
        self.assertEqual(self._checkout(0, 500).status_code, 400)
        self.assertEqual(self._checkout(-2, 500).status_code, 400)
        self.assertEqual(self._available(), before)

    def test_checkout_requires_open_session(self):
        # A fresh manager with no session can't bill.
        other = client_for(mk_staff(self.store, "manager"))
        r = other.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "qty": 1}],
            "payments": [{"method": "cash", "amount": 100}],
        }, format="json")
        self.assertEqual(r.status_code, 400)

    def test_idempotent_replay_does_not_double_post(self):
        r1 = self._checkout(2, 200, key="dup-1")
        r2 = self._checkout(2, 200, key="dup-1")
        self.assertEqual(r1.status_code, 201)
        self.assertEqual(_data(r1)["code"], _data(r2)["code"])  # same sale
        self.assertEqual(self._available(), 98)                  # decremented once

    def test_out_of_stock_is_409(self):
        r = self._checkout(9999, 100, key="oos-1")
        self.assertEqual(r.status_code, 409)
        body = r.json()
        code = (body.get("error") or body.get("data", {}).get("error") or {}).get("code")
        self.assertEqual(code, "pos_out_of_stock")

    def test_catalog_snapshot_has_product(self):
        snap = _data(self.mgr.get("/api/v1/store/pos/catalog"))
        row = next((p for p in snap["products"] if p["productId"] == str(self.product.id)), None)
        self.assertIsNotNone(row)
        self.assertEqual(row["available"], 100)
        self.assertIn("barcode", row)
        # Card UI fields for the POS product dialog.
        self.assertIn("imageUrl", row)
        self.assertIn("variants", row)

    def test_pos_product_detail(self):
        d = _data(self.mgr.get(f"/api/v1/store/pos/product/{self.product.id}"))
        # App-style detail fields for the POS product dialog.
        for k in ("name", "brand", "unit", "price", "mrp", "discountPercent",
                  "gallery", "rating", "reviews", "description", "available", "variants"):
            self.assertIn(k, d)
        self.assertEqual(d["available"], 100)
        self.assertEqual(d["price"], 60.0)

    def test_checkout_bills_variant_price_delta(self):
        from catalog.models import ProductVariant
        from inventory.services import InventoryService

        # A +₹15 variant → POS search exposes it and checkout bills base+delta.
        large = ProductVariant.objects.create(
            product=self.product, label="Large", price_delta=15
        )
        # Stock the PACK. The 100 units seeded in setUp predate this variant, so they
        # sit in the unallocated pool and no pack can draw on them — a variant is its
        # own stock-keeping unit.
        InventoryService.adjust(
            self.product, variant=large, set=20,
            warehouse=self.store.warehouse, reason="test",
        )
        search = _data(self.mgr.get("/api/v1/store/pos/search", {"q": self.product.name}))
        row = next(p for p in search if p["productId"] == str(self.product.id))
        self.assertEqual(len(row["variants"]), 1)
        v = row["variants"][0]
        self.assertEqual(v["price"], 75.0)  # 60 base + 15 delta
        r = self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "variantId": v["id"], "qty": 2}],
            "payments": [{"method": "cash", "amount": 200}],
        }, format="json")
        self.assertEqual(r.status_code, 201, _data(r))
        line = _data(r)["items"][0]
        self.assertEqual(line["unitPrice"], 75.0)  # variant price honoured server-side

    def test_variants_hold_separate_stock(self):
        """Selling one pack must not move another pack's stock."""
        from catalog.models import ProductVariant
        from inventory.services import InventoryService, StockCalculationService

        wh = self.store.warehouse
        small = ProductVariant.objects.create(product=self.product, label="500g")
        large = ProductVariant.objects.create(product=self.product, label="1kg", price_delta=15)
        InventoryService.adjust(self.product, variant=small, set=8, warehouse=wh, reason="t")
        InventoryService.adjust(self.product, variant=large, set=3, warehouse=wh, reason="t")

        r = self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "variantId": str(large.id), "qty": 2}],
            "payments": [{"method": "cash", "amount": 200}],
        }, format="json")
        self.assertEqual(r.status_code, 201, _data(r))
        # The 1kg dropped; the 500g is untouched.
        self.assertEqual(StockCalculationService.available(self.product, wh, large), 1)
        self.assertEqual(StockCalculationService.available(self.product, wh, small), 8)

    def test_out_of_stock_pack_is_409_not_500(self):
        """A pack with no stock is a clean out-of-stock, even when its siblings and
        the product pool are flush — the guard must read the pack's own bucket."""
        from catalog.models import ProductVariant

        empty = ProductVariant.objects.create(product=self.product, label="5kg")
        r = self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "variantId": str(empty.id), "qty": 1}],
            "payments": [{"method": "cash", "amount": 500}],
        }, format="json")
        self.assertEqual(r.status_code, 409, _data(r))
        self.assertEqual(_data(r)["error"]["code"], "pos_out_of_stock")

    def test_unallocated_pool_cannot_be_sold_as_a_pack(self):
        """Stock received before the packs existed is counted but not sellable as any
        pack until it's allocated — it can't be silently spent as one."""
        from catalog.models import ProductVariant
        from inventory.services import InventoryService, StockCalculationService

        wh = self.store.warehouse
        v = ProductVariant.objects.create(product=self.product, label="1kg")
        # setUp put 100 in the pool; the pack itself has none.
        self.assertEqual(StockCalculationService.on_hand(self.product, wh, variant=None), 100)
        self.assertEqual(StockCalculationService.available(self.product, wh, v), 0)
        r = self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "variantId": str(v.id), "qty": 1}],
            "payments": [{"method": "cash", "amount": 100}],
        }, format="json")
        self.assertEqual(r.status_code, 409, _data(r))

        # Allocating conserves the total and makes it sellable.
        InventoryService.allocate(self.product, variant=v, quantity=10, warehouse=wh)
        self.assertEqual(StockCalculationService.on_hand(self.product, wh, variant=None), 90)
        self.assertEqual(StockCalculationService.available(self.product, wh, v), 10)
        self.assertEqual(StockCalculationService.on_hand(self.product, wh), 100)  # conserved

    def test_variant_in_stock_flag_is_per_pack(self):
        """`in_stock` follows each pack's own shelf, not the product's."""
        from catalog.models import ProductVariant
        from inventory.services import InventoryService

        wh = self.store.warehouse
        small = ProductVariant.objects.create(product=self.product, label="500g")
        large = ProductVariant.objects.create(product=self.product, label="1kg")
        InventoryService.adjust(self.product, variant=small, set=5, warehouse=wh, reason="t")
        InventoryService.adjust(self.product, variant=large, set=0, warehouse=wh, reason="t")
        small.refresh_from_db()
        large.refresh_from_db()
        self.assertTrue(small.in_stock)
        self.assertFalse(large.in_stock)

    def test_cannot_move_stock_on_a_pack_product_without_naming_the_pack(self):
        from catalog.models import ProductVariant
        from inventory.services import InventoryError, InventoryService

        ProductVariant.objects.create(product=self.product, label="1kg")
        with self.assertRaises(InventoryError):
            InventoryService.adjust(
                self.product, set=5, warehouse=self.store.warehouse, reason="t"
            )

    def test_session_close(self):
        self._checkout(1, 100)
        r = self.mgr.post("/api/v1/store/pos/session/close", {"countedCash": None}, format="json")
        self.assertEqual(r.status_code, 201)
        self.assertIn("totalSales", _data(r))

    def test_pos_requires_permission(self):
        # inventory-only staff can't operate the POS.
        inv = client_for(mk_staff(self.store, "inventory", perms=default_permissions_for("inventory")))
        self.assertEqual(inv.post("/api/v1/store/pos/session", {}, format="json").status_code, 403)


class StoreOpsExtraTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.customer = mk_customer()
        mk_order(self.store, self.customer)

    def test_reports_render(self):
        for name in ("sales", "inventory", "top-products", "credit"):
            self.assertEqual(self.mgr.get(f"/api/v1/store/reports/{name}").status_code, 200)

    def test_collection_create_and_collect(self):
        coll = _data(self.mgr.post("/api/v1/store/collections", {
            "customerId": str(self.customer.id), "amount": 200}, format="json"))
        self.assertIn("id", coll)
        r = self.mgr.post(f"/api/v1/store/collections/{coll['id']}/collect", {}, format="json")
        self.assertIn(r.status_code, (200, 201))

    def test_settings_patch(self):
        r = self.mgr.patch("/api/v1/store/settings", {"name": "Renamed Store"}, format="json")
        self.assertEqual(r.status_code, 200)
        self.store.refresh_from_db()
        self.assertEqual(self.store.name, "Renamed Store")

    def test_audit_log_reads(self):
        self.assertEqual(self.mgr.get("/api/v1/store/audit").status_code, 200)


class StoreDetailViewTests(TestCase):
    """Detail drawers wired this sprint: order, customer-360, return, KYC."""

    def setUp(self):
        self.store = mk_store()
        self.manager = mk_staff(self.store, "manager")
        self.mgr = client_for(self.manager)
        self.customer = mk_customer()
        self.order = mk_order(self.store, self.customer)

    def test_order_detail_returns_header_and_items(self):
        d = _data(self.mgr.get(f"/api/v1/store/orders/{self.order.code}"))
        self.assertEqual(d["header"]["code"], self.order.code)
        self.assertIn("items", d)
        self.assertIn("timeline", d)

    def test_customer_360_detail(self):
        d = _data(self.mgr.get(f"/api/v1/store/customers/{self.customer.id}"))
        self.assertIn("header", d)
        self.assertIn("health", d)
        self.assertIn("creditIntelligence", d)

    def _mk_return(self, store=None, status="requested"):
        ret = ReturnRequest.objects.create(
            user=self.customer, order=mk_order(store or self.store, self.customer),
            reason="damaged", status=status, refund_amount=200,
        )
        ReturnItem.objects.create(return_request=ret, product_name="Prod", quantity=1, amount=200)
        return ret

    def test_return_detail_returns_items(self):
        ret = self._mk_return()
        d = _data(self.mgr.get(f"/api/v1/store/returns/{ret.code}"))
        self.assertEqual(d["code"], ret.code)
        self.assertEqual(len(d["items"]), 1)

    def test_return_decision_captures_note_and_actor(self):
        ret = self._mk_return()
        r = self.mgr.post(f"/api/v1/store/returns/{ret.code}/status",
                          {"status": "approved", "note": "Verified the damage"}, format="json")
        self.assertEqual(r.status_code, 200)
        ret.refresh_from_db()
        self.assertEqual(ret.status, "approved")
        self.assertEqual(ret.decision_note, "Verified the damage")
        self.assertEqual(ret.decided_by_id, self.manager.id)
        d = _data(self.mgr.get(f"/api/v1/store/returns/{ret.code}"))
        self.assertEqual(d["decisionNote"], "Verified the damage")

    def test_return_other_store_404(self):
        other = mk_store("Other")
        ret = self._mk_return(store=other)
        self.assertEqual(self.mgr.get(f"/api/v1/store/returns/{ret.code}").status_code, 404)

    def _mk_kyc(self, with_file=False):
        from kyc.models import KycApplication, KycDocument

        app = KycApplication.objects.create(user=self.customer, status="pending")
        KycDocument.objects.create(application=app, type="pan", number_masked="XXXXX1234X", status="pending")
        return app

    def test_kyc_detail_lists_documents(self):
        app = self._mk_kyc()
        d = _data(self.mgr.get(f"/api/v1/store/verification/{app.id}"))
        self.assertEqual(d["status"], "pending")
        self.assertEqual(len(d["documents"]), 1)
        # No bytes uploaded → no file URL handed out.
        self.assertIsNone(d["documents"][0]["fileUrl"])

    def test_kyc_document_file_404_without_file(self):
        app = self._mk_kyc()
        doc_id = _data(self.mgr.get(f"/api/v1/store/verification/{app.id}"))["documents"][0]["id"]
        r = self.mgr.get(f"/api/v1/store/verification/{app.id}/documents/{doc_id}/file")
        self.assertEqual(r.status_code, 404)

    def test_kyc_detail_other_store_404(self):
        from kyc.models import KycApplication

        other_cust = mk_customer()
        mk_order(mk_store("Other"), other_cust)  # belongs to a different store
        app = KycApplication.objects.create(user=other_cust, status="pending")
        self.assertEqual(self.mgr.get(f"/api/v1/store/verification/{app.id}").status_code, 404)

    def test_kyc_decision_approve(self):
        app = self._mk_kyc()
        r = self.mgr.post(f"/api/v1/store/verification/{app.id}/decision",
                          {"decision": "approve"}, format="json")
        self.assertEqual(r.status_code, 200)
        app.refresh_from_db()
        self.assertEqual(app.status, "verified")


class StoreOpsFlowTests(TestCase):
    """Previously-untested ops flows + new capture/filter behaviour."""

    def setUp(self):
        self.store = mk_store()
        self.manager = mk_staff(self.store, "manager")
        self.mgr = client_for(self.manager)
        self.customer = mk_customer()
        mk_order(self.store, self.customer)

    def test_collection_captures_method_and_reference(self):
        coll = _data(self.mgr.post("/api/v1/store/collections", {
            "customerId": str(self.customer.id), "amount": 300}, format="json"))
        r = self.mgr.post(f"/api/v1/store/collections/{coll['id']}/collect",
                          {"method": "upi", "reference": "UPI-9988"}, format="json")
        self.assertIn(r.status_code, (200, 201))
        rows = _data(self.mgr.get("/api/v1/store/collections", {"status": "collected"}))
        row = next(x for x in rows if x["id"] == coll["id"])
        self.assertEqual(row["method"], "upi")
        self.assertEqual(row["reference"], "UPI-9988")

    def test_credit_update_limit(self):
        from credit.services import ensure_account

        acc = ensure_account(self.customer)
        r = self.mgr.post(f"/api/v1/store/credit/{self.customer.id}",
                          {"creditLimit": 5000}, format="json")
        self.assertEqual(r.status_code, 200)
        acc.refresh_from_db()
        self.assertEqual(float(acc.credit_limit), 5000)

    def test_delivery_list_smoke(self):
        self.assertEqual(self.mgr.get("/api/v1/store/delivery").status_code, 200)

    def test_reports_sales_date_range(self):
        d = _data(self.mgr.get("/api/v1/store/reports/sales", {"from": "2024-01-01", "to": "2024-01-07"}))
        self.assertEqual(d["from"], "2024-01-01")
        self.assertEqual(d["to"], "2024-01-07")
        self.assertEqual(len(d["rows"]), 7)

    def test_reports_top_products_date_range(self):
        d = _data(self.mgr.get("/api/v1/store/reports/top-products", {"from": "2024-01-01", "to": "2024-01-31"}))
        self.assertEqual(d["from"], "2024-01-01")
        self.assertIn("rows", d)

    def test_audit_filter_by_action(self):
        # Generate two distinct audited actions, then narrow by action substring.
        coll = _data(self.mgr.post("/api/v1/store/collections", {
            "customerId": str(self.customer.id), "amount": 100}, format="json"))
        self.mgr.post(f"/api/v1/store/collections/{coll['id']}/collect", {}, format="json")
        self.mgr.patch("/api/v1/store/settings", {"name": "Renamed"}, format="json")

        rows = _data(self.mgr.get("/api/v1/store/audit", {"action": "collection"}))
        self.assertTrue(rows)
        self.assertTrue(all("collection" in r["action"] for r in rows))

    def test_collect_blocked_while_agent_actively_working_it(self):
        """StoreCollectionCollectView used to force ANY collection to
        "collected" regardless of state — overwriting whichever agent was
        assigned with the store staffer who clicked the button, skipping the
        agent's own OTP requirement, and risking a double-collection. Blocked
        now once an agent has actually started working it."""
        from payments.models import CashCollection

        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        coll = CashCollection.objects.create(
            user=self.customer, amount=200, agent=agent, status="en_route")
        r = self.mgr.post(f"/api/v1/store/collections/{coll.id}/collect", {}, format="json")
        self.assertEqual(r.status_code, 409)
        coll.refresh_from_db()
        self.assertEqual(coll.status, "en_route")
        self.assertEqual(coll.agent_id, agent.id)  # not overwritten

    def test_reassign_retries_a_failed_collection_to_a_new_agent(self):
        from payments.models import CashCollection

        old_agent = User.objects.create(phone=_ph(), name="Old Rider", role=Role.AGENT)
        new_agent = User.objects.create(phone=_ph(), name="New Rider", role=Role.AGENT)
        coll = CashCollection.objects.create(
            user=self.customer, amount=150, agent=old_agent, status="failed")
        r = self.mgr.post(f"/api/v1/store/collections/{coll.id}/reassign",
                          {"agentId": str(new_agent.id)}, format="json")
        self.assertEqual(r.status_code, 200)
        coll.refresh_from_db()
        self.assertEqual(coll.status, "assigned")
        self.assertEqual(coll.agent_id, new_agent.id)

    def test_reassign_requires_an_agent_id(self):
        from payments.models import CashCollection

        coll = CashCollection.objects.create(user=self.customer, amount=150, status="failed")
        r = self.mgr.post(f"/api/v1/store/collections/{coll.id}/reassign", {}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_reassign_404s_for_another_stores_customer(self):
        from payments.models import CashCollection

        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        other_customer = mk_customer()
        coll = CashCollection.objects.create(user=other_customer, amount=150, status="failed")
        r = self.mgr.post(f"/api/v1/store/collections/{coll.id}/reassign",
                          {"agentId": str(agent.id)}, format="json")
        self.assertEqual(r.status_code, 404)

    def test_collect_allowed_once_agent_stopped_working_it(self):
        """A collection an agent gave up on (failed) is back in the store's
        hands — the store recording it directly is legitimate here."""
        from payments.models import CashCollection

        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        coll = CashCollection.objects.create(
            user=self.customer, amount=200, agent=agent, status="failed")
        r = self.mgr.post(f"/api/v1/store/collections/{coll.id}/collect", {}, format="json")
        self.assertIn(r.status_code, (200, 201))
        coll.refresh_from_db()
        self.assertEqual(coll.status, "collected")
        # Still the field agent who'd been chasing it — NOT overwritten with
        # the store manager who happened to click the button.
        self.assertEqual(coll.agent_id, agent.id)

    def test_collection_detail_reports_timeline_and_assignment_history(self):
        from accounts.models import AgentProfile
        from payments.models import CashCollection

        agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(user=agent, code=f"AG{next(_seq)}", is_available=True)
        # Store-created collections now auto-assign too.
        coll = _data(self.mgr.post("/api/v1/store/collections", {
            "customerId": str(self.customer.id), "amount": 400}, format="json"))
        c = CashCollection.objects.get(pk=coll["id"])
        self.assertEqual(c.agent_id, agent.id)
        self.assertEqual(c.status, "assigned")

        r = self.mgr.get(f"/api/v1/store/collections/{coll['id']}")
        self.assertEqual(r.status_code, 200)
        d = _data(r)
        self.assertEqual(d["agent"], agent.name)
        self.assertIn("timeline", d)
        self.assertIsNotNone(d["timeline"]["assignedAt"])
        self.assertTrue(d["assignmentHistory"])
        self.assertEqual(d["assignmentHistory"][0]["action"], "auto_assigned")
        self.assertEqual(d["assignmentHistory"][0]["agent"], agent.name)

    def test_collection_detail_404s_for_another_stores_customer(self):
        from payments.models import CashCollection

        other_customer = mk_customer()
        c = CashCollection.objects.create(user=other_customer, amount=100)
        r = self.mgr.get(f"/api/v1/store/collections/{c.id}")
        self.assertEqual(r.status_code, 404)

    def test_store_collect_never_attributes_cash_in_hand_to_the_clicking_staffer(self):
        """The store manager who clicks "Collect" isn't a field agent
        physically holding this money (it reached the store directly — cash
        at the counter, or a digital payment) — it must never end up on
        THEIR cash-in-hand total. A collection nobody was ever assigned to
        stays agent=None after the store records it."""
        coll = _data(self.mgr.post("/api/v1/store/collections", {
            "customerId": str(self.customer.id), "amount": 250}, format="json"))
        r = self.mgr.post(f"/api/v1/store/collections/{coll['id']}/collect",
                          {}, format="json")
        self.assertIn(r.status_code, (200, 201))
        from payments.models import CashCollection

        c = CashCollection.objects.get(pk=coll["id"])
        self.assertEqual(c.status, "collected")
        self.assertIsNone(c.agent_id)
        self.assertNotEqual(c.agent_id, self.manager.id)

    def test_audit_filter_by_actor(self):
        self.mgr.patch("/api/v1/store/settings", {"name": "X"}, format="json")
        rows = _data(self.mgr.get("/api/v1/store/audit", {"actor": "manager"}))
        self.assertTrue(all("manager" in r["actor"].lower() for r in rows))


class StoreDispatchTests(TestCase):
    """Assignment engine: queue → auto-assign batches → agent gets a sequenced trip."""

    def setUp(self):
        from accounts.models import AgentProfile
        self.store = mk_store()
        self.store.latitude, self.store.longitude = 12.9300, 77.6200
        self.store.save(update_fields=["latitude", "longitude"])
        self.mgr = client_for(mk_staff(self.store, "manager"))
        # An available agent with capacity.
        self.agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(
            user=self.agent, code=f"AG{next(_seq)}", is_available=True,
            bag_capacity=5, max_stops=8, cash_capacity=10000, weight_capacity_kg=20,
            store=self.store,
        )

    def _ready_order(self, lat, lng):
        cust = mk_customer()
        o = Order.objects.create(
            user=cust, store=self.store, code=f"ORD-{next(_seq)}",
            total=300, subtotal=300, status="ready_for_dispatch",
            payment_method="upi", payment_status="paid",
            address_snapshot={"latitude": lat, "longitude": lng, "name": cust.name},
        )
        return o

    def test_queue_lists_ready_orders_and_agents(self):
        self._ready_order(12.9310, 77.6210)
        d = _data(self.mgr.get("/api/v1/store/dispatch/queue"))
        self.assertEqual(d["kpis"]["readyOrders"], 1)
        self.assertEqual(d["kpis"]["availableAgents"], 1)
        self.assertEqual(len(d["agents"]), 1)

    def test_auto_assign_creates_batch(self):
        # Three nearby orders → should batch together onto the one agent.
        self._ready_order(12.9310, 77.6210)
        self._ready_order(12.9315, 77.6215)
        self._ready_order(12.9320, 77.6220)
        r = _data(self.mgr.post("/api/v1/store/dispatch/auto-assign", {}, format="json"))
        self.assertEqual(r["orders"], 3)
        self.assertGreaterEqual(r["assigned"], 1)
        from delivery.models import DeliveryBatch
        batch = DeliveryBatch.objects.filter(store=self.store).first()
        self.assertIsNotNone(batch)
        self.assertEqual(batch.agent_id, self.agent.id)
        self.assertEqual(batch.stops.filter(kind="delivery").count(), 3)
        # Sequence numbers are set + tasks created + linked.
        self.assertEqual(batch.tasks.count(), 3)
        # Ready orders drained from the queue.
        q = _data(self.mgr.get("/api/v1/store/dispatch/queue"))
        self.assertEqual(q["kpis"]["readyOrders"], 0)

    def test_auto_assign_prefers_free_agent_over_closer_busy_one(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        # A second agent, positioned closer to the new order than self.agent,
        # but already mid-delivery — should lose out to the free (further)
        # agent rather than winning on distance score.
        busy_agent = User.objects.create(phone=_ph(), name="Busy Rider", role=Role.AGENT)
        AgentProfile.objects.create(
            user=busy_agent, code=f"AG{next(_seq)}", is_available=True,
            bag_capacity=5, max_stops=8, cash_capacity=10000, weight_capacity_kg=20,
            store=self.store,
        )
        busy_order = self._ready_order(12.9312, 77.6212)
        DeliveryTask.objects.create(
            order=busy_order, agent=busy_agent, status="out_for_delivery",
            dest_lat=12.9312, dest_lng=77.6212,
        )
        new_order = self._ready_order(12.9311, 77.6211)  # closer to busy_agent
        from delivery import assignment_engine as engine
        engine.run_auto_assign(self.store, exclude_agent_ids=[])
        from delivery.models import DeliveryBatch
        batch = DeliveryBatch.objects.filter(
            stops__task__order=new_order
        ).first()
        self.assertIsNotNone(batch)
        self.assertEqual(batch.agent_id, self.agent.id)  # the FREE one, not busy_agent

    def test_auto_assign_falls_back_to_soonest_busy_agent(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        # Make the only other agent busy too, with MORE active stops than
        # self.agent, so when both are busy self.agent (fewer stops = sooner
        # free) should still win the new order.
        busier_agent = User.objects.create(phone=_ph(), name="Busier Rider", role=Role.AGENT)
        AgentProfile.objects.create(
            user=busier_agent, code=f"AG{next(_seq)}", is_available=True,
            bag_capacity=5, max_stops=8, cash_capacity=10000, weight_capacity_kg=20,
            store=self.store,
        )
        for _ in range(3):
            o = self._ready_order(12.9310, 77.6210)
            DeliveryTask.objects.create(
                order=o, agent=busier_agent, status="out_for_delivery",
                dest_lat=12.9310, dest_lng=77.6210,
            )
        existing_order = self._ready_order(12.9310, 77.6210)
        DeliveryTask.objects.create(
            order=existing_order, agent=self.agent, status="out_for_delivery",
            dest_lat=12.9310, dest_lng=77.6210,
        )
        new_order = self._ready_order(12.9310, 77.6210)
        from delivery import assignment_engine as engine
        engine.run_auto_assign(self.store)
        from delivery.models import DeliveryBatch
        batch = DeliveryBatch.objects.filter(
            stops__task__order=new_order
        ).first()
        self.assertIsNotNone(batch)
        self.assertEqual(batch.agent_id, self.agent.id)  # fewer active stops

    def test_auto_assign_respects_bag_capacity(self):
        from accounts.models import AgentProfile
        AgentProfile.objects.filter(user=self.agent).update(bag_capacity=2, max_stops=2)
        for i in range(3):
            self._ready_order(12.9310 + i * 0.0005, 77.6210)
        r = _data(self.mgr.post("/api/v1/store/dispatch/auto-assign", {}, format="json"))
        # A cluster of 3 exceeds bag_capacity=2 → the single agent can't take it → queued.
        self.assertGreater(r["queued"], 0)

    def test_manual_batch(self):
        o1 = self._ready_order(12.9310, 77.6210)
        o2 = self._ready_order(12.9315, 77.6215)
        r = self.mgr.post("/api/v1/store/dispatch/manual", {
            "orderCodes": [o1.code, o2.code], "agentId": str(self.agent.id),
        }, format="json")
        self.assertEqual(r.status_code, 201)
        from delivery.models import DeliveryBatch
        b = DeliveryBatch.objects.get(store=self.store)
        self.assertEqual(b.stops.filter(kind="delivery").count(), 2)

    def test_agent_capacity_edit(self):
        self.mgr.patch(f"/api/v1/store/agents/{self.agent.id}",
                       {"bagCapacity": 7, "vehicle": "van"}, format="json")
        from accounts.models import AgentProfile
        p = AgentProfile.objects.get(user=self.agent)
        self.assertEqual(p.bag_capacity, 7)
        self.assertEqual(p.vehicle_type, "van")

    def test_agent_defaults_to_monthly_employment(self):
        row = _data(self.mgr.get("/api/v1/store/agents"))[0]
        self.assertEqual(row["employmentType"], "monthly")

    def test_agent_can_be_switched_to_gig(self):
        r = self.mgr.patch(f"/api/v1/store/agents/{self.agent.id}",
                           {"employmentType": "gig"}, format="json")
        self.assertEqual(_data(r)["employmentType"], "gig")
        from accounts.models import AgentProfile
        p = AgentProfile.objects.get(user=self.agent)
        self.assertEqual(p.employment_type, "gig")

    def test_agent_employment_type_rejects_unknown_value(self):
        r = self.mgr.patch(f"/api/v1/store/agents/{self.agent.id}",
                           {"employmentType": "salaried"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_dispatch_requires_permission(self):
        viewer = client_for(mk_staff(self.store, "custom", perms=["dashboard.view"]))
        self.assertEqual(
            viewer.post("/api/v1/store/dispatch/auto-assign", {}, format="json").status_code, 403)


class StoreAgentsCashTests(TestCase):
    """GET /store/agents/cash — a store's own view of its riders' collected cash."""

    def setUp(self):
        from accounts.models import AgentProfile
        self.store = mk_store()
        self.other_store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.agent = User.objects.create(phone=_ph(), name="Ravi", role=Role.AGENT)
        AgentProfile.objects.create(
            user=self.agent, code=f"AG{next(_seq)}", store=self.store)
        # An agent belonging to a DIFFERENT store — must never leak into this
        # store's cash view.
        self.other_agent = User.objects.create(phone=_ph(), name="Sita", role=Role.AGENT)
        AgentProfile.objects.create(
            user=self.other_agent, code=f"AG{next(_seq)}", store=self.other_store)

    def _collection(self, agent, amount="500"):
        from django.utils import timezone

        from payments.models import CashCollection

        customer = mk_customer()
        return CashCollection.objects.create(
            user=customer, agent=agent, amount=amount, collected_amount=amount,
            status=CashCollection.Status.COLLECTED, collected_at=timezone.now(),
        )

    def test_shows_only_this_stores_agents_cash(self):
        self._collection(self.agent, "500")
        self._collection(self.other_agent, "900")
        d = _data(self.mgr.get("/api/v1/store/agents/cash"))
        self.assertEqual(float(d["summary"]["inHand"]), 500.0)
        names = [r["agent"] for r in d["summary"]["byAgent"]]
        self.assertIn("Ravi", names)
        self.assertNotIn("Sita", names)

    def test_deposit_history_is_store_scoped(self):
        from payments.cashbook_services import create_deposit

        c = self._collection(self.agent, "500")
        create_deposit(self.agent, amount="500", method="bank", collection_ids=[c.id])
        d = _data(self.mgr.get("/api/v1/store/agents/cash"))
        self.assertEqual(len(d["deposits"]), 1)
        self.assertEqual(d["deposits"][0]["agentName"], "Ravi")

    def test_requires_permission(self):
        viewer = client_for(mk_staff(self.store, "custom", perms=["dashboard.view"]))
        self.assertEqual(viewer.get("/api/v1/store/agents/cash").status_code, 403)


class StoreAgentsCashActionTests(TestCase):
    """POST /store/agents/cash/deposits/<id>/<action> — a store manager
    counting/rejecting one of their own agent's cash hand-overs directly,
    instead of routing every one through the platform-wide Cash Book."""

    def setUp(self):
        from accounts.models import AgentProfile
        from payments.cashbook_services import create_deposit
        from payments.models import CashCollection

        self.store = mk_store()
        self.other_store = mk_store()
        self.mgr_user = mk_staff(self.store, "manager")
        self.mgr = client_for(self.mgr_user)
        self.agent = User.objects.create(phone=_ph(), name="Ravi", role=Role.AGENT)
        AgentProfile.objects.create(
            user=self.agent, code=f"AG{next(_seq)}", store=self.store)

        customer = mk_customer()
        collection = CashCollection.objects.create(
            user=customer, agent=self.agent, amount="500", collected_amount="500",
            status=CashCollection.Status.COLLECTED,
        )
        self.deposit = create_deposit(
            self.agent, amount="500", method="office", collection_ids=[collection.id])

        # A deposit that belongs to a different store — must never be reachable.
        self.other_agent = User.objects.create(phone=_ph(), name="Sita", role=Role.AGENT)
        AgentProfile.objects.create(
            user=self.other_agent, code=f"AG{next(_seq)}", store=self.other_store)
        other_collection = CashCollection.objects.create(
            user=mk_customer(), agent=self.other_agent, amount="200",
            collected_amount="200", status=CashCollection.Status.COLLECTED,
        )
        self.other_deposit = create_deposit(
            self.other_agent, amount="200", method="office",
            collection_ids=[other_collection.id])

    def test_manager_can_verify_a_matching_deposit(self):
        r = self.mgr.post(
            f"/api/v1/store/agents/cash/deposits/{self.deposit.id}/verify",
            {"countedAmount": "500"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        d = _data(r)
        self.assertEqual(d["status"], "verified")
        self.assertEqual(d["verifiedByName"], self.mgr_user.name)

    def test_verify_records_a_shortfall_and_audit_trail(self):
        from accounts.models import AuditLog

        r = self.mgr.post(
            f"/api/v1/store/agents/cash/deposits/{self.deposit.id}/verify",
            {"countedAmount": "450"}, format="json",
        )
        d = _data(r)
        self.assertEqual(d["status"], "short")
        self.assertEqual(float(d["shortfall"]), 50.0)
        self.assertTrue(
            AuditLog.objects.filter(action="cash.deposit.short").exists())

    def test_manager_can_reject_with_a_reason(self):
        r = self.mgr.post(
            f"/api/v1/store/agents/cash/deposits/{self.deposit.id}/reject",
            {"reason": "Never received"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.content)
        self.assertEqual(_data(r)["status"], "rejected")

    def test_reject_requires_a_reason(self):
        r = self.mgr.post(
            f"/api/v1/store/agents/cash/deposits/{self.deposit.id}/reject",
            {}, format="json",
        )
        self.assertEqual(r.status_code, 400)

    def test_another_stores_deposit_404s(self):
        r = self.mgr.post(
            f"/api/v1/store/agents/cash/deposits/{self.other_deposit.id}/verify",
            {}, format="json",
        )
        self.assertEqual(r.status_code, 404)

    def test_requires_manage_permission(self):
        viewer = client_for(mk_staff(self.store, "custom", perms=["delivery.view"]))
        r = viewer.post(
            f"/api/v1/store/agents/cash/deposits/{self.deposit.id}/verify",
            {}, format="json",
        )
        self.assertEqual(r.status_code, 403)

    def test_unknown_action_is_rejected(self):
        r = self.mgr.post(
            f"/api/v1/store/agents/cash/deposits/{self.deposit.id}/bogus",
            {}, format="json",
        )
        self.assertEqual(r.status_code, 400)


class AgentBatchTests(TestCase):
    """Agent-side batch: read current trip, accept, pickup handoff."""

    def setUp(self):
        from accounts.models import AgentProfile
        self.store = mk_store()
        self.store.latitude, self.store.longitude = 12.9300, 77.6200
        self.store.save(update_fields=["latitude", "longitude"])
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.agent = User.objects.create(phone=_ph(), name="Rider", role=Role.AGENT)
        AgentProfile.objects.create(
            user=self.agent, code=f"AG{next(_seq)}", is_available=True,
            bag_capacity=5, max_stops=8, cash_capacity=10000, weight_capacity_kg=20,
            store=self.store,
        )
        for i in range(2):
            cust = mk_customer()
            Order.objects.create(
                user=cust, store=self.store, code=f"ORD-{next(_seq)}",
                total=300, subtotal=300, status="ready_for_dispatch",
                payment_method="upi", payment_status="paid",
                address_snapshot={"latitude": 12.9310 + i * 0.0005, "longitude": 77.6210},
            )
        self.mgr.post("/api/v1/store/dispatch/auto-assign", {}, format="json")
        from delivery.models import DeliveryBatch
        self.batch = DeliveryBatch.objects.get(store=self.store)
        self.agc = client_for(self.agent)

    def test_current_batch_returns_sequenced_stops(self):
        d = _data(self.agc.get("/api/v1/deliveries/batch/current"))
        self.assertEqual(d["id"], self.batch.id)
        self.assertEqual(len(d["stops"]), 2)
        self.assertEqual(d["stops"][0]["sequence"], 1)
        self.assertNotIn("pickupCode", d)   # never leaked to the agent
        self.assertEqual(d["progress"]["total"], 2)

    def test_accept_then_pickup(self):
        self.agc.post(f"/api/v1/deliveries/batch/{self.batch.id}/accept", {}, format="json")
        self.batch.refresh_from_db()
        self.assertEqual(self.batch.status, "accepted")
        # Wrong pickup code rejected.
        bad = self.agc.post(f"/api/v1/deliveries/batch/{self.batch.id}/pickup",
                            {"code": "000000"}, format="json")
        self.assertEqual(bad.status_code, 400)
        # Correct code → in_progress + tasks out-for-delivery.
        self.agc.post(f"/api/v1/deliveries/batch/{self.batch.id}/pickup",
                      {"code": self.batch.pickup_code}, format="json")
        self.batch.refresh_from_db()
        self.assertEqual(self.batch.status, "in_progress")
        self.assertTrue(all(t.status == "out_for_delivery" for t in self.batch.tasks.all()))

    def test_batch_is_owner_scoped(self):
        other = User.objects.create(phone=_ph(), name="Other", role=Role.AGENT)
        r = client_for(other).get(f"/api/v1/deliveries/batch/{self.batch.id}")
        self.assertEqual(r.status_code, 404)


class StoreSingleTaskReassignFixTests(TestCase):
    """StoreDeliveryReassignView used to call delivery.admin_service.reassign()
    — a bare `task.agent = agent` write with no notification, no
    DeliveryAssignmentHistory row (silently corrupting future auto-assignment
    acceptance-rate scoring), and a force-jump straight to "accepted" that
    skipped the new agent's Accept/Reject prompt. Now routes through the real
    delivery.services.reassign()."""

    def setUp(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask

        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.customer = mk_customer()
        self.order = mk_order(self.store, self.customer, status="ready_for_dispatch",
                              payment_method="cod", credit_used=0)
        self.old_agent = User.objects.create(phone=_ph(), name="Old Rider", role=Role.AGENT)
        self.new_agent = User.objects.create(phone=_ph(), name="New Rider", role=Role.AGENT)
        for a in (self.old_agent, self.new_agent):
            AgentProfile.objects.create(user=a, code=f"AG{next(_seq)}", store=self.store)
        self.task = DeliveryTask.objects.create(
            order=self.order, agent=self.old_agent, status="assigned")

    def test_reassign_creates_a_fresh_task_with_history_and_notifies(self):
        from delivery.models import DeliveryAssignmentHistory, DeliveryTask
        from notifications.models import Notification

        r = self.mgr.post(f"/api/v1/store/delivery/{self.task.id}/reassign",
                          {"agentId": str(self.new_agent.id)}, format="json")
        self.assertEqual(r.status_code, 200, r.json())

        self.task.refresh_from_db()
        self.assertEqual(self.task.status, "reassigned")
        self.assertTrue(
            DeliveryAssignmentHistory.objects.filter(
                task=self.task, action="reassigned").exists())

        new_task = DeliveryTask.objects.filter(
            order=self.order, agent=self.new_agent).exclude(pk=self.task.pk).first()
        self.assertIsNotNone(new_task)
        self.assertEqual(new_task.status, "assigned")  # NOT force-jumped to accepted
        self.assertTrue(
            Notification.objects.filter(user=self.new_agent, type="delivery").exists())


class BatchReassignTests(TestCase):
    """Real-time reassignment: release, reassign to another agent, SLA sweep."""

    def setUp(self):
        from accounts.models import AgentProfile
        self.store = mk_store()
        self.store.latitude, self.store.longitude = 12.9300, 77.6200
        self.store.save(update_fields=["latitude", "longitude"])
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.a1 = User.objects.create(phone=_ph(), name="Rider1", role=Role.AGENT)
        self.a2 = User.objects.create(phone=_ph(), name="Rider2", role=Role.AGENT)
        for a in (self.a1, self.a2):
            AgentProfile.objects.create(
                user=a, code=f"AG{next(_seq)}", is_available=True,
                bag_capacity=5, max_stops=8, cash_capacity=10000, weight_capacity_kg=20,
                store=self.store,
            )
        for i in range(2):
            cust = mk_customer()
            Order.objects.create(
                user=cust, store=self.store, code=f"ORD-{next(_seq)}",
                total=300, subtotal=300, status="ready_for_dispatch",
                payment_method="upi", payment_status="paid",
                address_snapshot={"latitude": 12.9310 + i * 0.0005, "longitude": 77.6210},
            )

    def _assign(self):
        from delivery import assignment_engine as engine
        engine.run_auto_assign(self.store)
        from delivery.models import DeliveryBatch
        return DeliveryBatch.objects.filter(store=self.store, status="assigned").first()

    def test_store_reassign_moves_to_other_agent(self):
        from delivery.models import DeliveryBatch
        b = self._assign()
        first_agent = b.agent_id
        r = self.mgr.post(f"/api/v1/store/dispatch/batches/{b.id}/reassign", {}, format="json")
        self.assertEqual(r.status_code, 200)
        b.refresh_from_db()
        self.assertEqual(b.status, "cancelled")
        # A fresh batch exists for the OTHER agent.
        new = DeliveryBatch.objects.filter(store=self.store, status="assigned").exclude(id=b.id).first()
        self.assertIsNotNone(new)
        self.assertNotEqual(new.agent_id, first_agent)

    def test_agent_abandon_reassigns(self):
        b = self._assign()
        agent = b.agent  # the assigned agent
        r = client_for(agent).post(f"/api/v1/deliveries/batch/{b.id}/abandon",
                                   {"reason": "breakdown"}, format="json")
        self.assertEqual(r.status_code, 200)
        b.refresh_from_db()
        self.assertEqual(b.status, "cancelled")
        # Orders reopened + reassigned to the other agent.
        from delivery.models import DeliveryBatch
        self.assertTrue(DeliveryBatch.objects.filter(store=self.store, status="assigned").exists())

    def test_release_reopens_orders(self):
        from delivery import assignment_engine as engine
        from delivery.models import DeliveryBatch
        b = self._assign()
        engine.release_batch(b, reason="test")
        b.refresh_from_db()
        self.assertEqual(b.status, "cancelled")
        self.assertEqual(
            Order.objects.filter(store=self.store, status="ready_for_dispatch").count(), 2)

    def test_sla_sweep_reassigns_stale(self):
        from datetime import timedelta
        from django.utils import timezone
        from delivery import assignment_engine as engine
        from delivery.models import DeliveryBatch
        b = self._assign()
        # Make it stale (created 20 min ago) and drop the other agent so it re-queues.
        DeliveryBatch.objects.filter(id=b.id).update(
            created_at=timezone.now() - timedelta(minutes=20))
        n = engine.sweep_stale_batches(self.store)
        self.assertEqual(n, 1)
        b.refresh_from_db()
        self.assertEqual(b.status, "cancelled")


class StoreCatalogManagementTests(TestCase):
    """Store panel: add store-private products + per-store overrides (belong to this
    store only), image upload, and cross-store / customer isolation."""

    def setUp(self):
        self.store = mk_store("Alpha")
        self.other = mk_store("Beta")
        self.manager = mk_staff(self.store, role="manager")
        self.c = client_for(self.manager)
        self.shared = mk_product(price=100, mrp=120)  # company-wide product

    def _cat_id(self):
        return self.shared.category_id

    def test_create_store_private_product(self):
        resp = self.c.post("/api/v1/store/inventory/products", {
            "name": "House Masala", "categoryId": self._cat_id(),
            "price": 45, "mrp": 60, "openingStock": 12, "reorderLevel": 3,
        }, format="json")
        self.assertEqual(resp.status_code, 201, _data(resp))
        d = _data(resp)
        self.assertTrue(d["private"])
        self.assertEqual(d["onHand"], 12)
        from catalog.models import Product
        p = Product.objects.get(name="House Masala")
        self.assertEqual(p.origin_store_id, self.store.id)

    def test_private_product_hidden_from_other_store_and_admin(self):
        self.c.post("/api/v1/store/inventory/products", {
            "name": "Secret Sauce", "categoryId": self._cat_id(), "price": 30,
        }, format="json")
        # Another store's POS catalog must not include it.
        other_mgr = mk_staff(self.other, role="manager")
        # give the other store a warehouse session-free catalog read
        oc = client_for(other_mgr)
        resp = oc.get("/api/v1/store/pos/catalog")
        names = {r["name"] for r in _data(resp)["products"]}
        self.assertNotIn("Secret Sauce", names)
        # Admin master catalog excludes store-private products.
        admin = User.objects.create(phone=_ph(), name="Admin", role=Role.ADMIN)
        ac = client_for(admin)
        resp = ac.get("/api/v1/admin/catalog/products", {"q": "Secret"})
        rows = _data(resp)
        rows = rows["results"] if isinstance(rows, dict) else rows
        self.assertEqual(rows, [])

    def test_override_shared_product_price_and_name(self):
        orig_name = self.shared.name
        resp = self.c.patch(f"/api/v1/store/inventory/products/{self.shared.id}", {
            "price": 88, "name": "Alpha Special", "isAvailable": True,
        }, format="json")
        self.assertEqual(resp.status_code, 200, _data(resp))
        d = _data(resp)
        self.assertEqual(d["price"], 88.0)
        self.assertEqual(d["name"], "Alpha Special")
        # The global product is untouched …
        self.shared.refresh_from_db()
        self.assertEqual(self.shared.name, orig_name)
        self.assertEqual(float(self.shared.price), 100.0)
        # … and another store still sees the global values.
        from stores.services import store_view
        v = store_view(self.shared, self.other)
        self.assertEqual(float(v["price"]), 100.0)
        self.assertEqual(v["name"], orig_name)

    def test_override_does_not_mutate_private_of_other_store(self):
        # A store cannot override a product private to another store (404).
        oc = client_for(mk_staff(self.other, role="manager"))
        r = oc.post("/api/v1/store/inventory/products", {
            "name": "Beta Only", "categoryId": self._cat_id(), "price": 20,
        }, format="json")
        pid = _data(r)["productId"]
        resp = self.c.patch(f"/api/v1/store/inventory/products/{pid}", {"price": 5}, format="json")
        self.assertEqual(resp.status_code, 404)

    def test_customer_catalog_includes_store_products_when_unscoped(self):
        # Flag OFF / no zone (launch reality) → global catalog shows store-added
        # products too, so a product added in the panel is sellable immediately.
        # Zone scoping (tested in stores/test_variable_zone_catalog.py) narrows the
        # view to a single store once the customer's location is in a served zone.
        self.c.post("/api/v1/store/inventory/products", {
            "name": "Store Item", "categoryId": self._cat_id(), "price": 10,
        }, format="json")
        pub = APIClient()
        resp = pub.get("/api/v1/products")
        data = resp.json()["data"]
        items = data["results"] if isinstance(data, dict) else data
        names = {p["name"] for p in items}
        self.assertIn(self.shared.name, names)
        self.assertIn("Store Item", names)

    def test_create_product_with_variants(self):
        resp = self.c.post("/api/v1/store/inventory/products", {
            "name": "House Tea", "categoryId": self._cat_id(), "price": 50,
            "variants": [{"label": "250 g", "priceDelta": 0}, {"label": "1 kg", "priceDelta": 120}],
        }, format="json")
        self.assertEqual(resp.status_code, 201, _data(resp))
        d = _data(resp)
        labels = {v["label"]: v["priceDelta"] for v in d["variants"]}
        self.assertEqual(labels, {"250 g": 0.0, "1 kg": 120.0})

    def test_edit_owned_product_variants_add_and_remove(self):
        r = self.c.post("/api/v1/store/inventory/products", {
            "name": "House Spice", "categoryId": self._cat_id(), "price": 40,
            "variants": [{"label": "Small", "priceDelta": 0}, {"label": "Big", "priceDelta": 20}],
        }, format="json")
        pid = _data(r)["productId"]
        keep = next(v for v in _data(r)["variants"] if v["label"] == "Big")
        # Keep "Big" (by id, relabelled) and drop "Small"; add a new one.
        resp = self.c.patch(f"/api/v1/store/inventory/products/{pid}", {
            "variants": [
                {"id": keep["id"], "label": "Large", "priceDelta": 25},
                {"label": "Family", "priceDelta": 60},
            ],
        }, format="json")
        self.assertEqual(resp.status_code, 200, _data(resp))
        labels = {v["label"]: v["priceDelta"] for v in _data(resp)["variants"]}
        self.assertEqual(labels, {"Large": 25.0, "Family": 60.0})

    def test_cannot_remove_a_variant_that_still_has_stock(self):
        """Deleting a pack CASCADEs its StockItem but only SET_NULLs its ledger rows,
        so a stocked delete would bin the cache and let `reconcile` resurrect the units
        in the pool with no record of which pack they were. Make the store write it off."""
        from catalog.models import ProductVariant
        from inventory.services import InventoryService

        r = self.c.post("/api/v1/store/inventory/products", {
            "name": "Stocked Pack", "categoryId": self._cat_id(), "price": 40,
            "variants": [{"label": "Small", "priceDelta": 0}],
        }, format="json")
        pid = _data(r)["productId"]
        v = ProductVariant.objects.get(product_id=pid)
        InventoryService.adjust(
            v.product, variant=v, set=7, warehouse=self.store.warehouse, reason="t"
        )
        resp = self.c.patch(f"/api/v1/store/inventory/products/{pid}",
                            {"variants": []}, format="json")
        self.assertEqual(resp.status_code, 400, _data(resp))
        self.assertIn("still has 7 in stock", str(_data(resp)))
        self.assertTrue(ProductVariant.objects.filter(pk=v.pk).exists())

    def test_cannot_add_variants_to_shared_product(self):
        # Editing a shared company product ignores variant changes (they're global).
        resp = self.c.patch(f"/api/v1/store/inventory/products/{self.shared.id}", {
            "variants": [{"label": "Hacked", "priceDelta": 5}],
        }, format="json")
        self.assertEqual(resp.status_code, 200)
        self.shared.refresh_from_db()
        self.assertEqual(self.shared.variants.count(), 0)

    def test_product_and_variants_get_barcodes(self):
        r = self.c.post("/api/v1/store/inventory/products", {
            "name": "Barcoded", "categoryId": self._cat_id(), "price": 25,
            "variants": [{"label": "1 kg", "priceDelta": 30}],
        }, format="json")
        self.assertEqual(r.status_code, 201, _data(r))
        d = _data(r)
        self.assertTrue(d["barcode"])                       # product barcode
        self.assertTrue(d["variants"][0]["barcode"])        # variant barcode
        self.assertNotEqual(d["barcode"], d["variants"][0]["barcode"])
        # Scanning the variant barcode resolves the variant + its price (base+delta).
        scan = _data(self.c.get("/api/v1/store/pos/scan", {"code": d["variants"][0]["barcode"]}))
        self.assertEqual(scan["productId"], d["productId"])
        self.assertIsNotNone(scan["variantId"])
        self.assertEqual(scan["price"], 55.0)               # 25 + 30

    def test_categories_endpoint_has_parent(self):
        # Sub-category cascade needs parentId on every row.
        from catalog.models import Category

        parent = Category.objects.get(pk=self._cat_id())
        Category.objects.create(name="Sub", slug="sub-x", parent=parent)
        resp = self.c.get("/api/v1/store/categories")
        self.assertEqual(resp.status_code, 200)
        rows = {r["name"]: r for r in _data(resp)}
        self.assertIn("parentId", next(iter(rows.values())))
        self.assertEqual(rows["Sub"]["parentId"], str(parent.id))

    def test_create_product_with_gallery(self):
        urls = ["/api/v1/media/public/a/medium", "/api/v1/media/public/b/medium"]
        resp = self.c.post("/api/v1/store/inventory/products", {
            "name": "Gallery Item", "categoryId": self._cat_id(), "price": 30,
            "images": urls,
        }, format="json")
        self.assertEqual(resp.status_code, 201, _data(resp))
        d = _data(resp)
        self.assertEqual(d["images"], urls)          # gallery persisted, in order
        self.assertEqual(d["imageUrl"], urls[0])     # cover mirrored to image_url
        from catalog.models import Product
        p = Product.objects.get(name="Gallery Item")
        self.assertEqual([g.url for g in p.gallery.all()], urls)

    def test_edit_gallery_replaces(self):
        r = self.c.post("/api/v1/store/inventory/products", {
            "name": "Gal2", "categoryId": self._cat_id(), "price": 20,
            "images": ["/api/v1/media/public/x/medium"],
        }, format="json")
        pid = _data(r)["productId"]
        resp = self.c.patch(f"/api/v1/store/inventory/products/{pid}", {
            "images": ["/api/v1/media/public/y/medium", "/api/v1/media/public/z/medium"],
        }, format="json")
        self.assertEqual(resp.status_code, 200, _data(resp))
        d = _data(resp)
        self.assertEqual(d["images"], ["/api/v1/media/public/y/medium", "/api/v1/media/public/z/medium"])
        self.assertEqual(d["imageUrl"], "/api/v1/media/public/y/medium")


class StoreMarketingTests(TestCase):
    """Store-scoped notify: reaches only the store's own customers (inbox rows;
    push is a no-op without FCM creds)."""

    def setUp(self):
        self.store = mk_store()
        self.other = mk_store("Beta")
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.mine = mk_customer()
        self.theirs = mk_customer()
        mk_order(self.store, self.mine)
        mk_order(self.other, self.theirs)

    def test_audience_size(self):
        d = _data(self.mgr.get("/api/v1/store/marketing/notify"))
        self.assertEqual(d["customerCount"], 1)

    def test_send_reaches_only_store_customers(self):
        from notifications.models import Notification

        r = self.mgr.post("/api/v1/store/marketing/notify", {
            "title": "Fresh deals!", "body": "20% off today", "imageUrl": "/api/v1/media/public/x/medium",
        }, format="json")
        self.assertEqual(r.status_code, 200, _data(r))
        self.assertEqual(_data(r)["sent"], 1)
        self.assertTrue(Notification.objects.filter(user=self.mine, title="Fresh deals!").exists())
        self.assertFalse(Notification.objects.filter(user=self.theirs).exists())

    def test_title_required(self):
        r = self.mgr.post("/api/v1/store/marketing/notify", {"title": ""}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_cashier_cannot_send(self):
        cashier = client_for(mk_staff(self.store, "cashier"))
        r = cashier.post("/api/v1/store/marketing/notify", {"title": "hi"}, format="json")
        self.assertEqual(r.status_code, 403)


class StorePOSPaymentTests(TestCase):
    """POS online (Razorpay) + credit-2FA tenders + customer purchase 'story'."""

    def setUp(self):
        from credit.services import ensure_account
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.product = mk_product(price=100, mrp=120)
        self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV", "items": [{"productId": str(self.product.id), "quantity": 50, "unitCost": 60}],
        }, format="json")
        self.mgr.post("/api/v1/store/pos/session", {"openingCash": 500}, format="json")
        self.cust = mk_customer()
        self.cust.credit_enabled = True
        self.cust.kyc_status = "verified"
        self.cust.save(update_fields=["credit_enabled", "kyc_status"])
        acc = ensure_account(self.cust, default_limit=5000)
        acc.credit_limit = 5000; acc.status = "active"; acc.save()

    def _checkout(self, payments, **extra):
        body = {"items": [{"productId": str(self.product.id), "qty": 1}], "payments": payments, **extra}
        return self.mgr.post("/api/v1/store/pos/checkout", body, format="json")

    def test_online_order_and_checkout(self):
        # Cashier creates a Razorpay order (mock gw in dev) …
        order = _data(self.mgr.post("/api/v1/store/pos/online/order", {"amount": 118}, format="json"))
        self.assertIn("orderId", order)
        self.assertIn("keyId", order)
        # … then completes the sale with the online tender (mock gw verifies True).
        r = self._checkout(
            [{"method": "online", "amount": 118}],
            razorpayOrderId=order["orderId"], razorpayPaymentId="pay_x", razorpaySignature="sig",
        )
        self.assertEqual(r.status_code, 201, _data(r))
        # Recorded as a UPI tender carrying the Razorpay payment id.
        pays = _data(r)["payments"]
        self.assertEqual(pays[0]["method"], "upi")

    def test_credit_requires_2fa(self):
        # Without an OTP, a credit sale is rejected.
        r = self._checkout([{"method": "credit", "amount": 118}], customerId=str(self.cust.id))
        self.assertEqual(r.status_code, 400)
        self.assertIn("creditOtp", str(_data(r)))

    def test_credit_2fa_happy_path_deducts_and_notifies(self):
        from credit.pos_otp import pending_for
        from credit.services import ensure_account
        from notifications.models import Notification
        # 1) request the code
        req = self.mgr.post("/api/v1/store/pos/credit/request-otp",
                            {"customerId": str(self.cust.id), "amount": 118}, format="json")
        self.assertEqual(req.status_code, 200, _data(req))
        # 2) customer reads the code in-app (here: straight from the store)
        code = pending_for(self.cust)["code"]
        # 3) cashier enters it → sale clears, credit deducted, story notified
        r = self._checkout([{"method": "credit", "amount": 118}],
                           customerId=str(self.cust.id), creditOtp=code)
        self.assertEqual(r.status_code, 201, _data(r))
        acc = ensure_account(self.cust)
        self.assertEqual(float(acc.outstanding), 118.0)
        self.assertTrue(Notification.objects.filter(user=self.cust, type="order").exists())

    def test_credit_2fa_wrong_code_rejected(self):
        self.mgr.post("/api/v1/store/pos/credit/request-otp",
                      {"customerId": str(self.cust.id), "amount": 118}, format="json")
        r = self._checkout([{"method": "credit", "amount": 118}],
                           customerId=str(self.cust.id), creditOtp="000000")
        self.assertEqual(r.status_code, 400)

    def test_customer_confirm_endpoint(self):
        self.mgr.post("/api/v1/store/pos/credit/request-otp",
                      {"customerId": str(self.cust.id), "amount": 118}, format="json")
        r = client_for(self.cust).get("/api/v1/credit/pos-confirm")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(_data(r)["pending"]["amount"], "118")


class StorePOSFeatureTests(TestCase):
    """POS extras (ReadyEcommerce-style): customer create, coupon, drafts, brands,
    category/brand search filters."""

    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.product = mk_product(price=100, mrp=120)  # brand "B"
        self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV", "items": [{"productId": str(self.product.id), "quantity": 50, "unitCost": 60}],
        }, format="json")
        self.mgr.post("/api/v1/store/pos/session", {"openingCash": 500}, format="json")

    def test_create_customer_and_lookup(self):
        r = self.mgr.post("/api/v1/store/pos/customer/create", {
            "firstName": "Walk", "lastName": "In", "phone": "+919812345678", "email": "w@x.com",
        }, format="json")
        self.assertEqual(r.status_code, 201, _data(r))
        self.assertEqual(_data(r)["name"], "Walk In")
        from accounts.models import User
        self.assertTrue(User.objects.filter(phone="+919812345678", role="customer").exists())

    def test_create_customer_duplicate_phone_rejected(self):
        self.mgr.post("/api/v1/store/pos/customer/create", {"firstName": "A", "phone": "+919812340000"}, format="json")
        r = self.mgr.post("/api/v1/store/pos/customer/create", {"firstName": "B", "phone": "+919812340000"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_coupon_validate_and_apply_at_checkout(self):
        from offers.models import Coupon
        Coupon.objects.create(code="SAVE10", discount_type="percent", value=10, is_active=True)
        # preview
        r = self.mgr.post("/api/v1/store/pos/coupon", {"code": "SAVE10", "subtotal": 100}, format="json")
        self.assertEqual(r.status_code, 200, _data(r))
        self.assertEqual(_data(r)["discount"], 10.0)
        # apply at checkout → total = 100 + tax - 10
        r2 = self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "qty": 1}],
            "payments": [{"method": "cash", "amount": 200}], "couponCode": "SAVE10",
        }, format="json")
        self.assertEqual(r2.status_code, 201, _data(r2))
        self.assertEqual(_data(r2)["discount"], 10.0)

    def test_invalid_coupon_rejected(self):
        r = self.mgr.post("/api/v1/store/pos/coupon", {"code": "NOPE", "subtotal": 100}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_brands_list(self):
        r = self.mgr.get("/api/v1/store/brands")
        self.assertEqual(r.status_code, 200)
        self.assertIn("B", _data(r))

    def test_search_filter_by_category(self):
        rows = _data(self.mgr.get("/api/v1/store/pos/search", {"category": str(self.product.category_id)}))
        self.assertTrue(any(x["productId"] == str(self.product.id) for x in rows))
        # a different category returns nothing for this product
        from catalog.models import Category
        other = Category.objects.create(name="Other", slug="other-x")
        rows2 = _data(self.mgr.get("/api/v1/store/pos/search", {"category": str(other.id)}))
        self.assertFalse(any(x["productId"] == str(self.product.id) for x in rows2))

    def test_draft_save_list_load_delete(self):
        payload = {"items": [{"productId": str(self.product.id), "variantId": None, "name": "Prod", "price": 100, "qty": 2}], "total": 200}
        r = self.mgr.post("/api/v1/store/pos/drafts", {"label": "Table 5", "payload": payload}, format="json")
        self.assertEqual(r.status_code, 201, _data(r))
        did = _data(r)["id"]
        self.assertEqual(_data(r)["itemCount"], 2)
        lst = _data(self.mgr.get("/api/v1/store/pos/drafts"))
        self.assertTrue(any(d["id"] == did for d in lst))
        full = _data(self.mgr.get(f"/api/v1/store/pos/drafts/{did}"))
        self.assertEqual(full["payload"]["total"], 200)
        self.assertEqual(self.mgr.delete(f"/api/v1/store/pos/drafts/{did}").status_code, 204)
        self.assertEqual(len(_data(self.mgr.get("/api/v1/store/pos/drafts"))), 0)

    def test_draft_cross_store_isolation(self):
        other = client_for(mk_staff(mk_store("Beta"), "manager"))
        r = self.mgr.post("/api/v1/store/pos/drafts", {"payload": {"items": [{"qty": 1}]}}, format="json")
        did = _data(r)["id"]
        self.assertEqual(other.get(f"/api/v1/store/pos/drafts/{did}").status_code, 404)
        self.assertEqual(len(_data(other.get("/api/v1/store/pos/drafts"))), 0)


class StorePOSInvoiceTests(TestCase):
    def setUp(self):
        self.store = mk_store()
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.product = mk_product(price=100, mrp=120)
        self.mgr.post("/api/v1/store/purchases", {
            "invoiceNumber": "INV", "items": [{"productId": str(self.product.id), "quantity": 50, "unitCost": 60}],
        }, format="json")
        self.mgr.post("/api/v1/store/pos/session", {"openingCash": 500}, format="json")

    def test_invoice_pdf_served(self):
        r = self.mgr.post("/api/v1/store/pos/checkout", {
            "items": [{"productId": str(self.product.id), "qty": 1}],
            "payments": [{"method": "cash", "amount": 200}],
        }, format="json")
        code = _data(r)["code"]
        inv = self.mgr.get(f"/api/v1/store/pos/transactions/{code}/invoice")
        self.assertEqual(inv.status_code, 200)
        self.assertEqual(inv["Content-Type"], "application/pdf")
        self.assertTrue(inv.content[:5] == b"%PDF-")


class StoreBannerTests(TestCase):
    """Store-proposed banners: scoped to the caller's own store, and never
    self-approvable."""

    def setUp(self):
        self.store = mk_store()
        self.other = mk_store("Beta")
        self.mgr = client_for(mk_staff(self.store, "manager"))

    def _png(self, w=1600, h=1000):
        import io

        from PIL import Image

        buf = io.BytesIO()
        Image.new("RGB", (w, h), (10, 90, 60)).save(buf, "PNG")
        return buf.getvalue()

    def _create(self, **kw):
        body = {"title": "Store sale", "type": "banner", "placement": "top", **kw}
        return self.mgr.post("/api/v1/store/marketing/banners", body, format="json")

    def _upload(self, offer_id):
        from django.core.files.uploadedfile import SimpleUploadedFile

        f = SimpleUploadedFile("b.png", self._png(), content_type="image/png")
        return self.mgr.post(
            f"/api/v1/store/marketing/banners/{offer_id}/image", {"file": f},
            format="multipart",
        )

    def test_create_is_forced_to_this_store_and_draft(self):
        from offers.models import Offer

        r = self._create()
        self.assertEqual(r.status_code, 201, _data(r))
        offer = Offer.objects.get(id=_data(r)["id"])
        self.assertEqual(offer.store_id, self.store.id)
        self.assertEqual(offer.state, Offer.State.DRAFT)
        self.assertFalse(offer.is_active)

    def test_store_cannot_target_another_store_or_go_global(self):
        from offers.models import Offer

        r = self._create(storeId=self.other.id, zoneId=None, state="active",
                         isPinned=True)
        self.assertEqual(r.status_code, 201, _data(r))
        offer = Offer.objects.get(id=_data(r)["id"])
        # Ownership + lifecycle fields are server-forced, not taken from the body.
        self.assertEqual(offer.store_id, self.store.id)
        self.assertEqual(offer.state, Offer.State.DRAFT)
        self.assertFalse(offer.is_pinned)

    def test_list_only_shows_this_store(self):
        from offers.models import Offer

        self._create()
        Offer.objects.create(title="Theirs", type="banner", store=self.other)
        rows = _data(self.mgr.get("/api/v1/store/marketing/banners"))["results"]
        self.assertEqual([o["title"] for o in rows], ["Store sale"])

    def test_cannot_touch_another_stores_banner(self):
        from offers.models import Offer

        theirs = Offer.objects.create(title="Theirs", type="banner", store=self.other)
        for method, url in (
            ("patch", f"/api/v1/store/marketing/banners/{theirs.id}"),
            ("delete", f"/api/v1/store/marketing/banners/{theirs.id}"),
            ("post", f"/api/v1/store/marketing/banners/{theirs.id}/submit"),
        ):
            r = getattr(self.mgr, method)(url, {}, format="json")
            self.assertEqual(r.status_code, 404, f"{method} {url} leaked")

    def test_submit_requires_an_image(self):
        offer_id = _data(self._create())["id"]
        r = self.mgr.post(f"/api/v1/store/marketing/banners/{offer_id}/submit",
                          {}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_submit_moves_to_pending_not_active(self):
        from offers.models import Offer

        offer_id = _data(self._create())["id"]
        self.assertEqual(self._upload(offer_id).status_code, 200)
        r = self.mgr.post(f"/api/v1/store/marketing/banners/{offer_id}/submit",
                          {}, format="json")
        self.assertEqual(r.status_code, 200, _data(r))
        offer = Offer.objects.get(id=offer_id)
        self.assertEqual(offer.state, Offer.State.PENDING)
        self.assertFalse(offer.is_active)

    def test_store_has_no_approve_transition(self):
        offer_id = _data(self._create())["id"]
        r = self.mgr.post(f"/api/v1/store/marketing/banners/{offer_id}/approve",
                          {}, format="json")
        self.assertIn(r.status_code, (404, 405))

    def test_pending_banner_is_no_longer_editable(self):
        offer_id = _data(self._create())["id"]
        self._upload(offer_id)
        self.mgr.post(f"/api/v1/store/marketing/banners/{offer_id}/submit", {},
                      format="json")
        r = self.mgr.patch(f"/api/v1/store/marketing/banners/{offer_id}",
                           {"title": "Sneaky edit"}, format="json")
        # INVALID_BANNER_TRANSITION is a 409 (state conflict), not a 400.
        self.assertEqual(r.status_code, 409)

    def test_deep_link_validation_applies_to_stores_too(self):
        r = self._create(action="product", payload={})
        self.assertEqual(r.status_code, 400)

    def test_cashier_cannot_manage_banners(self):
        cashier = client_for(mk_staff(self.store, "cashier"))
        r = cashier.get("/api/v1/store/marketing/banners")
        self.assertEqual(r.status_code, 403)

    def test_coupons_are_read_only(self):
        from offers.models import Coupon

        Coupon.objects.create(code="SAVE10", discount_type="percent", value=10)
        rows = _data(self.mgr.get("/api/v1/store/marketing/coupons"))
        self.assertEqual([c["code"] for c in rows], ["SAVE10"])
        r = self.mgr.post("/api/v1/store/marketing/coupons", {"code": "HACK"},
                          format="json")
        self.assertIn(r.status_code, (403, 405))


# ── Reassignment: agent pool + store boundary ────────────
def mk_agent(store=None, *, available=True, active=True, name=None):
    """An agent, optionally owned by a store (AgentProfile.store)."""
    from accounts.models import AgentProfile

    n = next(_seq)
    user = User.objects.create(
        phone=_ph(), name=name or f"Agent{n}", role=Role.AGENT, is_active=active
    )
    AgentProfile.objects.create(
        user=user, code=f"AG-{n}", store=store, is_available=available
    )
    return user


class StoreReassignAgentPoolTests(TestCase):
    """Who a store may hand a delivery or a collection to.

    Agents are store-owned. The reassign pickers on both the Delivery and the
    Collections pages read `/store/delivery/agents`, which was unscoped — it
    listed every agent on the platform, so a store could hand its work to
    another store's rider. The task then drops off the owning store's board and
    lands with somebody who can't physically do it.
    """

    def setUp(self):
        self.store = mk_store("Mine")
        self.other = mk_store("Theirs")
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.mine = mk_agent(self.store, name="Mine Agent")
        self.theirs = mk_agent(self.other, name="Their Agent")

    def _pool(self):
        return {a["name"] for a in _data(self.mgr.get("/api/v1/store/delivery/agents"))}

    def test_pool_is_scoped_to_this_store(self):
        pool = self._pool()
        self.assertIn("Mine Agent", pool)
        self.assertNotIn("Their Agent", pool)

    def test_off_duty_agents_are_offered_but_flagged(self):
        # A human picking a name may knowingly choose someone starting a shift —
        # so they stay in the list, but the UI has to be able to say "off duty".
        resting = mk_agent(self.store, available=False, name="Resting")
        rows = {a["name"]: a for a in _data(self.mgr.get("/api/v1/store/delivery/agents"))}
        self.assertIn("Resting", rows)
        self.assertFalse(rows["Resting"]["onDuty"])
        self.assertEqual(str(resting.id), rows["Resting"]["id"])

    def test_deactivated_agents_are_never_offered(self):
        mk_agent(self.store, active=False, name="Gone")
        self.assertNotIn("Gone", self._pool())

    def test_store_less_legacy_agents_are_the_fallback_pool(self):
        # An install that never filled in AgentProfile.store must keep working:
        # store-less agents are offered when the store has none of its own, and
        # step aside once it does. Same rule as `candidate_agents`, so the panel
        # and the auto-assignment engine never disagree about who is eligible.
        mk_agent(None, name="Legacy")
        self.assertNotIn("Legacy", self._pool())  # this store has its own

        bare_store = mk_store("Bare")
        bare_mgr = client_for(mk_staff(bare_store, "manager"))
        names = {a["name"] for a in _data(bare_mgr.get("/api/v1/store/delivery/agents"))}
        self.assertIn("Legacy", names)
        self.assertNotIn("Mine Agent", names)

    def test_picker_and_endpoint_agree_on_eligibility(self):
        # The guard is defined as membership of the picker's pool, so an agent
        # the panel never offers can't be forced through the endpoint either.
        from agents.candidates import assignable_agents, eligible_for_store

        offered = {a.id for a in assignable_agents(self.store)}
        self.assertTrue(eligible_for_store(self.mine, self.store))
        self.assertFalse(eligible_for_store(self.theirs, self.store))
        self.assertEqual(offered, {self.mine.id})

    def test_reassigning_a_delivery_to_another_stores_agent_is_refused(self):
        from delivery.models import DeliveryTask

        order = mk_order(self.store, mk_customer(), status="packed")
        task = DeliveryTask.objects.create(order=order, agent=self.mine, status="failed")
        r = self.mgr.post(
            f"/api/v1/store/delivery/{task.id}/reassign",
            {"agentId": str(self.theirs.id)}, format="json",
        )
        self.assertEqual(r.status_code, 400)
        task.refresh_from_db()
        self.assertEqual(task.agent_id, self.mine.id)

    def test_a_failed_delivery_can_be_retried_with_this_stores_agent(self):
        from delivery.models import DeliveryTask

        order = mk_order(self.store, mk_customer(), status="packed")
        task = DeliveryTask.objects.create(order=order, agent=self.mine, status="failed")
        mate = mk_agent(self.store, name="Mate")
        r = self.mgr.post(
            f"/api/v1/store/delivery/{task.id}/reassign",
            {"agentId": str(mate.id)}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        # A fresh task for the new agent to accept — not a force-jump to accepted.
        self.assertEqual(_data(r)["agent"], "Mate")
        self.assertNotEqual(_data(r)["id"], task.id)
        fresh = DeliveryTask.objects.get(pk=_data(r)["id"])
        self.assertEqual(fresh.status, "assigned")
        # The next attempt at this address is attempt 2, not another attempt 1.
        self.assertEqual(fresh.attempt_no, task.attempt_no + 1)
        # The failed attempt keeps its status: those goods are still with the
        # first agent and must still come back through "Returns to receive".
        task.refresh_from_db()
        self.assertEqual(task.status, "failed")

    def test_a_rejected_delivery_can_still_be_given_to_someone(self):
        # `rejected` is TERMINAL, so `services.reassign` refuses it — and the
        # panel button 409'd. When an agent turns a job down and nobody else is
        # eligible, the order sits with a rejected task and no live one: nobody
        # is delivering it. The store must be able to hand it to a name.
        from delivery.models import DeliveryTask

        order = mk_order(self.store, mk_customer(), status="packed")
        task = DeliveryTask.objects.create(order=order, agent=self.mine, status="rejected")
        mate = mk_agent(self.store, name="Mate")
        r = self.mgr.post(
            f"/api/v1/store/delivery/{task.id}/reassign",
            {"agentId": str(mate.id)}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        fresh = DeliveryTask.objects.get(pk=_data(r)["id"])
        self.assertEqual(fresh.agent_id, mate.id)
        self.assertEqual(fresh.status, "assigned")
        task.refresh_from_db()
        self.assertEqual(task.status, "rejected")  # history is not rewritten

    def test_a_live_task_is_handed_over_rather_than_forked(self):
        # With a task still in play, reassignment must close it out — never
        # leave two live tasks racing on one order.
        from delivery.models import DeliveryTask

        order = mk_order(self.store, mk_customer(), status="packed")
        task = DeliveryTask.objects.create(order=order, agent=self.mine, status="assigned")
        mate = mk_agent(self.store, name="Mate")
        r = self.mgr.post(
            f"/api/v1/store/delivery/{task.id}/reassign",
            {"agentId": str(mate.id)}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        task.refresh_from_db()
        self.assertEqual(task.status, "reassigned")
        live = DeliveryTask.objects.filter(
            order=order, status__in=["assigned", "accepted"]
        )
        self.assertEqual(live.count(), 1)
        self.assertEqual(live.first().agent_id, mate.id)


class StoreCollectionReassignTests(TestCase):
    """Handing a cash recovery to a different agent.

    The panel only ever offered this on a FAILED collection, so the everyday
    case — the agent holding it went off duty, is unreachable, or was the wrong
    person — had no lever: the collection sat with someone who was never going
    to work it. `cashcollections.services.manual_assign` has always accepted
    requested/assigned/failed/disputed; only the UI was narrower.
    """

    def setUp(self):
        from payments.models import CashCollection

        self.store = mk_store("Mine")
        self.other = mk_store("Theirs")
        self.mgr = client_for(mk_staff(self.store, "manager"))
        self.customer = mk_customer()
        mk_order(self.store, self.customer)  # makes them this store's customer
        self.agent = mk_agent(self.store, name="First")
        self.mate = mk_agent(self.store, name="Second")
        self.theirs = mk_agent(self.other, name="Outsider")
        self.coll = CashCollection.objects.create(
            user=self.customer, agent=self.agent, amount=1500, status="assigned"
        )

    def _reassign(self, agent):
        return self.mgr.post(
            f"/api/v1/store/collections/{self.coll.id}/reassign",
            {"agentId": str(agent.id)}, format="json",
        )

    def test_an_assigned_collection_can_be_moved_to_another_agent(self):
        r = self._reassign(self.mate)
        self.assertEqual(r.status_code, 200)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.agent_id, self.mate.id)
        self.assertEqual(self.coll.status, "assigned")

    def test_a_failed_collection_is_reopened_with_the_new_agent(self):
        self.coll.status = "failed"
        self.coll.save(update_fields=["status"])
        r = self._reassign(self.mate)
        self.assertEqual(r.status_code, 200)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.agent_id, self.mate.id)
        self.assertEqual(self.coll.status, "assigned")

    def test_the_move_is_written_to_the_assignment_history(self):
        # The store detail drawer reads this to answer "who handled it, and why
        # is it with someone else now".
        self._reassign(self.mate)
        from cashcollections.models import CollectionAssignmentHistory

        actions = list(
            CollectionAssignmentHistory.objects.filter(collection=self.coll)
            .values_list("action", flat=True)
        )
        self.assertIn("reassigned", actions)

    def test_another_stores_agent_is_refused(self):
        r = self._reassign(self.theirs)
        self.assertEqual(r.status_code, 400)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.agent_id, self.agent.id)

    def test_a_collection_mid_visit_is_not_pulled_from_under_the_agent(self):
        # accepted/en_route/reached are excluded by manual_assign: a rider at
        # the customer's door shouldn't have the task moved away.
        self.coll.status = "reached"
        self.coll.save(update_fields=["status"])
        r = self._reassign(self.mate)
        self.assertEqual(r.status_code, 409)
        self.coll.refresh_from_db()
        self.assertEqual(self.coll.agent_id, self.agent.id)

    def test_a_collection_for_another_stores_customer_is_invisible(self):
        from payments.models import CashCollection

        outsider = mk_customer()
        mk_order(self.other, outsider)
        foreign = CashCollection.objects.create(
            user=outsider, agent=self.theirs, amount=900, status="assigned"
        )
        r = self.mgr.post(
            f"/api/v1/store/collections/{foreign.id}/reassign",
            {"agentId": str(self.mate.id)}, format="json",
        )
        self.assertEqual(r.status_code, 404)
