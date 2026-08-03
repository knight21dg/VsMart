"""Credit application lifecycle: apply -> review -> decision -> grant.

The guarantee these lock down: an explicit **approved limit** is the only thing
that gives a customer a usable credit line. KYC approval must not.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User

from .models import CreditAccount, CreditApplication


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


class CreditApplicationTests(TestCase):
    BODY = {
        "occupation": "Teacher", "monthlyIncome": "25000", "familyMembers": 4,
        "houseType": "apartment", "ownership": "rented", "requestedLimit": "5000",
    }

    def setUp(self):
        self.user = User.objects.create(
            phone="+919000000600", name="Applicant", kyc_status="verified",
        )
        self.admin = User.objects.create(
            phone="+919000000601", name="Reviewer", role="admin",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        self.staff = APIClient()
        self.staff.force_authenticate(self.admin)

    def _apply(self, client=None, **over):
        return (client or self.client).post(
            "/api/v1/credit/apply", {**self.BODY, **over}, format="json"
        )

    def _decide(self, app, **body):
        return self.staff.post(
            f"/api/v1/admin/credit/applications/{app.id}/decision",
            body, format="json",
        )

    def _app(self):
        return CreditApplication.objects.get(user=self.user)

    # ── submit ──
    def test_apply_creates_a_submitted_application(self):
        r = self._apply()
        self.assertEqual(r.status_code, 201, r.json())
        app = self._app()
        self.assertEqual(app.status, CreditApplication.Status.SUBMITTED)
        self.assertIsNotNone(app.submitted_at)

    def test_the_financial_fields_actually_persist(self):
        """Regression: the app collected these and dropped them on the floor —
        nothing was ever sent to the server."""
        self._apply()
        app = self._app()
        for field, expected in (
            ("occupation", "Teacher"),
            ("monthly_income", Decimal("25000")),
            ("family_members", 4),
            ("house_type", "apartment"),
            ("ownership", "rented"),
            ("requested_limit", Decimal("5000")),
        ):
            self.assertEqual(getattr(app, field), expected, field)

    def test_unverified_kyc_cannot_apply(self):
        self.user.kyc_status = "not_started"
        self.user.save(update_fields=["kyc_status"])
        self.assertEqual(self._apply().status_code, 403)

    def test_cannot_apply_twice_while_under_review(self):
        self.assertEqual(self._apply().status_code, 201)
        self.assertEqual(self._apply().status_code, 409)

    def test_invalid_payload_is_rejected(self):
        self.assertEqual(self._apply(requestedLimit="0").status_code, 400)
        self.assertEqual(self._apply(houseType="castle").status_code, 400)
        self.assertEqual(self._apply(familyMembers=0).status_code, 400)

    def test_resubmitting_after_rejection_reuses_the_row(self):
        self._apply()
        self._decide(self._app(), decision="reject", reason="Income too low")
        self.assertEqual(self._apply().status_code, 201)
        self.assertEqual(
            CreditApplication.objects.filter(user=self.user).count(), 1
        )
        app = self._app()
        self.assertEqual(app.status, CreditApplication.Status.SUBMITTED)
        # A resubmission must not carry the old decision forward.
        self.assertEqual(app.rejection_reason, "")
        self.assertIsNone(app.decided_at)

    # ── decision ──
    def test_approval_grants_the_limit_and_enables_credit(self):
        self._apply()
        self.assertFalse(self.user.credit_enabled)

        r = self._decide(self._app(), decision="approve", approvedLimit="3000")
        self.assertEqual(r.status_code, 200, r.json())

        app = self._app()
        self.user.refresh_from_db()
        self.assertEqual(app.status, CreditApplication.Status.APPROVED)
        self.assertEqual(app.approved_limit, Decimal("3000"))
        self.assertEqual(app.decided_by_id, self.admin.id)
        self.assertTrue(self.user.credit_enabled)
        account = CreditAccount.objects.get(user=self.user)
        self.assertEqual(account.credit_limit, Decimal("3000"))
        self.assertEqual(account.sanctioned_limit, Decimal("3000"))

    def test_approval_with_a_zero_limit_is_refused(self):
        self._apply()
        r = self._decide(self._app(), decision="approve", approvedLimit="0")
        self.assertEqual(r.status_code, 400)
        self.user.refresh_from_db()
        self.assertFalse(self.user.credit_enabled)

    def test_rejection_requires_a_customer_facing_reason(self):
        self._apply()
        self.assertEqual(
            self._decide(self._app(), decision="reject", reason="  ").status_code,
            400,
        )

    def test_a_decided_application_cannot_be_decided_again(self):
        self._apply()
        self._decide(self._app(), decision="approve", approvedLimit="3000")
        r = self._decide(self._app(), decision="approve", approvedLimit="99999")
        self.assertEqual(r.status_code, 409)
        self.assertEqual(
            CreditAccount.objects.get(user=self.user).credit_limit, Decimal("3000")
        )

    def test_kyc_approval_alone_does_not_grant_credit(self):
        """The core decoupling: verifying identity must not open a credit line."""
        from kyc.models import KycApplication
        from kyc.services import approve as approve_kyc

        user = User.objects.create(phone="+919000000602", name="Fresh")
        approve_kyc(KycApplication.objects.create(user=user), self.admin)
        user.refresh_from_db()
        self.assertEqual(user.kyc_status, "verified")
        self.assertFalse(
            user.credit_enabled, "KYC approval must not switch on credit"
        )
        self.assertFalse(CreditAccount.objects.filter(user=user).exists())

    # ── authorization ──
    def test_customer_cannot_decide_their_own_application(self):
        self._apply()
        r = self.client.post(
            f"/api/v1/admin/credit/applications/{self._app().id}/decision",
            {"decision": "approve", "approvedLimit": "99999"}, format="json",
        )
        self.assertEqual(r.status_code, 403)
        self.user.refresh_from_db()
        self.assertFalse(self.user.credit_enabled)

    def test_customer_cannot_read_the_admin_queue(self):
        self.assertEqual(
            self.client.get("/api/v1/admin/credit/applications").status_code, 403
        )

    def test_customer_cannot_raise_their_own_limit(self):
        r = self.client.post(
            f"/api/v1/admin/credit/users/{self.user.id}/limit",
            {"creditLimit": "50000"}, format="json",
        )
        self.assertEqual(r.status_code, 403)

    # ── customer status ──
    def test_status_endpoint_returns_the_customers_own_application(self):
        # No application yet — the envelope renders a null payload as {}.
        self.assertFalse(_data(self.client.get("/api/v1/credit/application")))
        self._apply()
        data = _data(self.client.get("/api/v1/credit/application"))
        self.assertEqual(data["status"], "submitted")
        # The reviewer's internal note must never reach the applicant.
        self.assertNotIn("decisionNote", data)

    def test_rejection_reason_reaches_the_customer_but_the_note_does_not(self):
        self._apply()
        self._decide(self._app(), decision="reject", reason="Income too low",
                     note="Internal: bureau thin file")
        data = _data(self.client.get("/api/v1/credit/application"))
        self.assertEqual(data["rejectionReason"], "Income too low")
        self.assertNotIn("decisionNote", data)

    def test_withdraw_releases_the_queue_slot(self):
        self._apply()
        r = self.client.post("/api/v1/credit/application/withdraw", {},
                             format="json")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(self._apply().status_code, 201)

    # ── queue ──
    def test_queue_is_fifo_and_filters_to_pending(self):
        other = User.objects.create(phone="+919000000603", name="Bala",
                                    kyc_status="verified")
        c2 = APIClient()
        c2.force_authenticate(other)
        self._apply()
        self._apply(client=c2)
        rows = _data(
            self.staff.get("/api/v1/admin/credit/applications?status=pending")
        )
        self.assertEqual([r["customerName"] for r in rows], ["Applicant", "Bala"])

        # A decided application drops out of the pending queue.
        self._decide(self._app(), decision="approve", approvedLimit="1000")
        rows = _data(
            self.staff.get("/api/v1/admin/credit/applications?status=pending")
        )
        self.assertEqual([r["customerName"] for r in rows], ["Bala"])

    def test_detail_gives_the_reviewer_account_and_bureau_context(self):
        self._apply()
        data = _data(
            self.staff.get(f"/api/v1/admin/credit/applications/{self._app().id}")
        )
        self.assertEqual(data["customerPhone"], "+919000000600")
        self.assertIn("account", data)
        self.assertIn("bureau", data)

    # ── limit management ──
    def test_admin_can_adjust_a_live_limit(self):
        self._apply()
        self._decide(self._app(), decision="approve", approvedLimit="3000")
        r = self.staff.post(
            f"/api/v1/admin/credit/users/{self.user.id}/limit",
            {"creditLimit": "8000"}, format="json",
        )
        self.assertEqual(r.status_code, 200, r.json())
        self.assertEqual(
            CreditAccount.objects.get(user=self.user).credit_limit, Decimal("8000")
        )

    def test_dropping_a_limit_to_zero_revokes_credit(self):
        from .services import set_credit_limit

        self._apply()
        self._decide(self._app(), decision="approve", approvedLimit="3000")
        set_credit_limit(self.user, 0, actor=self.admin)
        self.user.refresh_from_db()
        self.assertFalse(self.user.credit_enabled)

    def test_a_negative_limit_is_refused(self):
        r = self.staff.post(
            f"/api/v1/admin/credit/users/{self.user.id}/limit",
            {"creditLimit": "-5"}, format="json",
        )
        self.assertEqual(r.status_code, 400)
