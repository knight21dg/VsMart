"""What a return reviewer can see, and who gets told about a decision.

Two gaps, both on the review half of the flow. A return cannot be submitted
without photos, yet `return_detail` — the payload BOTH the admin console and the
store panel read — carried none, so a reviewer approved or declined without ever
seeing the evidence the customer was forced to upload. And `set_return_status`
transitioned the return silently: approved, declined and refunded were equally
unannounced, so the customer's only way to learn the outcome was to reopen the
app and look.
"""
import io
import tempfile
from decimal import Decimal

from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient

from accounts.models import Role, User
from notifications.models import Notification
from orders.models import Order, OrderStatus
from returns.admin_service import return_detail, set_return_status
from returns.models import ReturnEvidence, ReturnItem, ReturnRequest, ReturnStatus

TMP_MEDIA = tempfile.mkdtemp(prefix="vsmart-returns-review-")


def _png_bytes():
    img = Image.new("RGB", (80, 60), (120, 30, 30))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


@override_settings(MEDIA_ROOT=TMP_MEDIA, MEDIA_INTERNAL_REDIRECT_PREFIX="")
class ReturnReviewVisibilityTests(TestCase):
    def setUp(self):
        self.customer = User.objects.create(
            phone="+919600077001", name="Cust", role=Role.CUSTOMER
        )
        self.admin = User.objects.create(
            phone="+919600077002", name="Admin", role=Role.ADMIN
        )
        self.order = Order.objects.create(
            user=self.customer, subtotal=Decimal("500"), total=Decimal("500"),
            status=OrderStatus.DELIVERED,
        )
        self.ret = ReturnRequest.objects.create(
            user=self.customer, order=self.order, reason="damaged",
            description="Box was crushed", refund_amount=Decimal("500"),
        )
        ReturnItem.objects.create(
            return_request=self.ret, product_name="Atta 5kg", quantity=2,
            amount=Decimal("500"),
        )

    def _evidence(self, source=ReturnEvidence.Source.CUSTOMER):
        from mediastore.pipeline import store_image

        asset = store_image(
            _png_bytes(), category="return", visibility="private",
            owner=self.customer, original_name="proof.png",
        )
        return ReturnEvidence.objects.create(
            return_request=self.ret, source=source, file_key=str(asset.id),
            uploaded_by=self.customer,
        )

    # ── evidence on the review payload ──
    def test_customer_photos_reach_the_reviewer(self):
        ev = self._evidence()
        detail = return_detail(self.ret)
        self.assertEqual(len(detail["evidence"]), 1)
        row = detail["evidence"][0]
        self.assertEqual(row["source"], "customer")
        self.assertEqual(row["url"], f"/returns/photos/{ev.id}")

    def test_agent_door_photos_are_distinguishable_from_customer_ones(self):
        self._evidence(ReturnEvidence.Source.CUSTOMER)
        self._evidence(ReturnEvidence.Source.AGENT)
        sources = [e["source"] for e in return_detail(self.ret)["evidence"]]
        self.assertEqual(sorted(sources), ["agent", "customer"])

    def test_a_return_with_no_photos_yields_an_empty_list_not_a_crash(self):
        self.assertEqual(return_detail(self.ret)["evidence"], [])

    def test_the_url_actually_serves_the_image_to_a_reviewer(self):
        """A URL that 403s or 404s would be no better than not sending one."""
        ev = self._evidence()
        client = APIClient()
        client.force_authenticate(self.admin)
        r = client.get(f"/api/v1/returns/photos/{ev.id}")
        self.assertEqual(r.status_code, 200)
        body = b"".join(r.streaming_content)
        r.close()
        self.assertTrue(body)

    def test_an_unrelated_customer_still_cannot_see_the_photo(self):
        ev = self._evidence()
        stranger = APIClient()
        stranger.force_authenticate(User.objects.create(
            phone="+919600077003", name="Nosy", role=Role.CUSTOMER))
        self.assertEqual(
            stranger.get(f"/api/v1/returns/photos/{ev.id}").status_code, 403
        )

    def test_settled_quantities_are_exposed_for_the_refund_decision(self):
        """The reviewer refunds on what the agent ACCEPTED, not what was asked."""
        item = self.ret.items.first()
        item.accepted_quantity = 1
        item.accepted_amount = Decimal("250")
        item.save(update_fields=["accepted_quantity", "accepted_amount"])
        row = return_detail(self.ret)["items"][0]
        self.assertEqual(row["quantity"], 2)
        self.assertEqual(row["acceptedQuantity"], 1)
        self.assertEqual(row["settledAmount"], 250.0)

    # ── decision notifications ──
    def _decisions(self):
        return Notification.objects.filter(user=self.customer, type="return")

    def test_approval_notifies_the_customer(self):
        set_return_status(self.ret, ReturnStatus.APPROVED, by=self.admin)
        self.assertTrue(self._decisions().filter(title="Return approved").exists())

    def test_rejection_carries_the_reviewers_reason(self):
        set_return_status(self.ret, ReturnStatus.REJECTED, by=self.admin,
                          note="Item shows use beyond inspection")
        note = self._decisions().get(title="Return declined")
        self.assertIn("Item shows use beyond inspection", note.body)

    def test_refund_notifies_with_the_amount(self):
        set_return_status(self.ret, ReturnStatus.APPROVED, by=self.admin)
        set_return_status(self.ret, ReturnStatus.REFUNDED, by=self.admin)
        self.assertTrue(
            self._decisions().filter(title="Refund issued", body__contains="500").exists()
        )

    def test_a_decision_is_announced_once(self):
        """A re-saved review must not buzz the customer again."""
        set_return_status(self.ret, ReturnStatus.APPROVED, by=self.admin)
        try:
            set_return_status(self.ret, ReturnStatus.APPROVED, by=self.admin)
        except ValueError:
            pass  # a same-state re-save may be refused; either way, one message
        self.assertEqual(self._decisions().filter(title="Return approved").count(), 1)

    def test_a_notification_failure_never_undoes_a_refund(self):
        from unittest import mock

        set_return_status(self.ret, ReturnStatus.APPROVED, by=self.admin)
        with mock.patch("notifications.services.notify", side_effect=RuntimeError):
            set_return_status(self.ret, ReturnStatus.REFUNDED, by=self.admin)
        self.ret.refresh_from_db()
        self.assertEqual(self.ret.status, ReturnStatus.REFUNDED)
