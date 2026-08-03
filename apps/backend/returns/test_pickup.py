"""Return pickup — customer submits with photos → auto-assigned to a field agent
→ agent settles it at the door (accept / partial accept / reject / reschedule).

Money never moves here: accepting only marks the goods collected (`picked`), the
store still presses refund.
"""
import io
import json
import tempfile
from decimal import Decimal

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import AgentProfile, User
from orders.models import Order, OrderItem
from returns.models import (
    ReturnEvidence,
    ReturnItem,
    ReturnPickupTask,
    ReturnRequest,
)
from inventory.models import Warehouse
from stores.models import Store


def _png(name="item.png"):
    img = Image.new("RGB", (200, 150), (120, 60, 40))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return SimpleUploadedFile(name, buf.getvalue(), content_type="image/png")


def _store(code="ST1", name="Main"):
    wh = Warehouse.objects.create(name=f"{name} WH", code=f"WH{code}")
    return Store.objects.create(code=code, name=name, status="active", warehouse=wh)


@override_settings(MEDIA_ROOT=tempfile.mkdtemp(prefix="vsmart-return-"),
                   MEDIA_INTERNAL_REDIRECT_PREFIX="")
class ReturnPickupFlowTests(TestCase):
    def setUp(self):
        self.store = _store()
        self.customer = User.objects.create(
            phone="+919000000501", name="Cust", role="customer")
        self.agent = User.objects.create(
            phone="+919000000502", name="Agent", role="agent")
        AgentProfile.objects.create(
            user=self.agent, store=self.store, is_available=True, code="AG1")

        self.order = Order.objects.create(
            user=self.customer, payment_method=Order.PaymentMethod.COD,
            status="delivered", total=Decimal("500"), payment_status="paid",
            store=self.store,
            address_snapshot={"latitude": "12.9716", "longitude": "77.5946"},
        )
        OrderItem.objects.create(
            order=self.order, product=None, name="Rice", quantity=2,
            price=Decimal("250"), mrp=Decimal("300"))

        self.client = APIClient()
        self.client.force_authenticate(self.customer)
        self.agent_client = APIClient()
        self.agent_client.force_authenticate(self.agent)

    # ── customer submission ──
    def _create(self, with_photo=True, items=None):
        payload = {"reason": "Damaged", "description": "Torn pack"}
        if with_photo:
            # Multipart carries every field as text, so `items` travels as a
            # JSON string — exactly how the app sends it alongside the files.
            if items is not None:
                payload["items"] = json.dumps(items)
            payload["photos"] = [_png()]
            return self.client.post(
                f"/api/v1/orders/{self.order.code}/returns", payload,
                format="multipart")
        if items is not None:
            payload["items"] = items
        return self.client.post(
            f"/api/v1/orders/{self.order.code}/returns", payload, format="json")

    def test_return_without_photos_is_rejected(self):
        r = self._create(with_photo=False)
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["error"]["code"], "RETURN_PHOTOS_REQUIRED")
        self.assertFalse(ReturnRequest.objects.exists())

    def test_submission_stores_photo_and_auto_assigns_pickup(self):
        r = self._create()
        self.assertEqual(r.status_code, 201)
        ret = ReturnRequest.objects.get()
        self.assertEqual(
            ret.evidence.filter(source=ReturnEvidence.Source.CUSTOMER).count(), 1)
        task = ret.pickup_tasks.get()
        self.assertEqual(task.agent, self.agent)
        self.assertEqual(task.status, ReturnPickupTask.Status.ASSIGNED)
        self.assertIsNotNone(task.assigned_at)
        # Destination copied off the order for the agent's map.
        self.assertEqual(str(task.dest_lat), "12.971600")

    def test_pickup_never_crosses_stores(self):
        """An agent belonging to another store must not be given this pickup —
        assignment used to pool every agent on the platform."""
        other = _store(code="ST2", name="Far")
        far_agent = User.objects.create(
            phone="+919000000503", name="Far", role="agent")
        AgentProfile.objects.create(
            user=far_agent, store=other, is_available=True, code="AG2")
        self._create()
        self.assertEqual(ReturnPickupTask.objects.get().agent, self.agent)

    def test_unassignable_pickup_is_still_created_and_swept_later(self):
        """No agent on duty → the task exists (visible to the store) and the
        dispatch sweep picks it up once somebody comes on duty."""
        AgentProfile.objects.filter(user=self.agent).update(is_available=False)
        r = self._create()
        self.assertEqual(r.status_code, 201)
        task = ReturnPickupTask.objects.get()
        self.assertIsNone(task.agent)

        AgentProfile.objects.filter(user=self.agent).update(is_available=True)
        from returns.pickup_services import assign_orphan_pickups

        self.assertEqual(assign_orphan_pickups(), 1)
        task.refresh_from_db()
        self.assertEqual(task.agent, self.agent)

    # ── agent workflow ──
    def _assigned_task(self):
        self._create(items=[{"productName": "Rice", "quantity": 2, "amount": 500}])
        return ReturnPickupTask.objects.get()

    def _walk_to_door(self, task):
        for step in ("accept", "en-route", "reach"):
            r = self.agent_client.post(
                f"/api/v1/agent/return-pickups/{task.id}/{step}", {}, format="json")
            self.assertEqual(r.status_code, 200, step)
        return r

    def test_task_appears_on_the_agents_list(self):
        task = self._assigned_task()
        r = self.agent_client.get("/api/v1/agent/return-pickups")
        rows = r.json()["data"]
        self.assertEqual([str(x["id"]) for x in rows], [str(task.id)])
        self.assertEqual(rows[0]["returnCode"], task.return_request.code)
        # The customer's photos travel with the task so the agent can compare.
        self.assertEqual(len(rows[0]["photos"]), 1)

    def test_agent_cannot_touch_another_agents_pickup(self):
        task = self._assigned_task()
        intruder = User.objects.create(
            phone="+919000000504", name="Nosy", role="agent")
        c = APIClient()
        c.force_authenticate(intruder)
        r = c.post(f"/api/v1/agent/return-pickups/{task.id}/accept", {},
                   format="json")
        self.assertEqual(r.status_code, 404)

    def test_complete_requires_agent_photo(self):
        task = self._assigned_task()
        self._walk_to_door(task)
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete", {}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["error"]["code"], "RETURN_EVIDENCE_REQUIRED")

    def _agent_photo(self, task):
        return self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/photo", {"photo": _png()},
            format="multipart")

    def test_accept_at_door_picks_up_without_moving_money(self):
        task = self._assigned_task()
        self._walk_to_door(task)
        self.assertEqual(self._agent_photo(task).status_code, 200)
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete",
            {"note": "Condition OK"}, format="json")
        self.assertEqual(r.status_code, 200)

        task.refresh_from_db()
        ret = task.return_request
        ret.refresh_from_db()
        self.assertEqual(task.status, ReturnPickupTask.Status.COMPLETED)
        self.assertEqual(ret.status, "picked")          # NOT refunded
        self.assertEqual(ret.refund_amount, Decimal("500"))
        self.assertEqual(ret.decided_by, self.agent)
        self.order.refresh_from_db()
        self.assertEqual(self.order.payment_status, "paid")  # untouched

    def test_partial_accept_recalculates_the_refund(self):
        task = self._assigned_task()
        item = ReturnItem.objects.get()
        self._walk_to_door(task)
        self._agent_photo(task)
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete",
            {"decisions": {str(item.id): 1}}, format="json")
        self.assertEqual(r.status_code, 200)

        item.refresh_from_db()
        self.assertEqual(item.accepted_quantity, 1)
        self.assertEqual(item.accepted_amount, Decimal("250.00"))
        task.return_request.refresh_from_db()
        self.assertEqual(task.return_request.refund_amount, Decimal("250.00"))

    def test_accepting_more_than_requested_is_rejected(self):
        task = self._assigned_task()
        item = ReturnItem.objects.get()
        self._walk_to_door(task)
        self._agent_photo(task)
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete",
            {"decisions": {str(item.id): 5}}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["error"]["code"], "RETURN_QUANTITY_INVALID")

    def test_reject_at_door_closes_the_return(self):
        task = self._assigned_task()
        self._walk_to_door(task)
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/reject",
            {"reason_code": "item_used", "note": "Clearly used"}, format="json")
        self.assertEqual(r.status_code, 200)

        task.refresh_from_db()
        ret = task.return_request
        ret.refresh_from_db()
        self.assertEqual(task.status, ReturnPickupTask.Status.REJECTED)
        self.assertEqual(task.reason_code, "item_used")
        self.assertEqual(ret.status, "rejected")
        self.assertIsNotNone(ret.resolved_at)

    def test_reject_needs_a_known_reason_code(self):
        task = self._assigned_task()
        self._walk_to_door(task)
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/reject",
            {"reason_code": "because"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_reschedule_keeps_the_task_open(self):
        task = self._assigned_task()
        self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/accept", {}, format="json")
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/reschedule",
            {"reason_code": "customer_unavailable"}, format="json")
        self.assertEqual(r.status_code, 200)

        task.refresh_from_db()
        self.assertEqual(task.status, ReturnPickupTask.Status.RESCHEDULED)
        self.assertEqual(task.attempt_no, 2)
        self.assertFalse(task.is_terminal)
        # Still on the agent's open list.
        rows = self.agent_client.get("/api/v1/agent/return-pickups").json()["data"]
        self.assertEqual(len(rows), 1)

    def test_cannot_complete_before_reaching_the_customer(self):
        task = self._assigned_task()
        self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/accept", {}, format="json")
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete", {}, format="json")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(r.json()["error"]["code"], "INVALID_RETURN_TRANSITION")

    def test_settled_return_cannot_be_settled_twice(self):
        task = self._assigned_task()
        self._walk_to_door(task)
        self._agent_photo(task)
        self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete", {}, format="json")
        r = self.agent_client.post(
            f"/api/v1/agent/return-pickups/{task.id}/complete", {}, format="json")
        self.assertEqual(r.status_code, 409)

    # ── evidence permissions ──
    def test_return_photo_is_permission_gated(self):
        task = self._assigned_task()
        ev = task.return_request.evidence.first()
        url = f"/api/v1/returns/photos/{ev.id}"
        # customer + assigned agent may see it
        self.assertEqual(self.client.get(url).status_code, 200)
        self.assertEqual(self.agent_client.get(url).status_code, 200)
        # an unrelated customer may not
        stranger = User.objects.create(
            phone="+919000000505", name="Stranger", role="customer")
        c = APIClient()
        c.force_authenticate(stranger)
        self.assertEqual(c.get(url).status_code, 403)
