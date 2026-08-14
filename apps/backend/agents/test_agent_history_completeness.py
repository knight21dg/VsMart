"""The agent's history must be the exact complement of their active queue.

Two guarantees, both previously unenforced:

**1. A delivered order reaches history regardless of its type.** No payment
method, delivery mode or discount may hide completed work from the agent who did
it. Nothing in the stack filters delivered work by type today, and these tests
exist so nobody adds it.

**2. Nothing falls between the two lists.** The queue and the history were built
from two different notions of "done" — the queue dropped only `TERMINAL`, the
assignment engine used `TERMINAL | {failed}`, history used `TERMINAL`. A `failed`
delivery therefore stayed on the agent's active list forever AND appeared in no
history: dead work they could not clear, with no record they had attempted it.
Both now read `DeliveryTask.CLOSED_FOR_AGENT`.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from delivery.models import DeliveryTask
from inventory.models import Warehouse
from orders.models import Order, OrderItem, OrderStatus
from stores.models import Store
from zones.models import Zone


def _data(resp):
    body = resp.json()
    return body.get("data", body)


class AgentHistoryBase(TestCase):
    def setUp(self):
        self.cat = Category.objects.create(name="Grocery")
        self.wh = Warehouse.objects.create(code="WH1", name="WH 1", is_default=True)
        self.store = Store.objects.create(code="S1", name="Store 1", warehouse=self.wh)
        self.zone = Zone.objects.create(code="Z1", name="Zone 1", store=self.store)
        self.product = Product.objects.create(
            name="Rice", price=Decimal("100"), mrp=Decimal("120"), category=self.cat)
        self.customer = User.objects.create(
            phone="+919000000800", name="Cust", role="customer")
        self.agent = User.objects.create(
            phone="+919777777800", name="Agent", role="agent")
        self.client = APIClient()
        self.client.force_authenticate(self.agent)

    def mk_task(self, *, status, payment_method="cod", payment_status="pending",
                total="500", discount="0", coupon=""):
        order = Order.objects.create(
            user=self.customer, payment_method=payment_method,
            payment_status=payment_status, status=OrderStatus.DELIVERED,
            store=self.store, zone=self.zone, total=Decimal(total),
            discount=Decimal(discount), coupon_code=coupon,
            address_snapshot={"formatted": "1 Test Road", "name": "Cust"},
        )
        OrderItem.objects.create(
            order=order, product=self.product, quantity=1, name=self.product.name,
            price=Decimal("100"), mrp=Decimal("120"))
        return DeliveryTask.objects.create(
            order=order, agent=self.agent, status=status)

    def history(self, **params):
        q = "&".join(f"{k}={v}" for k, v in {"type": "delivery", **params}.items())
        return _data(self.client.get(f"/api/v1/agents/history?{q}"))

    def queue_codes(self):
        rows = _data(self.client.get("/api/v1/deliveries/assigned"))
        rows = rows if isinstance(rows, list) else rows.get("results", [])
        return {r.get("orderCode") or r.get("order_code") for r in rows}


class DeliveredHistoryByTypeTests(AgentHistoryBase):
    """A delivered order is delivered. Its payment type is not a reason to hide it."""

    #: (label, payment_method, payment_status, total, discount, coupon)
    TYPES = [
        ("cod unpaid", "cod", "pending", "500", "0", ""),
        ("cod paid", "cod", "paid", "500", "0", ""),
        ("prepaid online", "online", "paid", "500", "0", ""),
        ("upi", "upi", "paid", "500", "0", ""),
        ("credit", "credit", "pending", "500", "0", ""),
        ("discounted", "online", "paid", "450", "50", ""),
        ("coupon", "online", "paid", "400", "100", "SAVE100"),
        ("zero-value", "online", "paid", "0", "0", ""),
    ]

    def test_every_payment_type_reaches_delivered_history(self):
        expected = set()
        for label, method, pay_status, total, discount, coupon in self.TYPES:
            task = self.mk_task(
                status=DeliveryTask.Status.DELIVERED, payment_method=method,
                payment_status=pay_status, total=total, discount=discount,
                coupon=coupon)
            expected.add(task.order.code)

        page = self.history(limit=100)
        got = {r["reference"] for r in page["items"]}
        missing = expected - got
        self.assertEqual(
            missing, set(),
            f"delivered orders hidden from history by type: {missing}")
        self.assertEqual(page["total"], len(self.TYPES))

    def test_each_type_is_reported_as_completed(self):
        for label, method, pay_status, total, discount, coupon in self.TYPES:
            with self.subTest(type=label):
                task = self.mk_task(
                    status=DeliveryTask.Status.DELIVERED, payment_method=method,
                    payment_status=pay_status, total=total, discount=discount,
                    coupon=coupon)
                row = next(
                    r for r in self.history(limit=100)["items"]
                    if r["reference"] == task.order.code)
                self.assertEqual(row["outcome"], "success")
                self.assertEqual(row["status"], "delivered")

    def test_a_delivered_cod_order_awaiting_cash_is_in_BOTH_lists(self):
        """Deliberate: the cash is still owed, so it stays actionable AND recorded."""
        task = self.mk_task(status=DeliveryTask.Status.DELIVERED,
                            payment_method="cod", payment_status="pending")
        self.assertIn(task.order.code, self.queue_codes())
        self.assertIn(task.order.code,
                      {r["reference"] for r in self.history()["items"]})


class QueueAndHistoryAreComplementsTests(AgentHistoryBase):
    """Every status a task can hold belongs to exactly one of the two lists."""

    ACTIVE = ["assigned", "accepted", "picked_up", "out_for_delivery", "reached",
              "rescheduled", "return_initiated"]
    CLOSED = ["delivered", "rejected", "failed", "returned_to_store",
              "reassigned", "cancelled"]

    def test_active_statuses_are_on_the_queue_and_not_in_history(self):
        for status in self.ACTIVE:
            with self.subTest(status=status):
                task = self.mk_task(status=status, payment_method="online",
                                    payment_status="paid")
                self.assertIn(task.order.code, self.queue_codes())
                self.assertNotIn(
                    task.order.code,
                    {r["reference"] for r in self.history(limit=100)["items"]})

    def test_closed_statuses_are_in_history(self):
        for status in self.CLOSED:
            with self.subTest(status=status):
                task = self.mk_task(status=status, payment_method="online",
                                    payment_status="paid")
                self.assertIn(
                    task.order.code,
                    {r["reference"] for r in self.history(limit=100)["items"]},
                    f"{status} is closed work but absent from history")

    def test_no_status_falls_between_the_two_lists(self):
        """The bug this file exists for: `failed` was in neither."""
        every = set(DeliveryTask.Status.values)
        covered = set(self.ACTIVE) | set(self.CLOSED)
        self.assertEqual(
            every - covered, set(),
            "a DeliveryTask status is classified neither active nor closed")

    def test_a_failed_delivery_leaves_the_agents_queue(self):
        task = self.mk_task(status=DeliveryTask.Status.FAILED,
                            payment_method="online", payment_status="paid")
        self.assertNotIn(
            task.order.code, self.queue_codes(),
            "a failed attempt is the store's problem now, not the agent's")

    def test_a_failed_delivery_is_recorded_as_not_completed(self):
        task = self.mk_task(status=DeliveryTask.Status.FAILED)
        row = next(r for r in self.history(limit=100)["items"]
                   if r["reference"] == task.order.code)
        self.assertEqual(row["outcome"], "failed")

    def test_the_three_consumers_share_one_definition(self):
        """Queue, history and the assignment engine must not drift apart again."""
        from delivery.services import _agent_active_load

        # Paid, so the deliberate "delivered COD awaiting cash stays actionable"
        # exception is not in play — this asserts the general rule.
        for status in self.CLOSED:
            self.mk_task(status=status, payment_method="online",
                         payment_status="paid")
        # None of the closed work counts as load, and none of it is on the queue.
        self.assertEqual(_agent_active_load(self.agent), 0)
        self.assertEqual(self.queue_codes(), set())
        self.assertEqual(self.history(limit=100)["total"], len(self.CLOSED))


class HistoryPaginationTests(AgentHistoryBase):
    """Paging must not lose a delivered order."""

    def test_a_single_delivery_is_returned(self):
        self.mk_task(status=DeliveryTask.Status.DELIVERED)
        self.assertEqual(self.history()["total"], 1)

    def test_exactly_one_page_has_no_next(self):
        for _ in range(20):
            self.mk_task(status=DeliveryTask.Status.DELIVERED)
        page = self.history(limit=20, offset=0)
        self.assertEqual(len(page["items"]), 20)
        self.assertFalse(page["hasMore"])

    def test_one_more_than_a_page_pages_without_loss(self):
        codes = {self.mk_task(status=DeliveryTask.Status.DELIVERED).order.code
                 for _ in range(21)}
        seen, offset = set(), 0
        while True:
            page = self.history(limit=20, offset=offset)
            seen |= {r["reference"] for r in page["items"]}
            if not page["hasMore"]:
                break
            offset += 20
        self.assertEqual(seen, codes)

    def test_totals_describe_the_whole_set_not_the_page(self):
        for _ in range(25):
            self.mk_task(status=DeliveryTask.Status.DELIVERED)
        page = self.history(limit=5)
        self.assertEqual(len(page["items"]), 5)
        self.assertEqual(page["total"], 25)


class HistoryScopingTests(AgentHistoryBase):
    def test_an_agent_never_sees_another_agents_history(self):
        other = User.objects.create(
            phone="+919777777801", name="Other", role="agent")
        mine = self.mk_task(status=DeliveryTask.Status.DELIVERED)
        theirs = self.mk_task(status=DeliveryTask.Status.DELIVERED)
        DeliveryTask.objects.filter(pk=theirs.pk).update(agent=other)

        refs = {r["reference"] for r in self.history(limit=100)["items"]}
        self.assertIn(mine.order.code, refs)
        self.assertNotIn(theirs.order.code, refs)

    def test_a_non_agent_cannot_read_agent_history(self):
        c = APIClient()
        c.force_authenticate(self.customer)
        r = c.get("/api/v1/agents/history?type=delivery")
        self.assertIn(r.status_code, (401, 403))
