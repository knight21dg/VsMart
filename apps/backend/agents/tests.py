from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import User
from agents import services
from agents.models import AgentAttendance


class AgentMeAvatarTests(TestCase):
    """avatar_url on GET /agents/me — what the app's first-login face-capture
    gate reads to decide whether to show the capture screen at all, and what
    a delivery's OrderTracking row gets seeded from at assignment time."""

    def setUp(self):
        self.agent = User.objects.create(phone="+919777777200", name="Agent", role="agent")

    def test_empty_until_uploaded(self):
        c = APIClient()
        c.force_authenticate(self.agent)
        r = c.get("/api/v1/agents/me")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["data"]["avatarUrl"], "")

    def test_reflects_uploaded_avatar(self):
        self.agent.avatar_url = "/api/v1/media/public/9/medium"
        self.agent.save(update_fields=["avatar_url"])
        c = APIClient()
        c.force_authenticate(self.agent)
        r = c.get("/api/v1/agents/me")
        self.assertEqual(r.json()["data"]["avatarUrl"], "/api/v1/media/public/9/medium")

    def test_delivery_assignment_seeds_tracking_photo_from_avatar(self):
        from accounts.models import AgentProfile
        from delivery import services as delivery_services
        from delivery.models import DeliveryTask
        from orders.models import Order, OrderTracking
        from stores.models import Store

        self.agent.avatar_url = "/api/v1/media/public/9/medium"
        self.agent.save(update_fields=["avatar_url"])
        AgentProfile.objects.create(user=self.agent, code="AGAV1", is_available=True)
        customer = User.objects.create(phone="+919777777201", name="Cust", role="customer")
        store = Store.objects.create(
            code="SAV1", name="Avatar Store", address="x",
            phone="+918000000099", gstin="29ABCDE1234F1Z5")
        order = Order.objects.create(
            user=customer, store=store, code="VSAV1",
            total=100, subtotal=100, status="ready_for_dispatch",
            payment_method="cod", payment_status="pending",
        )
        task = DeliveryTask.objects.create(order=order, agent=self.agent, status="assigned")
        delivery_services._seed_tracking_identity(task)
        tracking = OrderTracking.objects.get(order=order)
        self.assertEqual(tracking.agent_photo_url, "/api/v1/media/public/9/medium")


class AgentPerformanceTests(TestCase):
    """GET /agents/performance — lifetime totals plus a per-day breakdown for
    the app's trend chart (agent_app performance_screen.dart)."""

    def setUp(self):
        self.agent = User.objects.create(phone="+919777777300", name="Agent", role="agent")
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def test_empty_performance_still_returns_a_full_window(self):
        r = self.client.get("/api/v1/agents/performance")
        self.assertEqual(r.status_code, 200)
        d = r.json()["data"]
        self.assertEqual(d["deliveriesCompleted"], 0)
        self.assertEqual(len(d["daily"]), 14)
        self.assertTrue(all(day["deliveries"] == 0 for day in d["daily"]))

    def test_counts_todays_completed_delivery_in_both_total_and_daily(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask
        from orders.models import Order
        from stores.models import Store

        AgentProfile.objects.create(user=self.agent, code="AGPF1")
        customer = User.objects.create(phone="+919777777301", name="Cust", role="customer")
        store = Store.objects.create(
            code="SPF1", name="Perf Store", address="x",
            phone="+918000000098", gstin="29ABCDE1234F1Z6")
        order = Order.objects.create(
            user=customer, store=store, code="VSPF1",
            total=100, subtotal=100, status="delivered",
            payment_method="cod", payment_status="paid",
        )
        DeliveryTask.objects.create(
            order=order, agent=self.agent, status="delivered",
            delivered_at=timezone.now(),
        )
        d = self.client.get("/api/v1/agents/performance").json()["data"]
        self.assertEqual(d["deliveriesCompleted"], 1)
        today = timezone.localdate().isoformat()
        today_row = next(row for row in d["daily"] if row["date"] == today)
        self.assertEqual(today_row["deliveries"], 1)
        # The window's last entry is always today, so the trend chart doesn't
        # need to know "today" separately from the data.
        self.assertEqual(d["daily"][-1]["date"], today)

    def test_another_agents_work_never_counts(self):
        from accounts.models import AgentProfile
        from delivery.models import DeliveryTask
        from orders.models import Order
        from stores.models import Store

        other = User.objects.create(phone="+919777777302", name="Other", role="agent")
        AgentProfile.objects.create(user=other, code="AGPF2")
        customer = User.objects.create(phone="+919777777303", name="Cust2", role="customer")
        store = Store.objects.create(
            code="SPF2", name="Perf Store 2", address="x",
            phone="+918000000097", gstin="29ABCDE1234F1Z7")
        order = Order.objects.create(
            user=customer, store=store, code="VSPF2",
            total=100, subtotal=100, status="delivered",
            payment_method="cod", payment_status="paid",
        )
        DeliveryTask.objects.create(
            order=order, agent=other, status="delivered", delivered_at=timezone.now(),
        )
        d = self.client.get("/api/v1/agents/performance").json()["data"]
        self.assertEqual(d["deliveriesCompleted"], 0)
        self.assertTrue(all(row["deliveries"] == 0 for row in d["daily"]))


class AttendanceTests(TestCase):
    def setUp(self):
        self.agent = User.objects.create(phone="+919777777100", name="Agent", role="agent")
        self.admin = User.objects.create(phone="+919888888100", name="Admin", role="admin")

    def test_check_in_then_out(self):
        att = services.check_in(self.agent)
        self.assertTrue(att.on_duty)
        att2 = services.check_out(self.agent)
        self.assertFalse(att2.on_duty)
        # Same day → one row.
        self.assertEqual(AgentAttendance.objects.filter(agent=self.agent).count(), 1)

    def test_check_in_endpoint(self):
        c = APIClient()
        c.force_authenticate(self.agent)
        r = c.post("/api/v1/agents/attendance/check-in")
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["data"]["onDuty"])

    def test_attendance_history_current_month_default(self):
        services.check_in(self.agent)
        services.check_out(self.agent)
        c = APIClient()
        c.force_authenticate(self.agent)
        r = c.get("/api/v1/agents/attendance/history")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertEqual(data["month"], timezone.localdate().strftime("%Y-%m"))
        self.assertEqual(len(data["days"]), 1)
        day = data["days"][0]
        self.assertIsNotNone(day["hoursWorked"])
        self.assertFalse(day["onDuty"])  # already checked out

    def test_attendance_history_scoped_to_requested_month(self):
        att = services.check_in(self.agent)
        att.date = att.date.replace(month=1 if att.date.month != 1 else 2)
        att.save(update_fields=["date"])
        c = APIClient()
        c.force_authenticate(self.agent)
        # Current month (no rows moved into it) should come back empty.
        r = c.get("/api/v1/agents/attendance/history")
        self.assertEqual(r.json()["data"]["days"], [])
        # The month we moved the row into should have it.
        r2 = c.get(f"/api/v1/agents/attendance/history?month={att.date.strftime('%Y-%m')}")
        self.assertEqual(len(r2.json()["data"]["days"]), 1)

    def test_attendance_history_only_this_agents_rows(self):
        other = User.objects.create(phone="+919777777101", name="Other Agent", role="agent")
        services.check_in(other)
        services.check_in(self.agent)
        c = APIClient()
        c.force_authenticate(self.agent)
        r = c.get("/api/v1/agents/attendance/history")
        self.assertEqual(len(r.json()["data"]["days"]), 1)

    def test_live_operations_counts_on_duty(self):
        services.check_in(self.agent)
        data = services.live_operations()
        self.assertEqual(data["summary"]["agentsOnDuty"], 1)
        self.assertTrue(any(a["onDuty"] for a in data["agents"]))

    def test_live_ops_endpoint_admin_only(self):
        c = APIClient()
        c.force_authenticate(self.admin)
        r = c.get("/api/v1/admin/ops/live")
        self.assertEqual(r.status_code, 200)
        self.assertIn("summary", r.json()["data"])

        c2 = APIClient()
        c2.force_authenticate(self.agent)
        self.assertIn(c2.get("/api/v1/admin/ops/live").status_code, (401, 403))

    def test_online_from_recent_location(self):
        from delivery.models import DeliveryLocation

        DeliveryLocation.objects.create(agent=self.agent, latitude="12.97", longitude="77.60")
        data = services.live_operations()
        me = next(a for a in data["agents"] if a["id"] == str(self.agent.id))
        self.assertTrue(me["online"])
        self.assertEqual(me["lat"], 12.97)
