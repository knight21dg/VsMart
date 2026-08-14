"""Payment reconciliation safety — the states an unresolved payment may reach.

Prod order VSORD100025 sat PENDING for 17 days holding a unit of stock. Nothing was
broken: the gateway never answered, and `release_expired_reservations` correctly
refused to cancel an order whose money might already be captured. But there was no
state above PENDING, no operator surface, and no bound on the hold — so the safe
behaviour was indistinguishable from a stuck one.

The rule these enforce:

    NO MONEY LOST · NO FALSE PAYMENT STATE · NO PERMANENT STOCK LOCK ·
    NO SILENT CANCELLATION

Payment state comes from the gateway, never from the age of a row, the absence of a
callback, or anything the client says.
"""
from decimal import Decimal
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from accounts.models import AuditLog, User
from orders.models import Order, OrderStatus
from payments.models import Payment
from payments.reconciliation import confirm_captured, confirm_not_captured
from payments.services import (
    has_inflight_gateway_payment,
    reconcile_pending_payments,
)


class FakeGateway:
    """Stands in for Razorpay. `answer` is what the gateway reports; None = no record."""

    def __init__(self, answer=None, raises=False):
        self.answer = answer
        self.raises = raises
        self.calls = 0

    def fetch_order_payment(self, gateway_order_id):
        self.calls += 1
        if self.raises:
            raise RuntimeError("gateway unreachable")
        return self.answer


class ReconciliationBase(TestCase):
    def setUp(self):
        self.customer = User.objects.create(
            phone="+919000000700", name="Cust", role="customer")
        self.admin = User.objects.create(
            phone="+919888888700", name="Admin", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def mk(self, *, minutes_old=240, amount="109.00", status=Payment.Status.PENDING):
        order = Order.objects.create(
            user=self.customer, payment_method="upi", status=OrderStatus.PENDING,
            total=Decimal(amount), stock_state=Order.StockState.RESERVED,
        )
        p = Payment.objects.create(
            user=self.customer, purpose=Payment.Purpose.ORDER, order=order,
            amount=Decimal(amount), method=Payment.Method.UPI,
            gateway=Payment.Gateway.RAZORPAY, gateway_order_id="order_TEST1",
            status=status,
        )
        old = timezone.now() - timezone.timedelta(minutes=minutes_old)
        Payment.objects.filter(pk=p.pk).update(created_at=old)
        Order.objects.filter(pk=order.pk).update(placed_at=old)
        return Payment.objects.get(pk=p.pk), Order.objects.get(pk=order.pk)

    def sweep(self, gateway):
        with patch("payments.services.get_gateway", return_value=gateway):
            return reconcile_pending_payments(older_than_minutes=10)


class GatewayIsAuthoritativeTests(ReconciliationBase):
    def test_captured_but_callback_missing_is_settled(self):
        """The whole reason the sweep exists — money taken, webhook never landed."""
        p, order = self.mk()
        gw = FakeGateway({"status": "captured", "gateway_payment_id": "pay_1",
                          "amount": Decimal("109.00")})
        summary = self.sweep(gw)
        p.refresh_from_db(); order.refresh_from_db()
        self.assertEqual(summary["settled"], 1)
        self.assertEqual(p.status, Payment.Status.SUCCESS)
        self.assertEqual(order.payment_status, order.PaymentStatus.PAID)

    def test_failed_at_the_gateway_is_marked_failed_and_released(self):
        p, _ = self.mk()
        self.sweep(FakeGateway({"status": "failed"}))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.FAILED)
        # No longer in flight, so the expiry sweep may now release the stock.
        self.assertFalse(has_inflight_gateway_payment(p.order))

    def test_a_fresh_reservation_is_never_touched(self):
        """A checkout still in progress must not be reconciled out from under itself."""
        p, _ = self.mk(minutes_old=2)
        summary = self.sweep(FakeGateway({"status": "captured",
                                          "gateway_payment_id": "pay_x",
                                          "amount": Decimal("109.00")}))
        p.refresh_from_db()
        self.assertEqual(summary["checked"], 0)
        self.assertEqual(p.status, Payment.Status.PENDING)

    def test_still_pending_at_the_gateway_within_the_window_stays_pending(self):
        p, _ = self.mk(minutes_old=30)
        self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.PENDING)
        self.assertEqual(p.reconcile_attempts, 1)   # but the attempt is recorded

    def test_unresolved_past_the_window_is_flagged_not_cancelled(self):
        p, order = self.mk(minutes_old=400)
        summary = self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db(); order.refresh_from_db()
        self.assertEqual(summary["flagged"], 1)
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)
        # Not cancelled, and the stock is still deliberately held.
        self.assertEqual(order.status, OrderStatus.PENDING)
        self.assertEqual(order.stock_state, Order.StockState.RESERVED)

    def test_no_gateway_record_is_flagged_not_assumed_failed(self):
        """Absence of a record is not evidence of failure."""
        p, _ = self.mk(minutes_old=400)
        self.sweep(FakeGateway(None))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)

    def test_amount_mismatch_is_flagged_immediately(self):
        """The gateway HAS answered and the answer is wrong — that needs a human now."""
        p, _ = self.mk(minutes_old=20)
        self.sweep(FakeGateway({"status": "captured", "gateway_payment_id": "pay_2",
                                "amount": Decimal("50.00")}))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)
        self.assertIn("mismatch", p.reconcile_note.lower())


class GatewayUnavailableTests(ReconciliationBase):
    def test_an_outage_does_not_look_like_a_resolved_payment(self):
        p, _ = self.mk(minutes_old=30)
        summary = self.sweep(FakeGateway(raises=True))
        p.refresh_from_db()
        self.assertEqual(summary["errors"], 1)
        self.assertEqual(p.status, Payment.Status.PENDING)   # not failed, not settled
        self.assertEqual(p.reconcile_attempts, 1)
        self.assertIn("gateway error", p.reconcile_note)

    def test_a_long_outage_eventually_surfaces_the_row(self):
        p, _ = self.mk(minutes_old=400)
        self.sweep(FakeGateway(raises=True))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)

    def test_a_flagged_row_resolves_itself_when_the_gateway_recovers(self):
        """No human needed if the outage ends — flagged rows keep being asked."""
        p, _ = self.mk(minutes_old=400)
        self.sweep(FakeGateway(raises=True))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)

        self.sweep(FakeGateway({"status": "captured", "gateway_payment_id": "pay_3",
                                "amount": Decimal("109.00")}))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.SUCCESS)

    def test_retries_accumulate_rather_than_starting_over(self):
        p, _ = self.mk(minutes_old=30)
        for _ in range(3):
            self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db()
        self.assertEqual(p.reconcile_attempts, 3)
        self.assertIsNotNone(p.last_reconciled_at)


class NeverAutoCancelTests(ReconciliationBase):
    def test_flagged_payments_still_block_auto_cancellation(self):
        """Flagging for review must not make an order eligible for cancellation."""
        p, order = self.mk(minutes_old=400)
        self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)
        self.assertTrue(has_inflight_gateway_payment(order))

    def test_the_expiry_sweep_leaves_an_unresolved_order_alone(self):
        from orders.services import release_expired_reservations

        _, order = self.mk(minutes_old=400)
        with patch("payments.services.get_gateway", return_value=FakeGateway(None)):
            cancelled = release_expired_reservations(ttl_minutes=30)
        order.refresh_from_db()
        self.assertNotIn(order.code, cancelled)
        self.assertEqual(order.status, OrderStatus.PENDING)


class DuplicateCallbackTests(ReconciliationBase):
    def test_settling_twice_settles_once(self):
        p, order = self.mk()
        gw = FakeGateway({"status": "captured", "gateway_payment_id": "pay_4",
                          "amount": Decimal("109.00")})
        self.sweep(gw)
        self.sweep(gw)
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.SUCCESS)
        self.assertEqual(
            p.events.filter(status=Payment.Status.SUCCESS).count(), 1,
            "a duplicate callback must not write a second settlement event")

    def test_a_settled_payment_is_not_re_swept(self):
        p, _ = self.mk()
        self.sweep(FakeGateway({"status": "captured", "gateway_payment_id": "pay_5",
                                "amount": Decimal("109.00")}))
        gw2 = FakeGateway({"status": "captured", "gateway_payment_id": "pay_5",
                           "amount": Decimal("109.00")})
        summary = self.sweep(gw2)
        self.assertEqual(summary["checked"], 0)
        self.assertEqual(gw2.calls, 0)


class AdminSurfaceTests(ReconciliationBase):
    def flag_one(self):
        p, order = self.mk(minutes_old=400)
        self.sweep(FakeGateway({"status": "pending"}))
        return p, order

    def test_the_queue_lists_flagged_payments_with_their_exposure(self):
        p, order = self.flag_one()
        r = self.client.get("/api/v1/admin/payments/reconciliation")
        self.assertEqual(r.status_code, 200)
        data = r.json()["data"]
        self.assertEqual(data["total"], 1)
        row = data["payments"][0]
        self.assertEqual(row["id"], p.id)
        self.assertEqual(row["orderCode"], order.code)
        self.assertTrue(row["stockHeld"])
        self.assertGreaterEqual(row["ageMinutes"], 400)
        self.assertEqual(row["attempts"], 1)

    def test_an_operator_can_resolve_from_the_queue(self):
        p, _ = self.flag_one()
        r = self.client.post(f"/api/v1/admin/payments/{p.id}/confirm-not-captured",
                             {"reason": "not in dashboard"}, format="json")
        self.assertEqual(r.status_code, 200)
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.FAILED)

    def test_a_non_admin_cannot_resolve_a_payment(self):
        p, _ = self.flag_one()
        c = APIClient()
        c.force_authenticate(self.customer)
        r = c.post(f"/api/v1/admin/payments/{p.id}/confirm-captured",
                   {"capturedAmount": "109.00", "attested": True}, format="json")
        self.assertIn(r.status_code, (401, 403))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)

    def test_confirming_without_attestation_is_refused(self):
        p, _ = self.flag_one()
        r = self.client.post(f"/api/v1/admin/payments/{p.id}/confirm-captured",
                             {"capturedAmount": "109.00"}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "PAYMENT_ATTESTATION_REQUIRED")

    def test_confirming_without_an_amount_is_refused(self):
        p, _ = self.flag_one()
        r = self.client.post(f"/api/v1/admin/payments/{p.id}/confirm-captured",
                             {"attested": True}, format="json")
        self.assertEqual(r.status_code, 400)
        self.assertEqual(r.json()["code"], "PAYMENT_CAPTURED_AMOUNT_REQUIRED")

    def test_confirm_captured_settles_through_the_endpoint(self):
        p, order = self.flag_one()
        r = self.client.post(f"/api/v1/admin/payments/{p.id}/confirm-captured",
                             {"capturedAmount": "109.00", "attested": True,
                              "gatewayPaymentId": "pay_ui", "reason": "seen in dashboard"},
                             format="json")
        self.assertEqual(r.status_code, 200)
        body = r.json()["data"]
        self.assertEqual(body["status"], Payment.Status.SUCCESS)
        self.assertTrue(body["applied"])
        p.refresh_from_db(); order.refresh_from_db()
        self.assertEqual(order.payment_status, order.PaymentStatus.PAID)


class ConfirmCapturedTests(ReconciliationBase):
    """Confirm Captured records an externally verified fact. It is not Mark Paid."""

    def flagged(self, *, amount="109.00"):
        p, order = self.mk(minutes_old=400, amount=amount)
        self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db()
        return p, order

    # -- the happy path ------------------------------------------------------
    def test_confirmed_capture_becomes_paid(self):
        p, order = self.flagged()
        p, applied = confirm_captured(
            p, captured_amount=Decimal("109.00"), by=self.admin, attested=True,
            gateway_payment_id="pay_ok", reason="seen in dashboard")
        order.refresh_from_db()
        self.assertTrue(applied)
        self.assertEqual(p.status, Payment.Status.SUCCESS)
        self.assertEqual(order.payment_status, order.PaymentStatus.PAID)

    def test_a_delivered_order_keeps_its_delivery_state(self):
        """VSORD100011's shape: goods already handed over, payment confirmed later."""
        p, order = self.flagged(amount="649.00")
        Order.objects.filter(pk=order.pk).update(status=OrderStatus.DELIVERED)
        confirm_captured(p, captured_amount=Decimal("649.00"), by=self.admin,
                         attested=True)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.DELIVERED)   # untouched
        self.assertEqual(order.payment_status, order.PaymentStatus.PAID)

    # -- the guards ----------------------------------------------------------
    def test_attestation_is_mandatory(self):
        from core.app_errors import AppError

        p, _ = self.flagged()
        with self.assertRaises(AppError) as ctx:
            confirm_captured(p, captured_amount=Decimal("109.00"), by=self.admin)
        self.assertEqual(ctx.exception.code, "PAYMENT_ATTESTATION_REQUIRED")
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)

    def test_the_captured_amount_is_mandatory(self):
        from core.app_errors import AppError

        p, _ = self.flagged()
        with self.assertRaises(AppError) as ctx:
            confirm_captured(p, captured_amount=None, by=self.admin, attested=True)
        self.assertEqual(ctx.exception.code, "PAYMENT_CAPTURED_AMOUNT_REQUIRED")

    def test_an_actor_is_mandatory(self):
        from core.app_errors import AppError

        p, _ = self.flagged()
        with self.assertRaises(AppError) as ctx:
            confirm_captured(p, captured_amount=Decimal("109.00"), by=None,
                             attested=True)
        self.assertEqual(ctx.exception.code, "PAYMENT_RESOLVER_REQUIRED")

    def test_a_short_capture_is_refused_and_nothing_is_settled(self):
        """The provider took less than was due, so never a full settlement."""
        from core.app_errors import AppError

        p, order = self.flagged()
        with self.assertRaises(AppError) as ctx:
            confirm_captured(p, captured_amount=Decimal("50.00"), by=self.admin,
                             attested=True)
        self.assertEqual(ctx.exception.code, "PAYMENT_AMOUNT_MISMATCH")
        p.refresh_from_db(); order.refresh_from_db()
        # Whole transaction rolled back: still under review, order not paid.
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)
        self.assertNotEqual(order.payment_status, order.PaymentStatus.PAID)

    def test_an_over_capture_is_also_refused(self):
        from core.app_errors import AppError

        p, _ = self.flagged()
        with self.assertRaises(AppError):
            confirm_captured(p, captured_amount=Decimal("500.00"), by=self.admin,
                             attested=True)
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.RECONCILIATION_REQUIRED)

    def test_a_payment_not_under_review_cannot_be_confirmed(self):
        from core.app_errors import AppError

        p, _ = self.mk(minutes_old=5)   # still plain PENDING
        with self.assertRaises(AppError) as ctx:
            confirm_captured(p, captured_amount=Decimal("109.00"), by=self.admin,
                             attested=True)
        self.assertEqual(ctx.exception.code, "PAYMENT_NOT_UNDER_REVIEW")

    # -- idempotency and races ----------------------------------------------
    def test_clicking_twice_settles_once(self):
        p, _ = self.flagged()
        confirm_captured(p, captured_amount=Decimal("109.00"), by=self.admin,
                         attested=True, gateway_payment_id="pay_dup")
        p.refresh_from_db()
        p2, applied = confirm_captured(
            p, captured_amount=Decimal("109.00"), by=self.admin, attested=True,
            gateway_payment_id="pay_dup")
        self.assertFalse(applied)                       # reported, not repeated
        self.assertEqual(p2.status, Payment.Status.SUCCESS)
        self.assertEqual(
            p2.events.filter(status=Payment.Status.SUCCESS).count(), 1)
        self.assertEqual(Payment.objects.filter(order=p2.order).count(), 1)

    def test_the_scheduler_winning_the_race_is_reported_not_re_settled(self):
        p, _ = self.flagged()
        # Scheduler settles it while the operator has the row open.
        self.sweep(FakeGateway({"status": "captured", "gateway_payment_id": "pay_sch",
                                "amount": Decimal("109.00")}))
        p.refresh_from_db()
        self.assertEqual(p.status, Payment.Status.SUCCESS)

        p2, applied = confirm_captured(
            p, captured_amount=Decimal("109.00"), by=self.admin, attested=True)
        self.assertFalse(applied)
        self.assertEqual(p2.status, Payment.Status.SUCCESS)
        self.assertEqual(p2.events.filter(status=Payment.Status.SUCCESS).count(), 1)

    def test_a_scheduler_failure_verdict_is_reported_not_overwritten(self):
        p, _ = self.flagged()
        self.sweep(FakeGateway({"status": "failed"}))
        p.refresh_from_db()
        p2, applied = confirm_captured(
            p, captured_amount=Decimal("109.00"), by=self.admin, attested=True)
        self.assertFalse(applied)
        self.assertEqual(p2.status, Payment.Status.FAILED)

    # -- the ledger ----------------------------------------------------------
    def test_a_payment_event_records_the_transition(self):
        p, _ = self.flagged()
        confirm_captured(p, captured_amount=Decimal("109.00"), by=self.admin,
                         attested=True, gateway_payment_id="pay_ev", reason="verified")
        ev = p.events.filter(status=Payment.Status.SUCCESS).first()
        self.assertIsNotNone(ev)
        self.assertEqual(ev.previous_status, Payment.Status.RECONCILIATION_REQUIRED)
        self.assertEqual(ev.amount, Decimal("109.00"))
        self.assertEqual(ev.created_by_id, self.admin.id)
        self.assertIn("Confirmed captured", ev.note)

    def test_an_audit_log_records_the_admin_decision(self):
        p, order = self.flagged()
        confirm_captured(p, captured_amount=Decimal("109.00"), by=self.admin,
                         attested=True, reason="dashboard ref 12345")
        entry = AuditLog.objects.filter(action="payment.confirm_captured").first()
        self.assertIsNotNone(entry)
        self.assertEqual(entry.actor_id, self.admin.id)
        self.assertIn("109.00", str(entry.after))
        self.assertIn(order.code, str(entry.after))
        self.assertIn("dashboard ref 12345", str(entry.after))


class CapturedCancelledOrderTests(ReconciliationBase):
    """A capture on a CANCELLED order is money owed back, not revenue."""

    def flagged_cancelled(self, amount="336.00"):
        p, order = self.mk(minutes_old=400, amount=amount)
        self.sweep(FakeGateway({"status": "pending"}))
        Order.objects.filter(pk=order.pk).update(status=OrderStatus.CANCELLED)
        p.refresh_from_db(); order.refresh_from_db()
        return p, order

    def test_capture_is_recorded_then_refunded(self):
        p, order = self.flagged_cancelled()
        p, applied = confirm_captured(
            p, captured_amount=Decimal("336.00"), by=self.admin, attested=True,
            reason="captured on a cancelled order")
        self.assertTrue(applied)
        # The capture stands in the ledger...
        self.assertEqual(p.status, Payment.Status.SUCCESS)
        # ...and a refund reverses it, so the net position is zero.
        refund = Payment.objects.filter(
            purpose=Payment.Purpose.REFUND, order=order).first()
        self.assertIsNotNone(refund, "a captured cancelled order must be refunded")
        self.assertEqual(refund.amount, Decimal("336.00"))

    def test_the_cancelled_order_is_not_resurrected(self):
        p, order = self.flagged_cancelled()
        confirm_captured(p, captured_amount=Decimal("336.00"), by=self.admin,
                         attested=True)
        order.refresh_from_db()
        self.assertEqual(order.status, OrderStatus.CANCELLED)

    def test_confirming_twice_does_not_refund_twice(self):
        p, order = self.flagged_cancelled()
        confirm_captured(p, captured_amount=Decimal("336.00"), by=self.admin,
                         attested=True)
        p.refresh_from_db()
        confirm_captured(p, captured_amount=Decimal("336.00"), by=self.admin,
                         attested=True)
        self.assertEqual(
            Payment.objects.filter(purpose=Payment.Purpose.REFUND, order=order).count(),
            1, "the reconcile refund must be idempotent")

    def test_a_live_order_raises_no_refund(self):
        p, order = self.mk(minutes_old=400)
        self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db()
        confirm_captured(p, captured_amount=Decimal("109.00"), by=self.admin,
                         attested=True)
        self.assertFalse(
            Payment.objects.filter(purpose=Payment.Purpose.REFUND, order=order).exists(),
            "a refund must never be manufactured for an order that stands")


class ConfirmNotCapturedTests(ReconciliationBase):
    def flagged(self):
        p, order = self.mk(minutes_old=400)
        self.sweep(FakeGateway({"status": "pending"}))
        p.refresh_from_db()
        return p, order

    def test_provider_has_no_capture_marks_it_failed_and_frees_the_hold(self):
        p, order = self.flagged()
        p, applied = confirm_not_captured(p, by=self.admin, reason="nothing at provider")
        self.assertTrue(applied)
        self.assertEqual(p.status, Payment.Status.FAILED)
        self.assertFalse(has_inflight_gateway_payment(order))

    def test_it_never_marks_the_order_paid(self):
        p, order = self.flagged()
        confirm_not_captured(p, by=self.admin)
        order.refresh_from_db()
        self.assertNotEqual(order.payment_status, order.PaymentStatus.PAID)

    def test_it_is_audited(self):
        p, _ = self.flagged()
        confirm_not_captured(p, by=self.admin, reason="bank statement checked")
        entry = AuditLog.objects.filter(action="payment.confirm_not_captured").first()
        self.assertIsNotNone(entry)
        self.assertEqual(entry.actor_id, self.admin.id)

    def test_it_requires_an_actor(self):
        from core.app_errors import AppError

        p, _ = self.flagged()
        with self.assertRaises(AppError):
            confirm_not_captured(p, by=None)
