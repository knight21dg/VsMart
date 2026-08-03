from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from credit.models import CreditAccount
from crm import services


class Crm360Tests(TestCase):
    def setUp(self):
        self.admin = User.objects.create(phone="+919888888050", name="Admin", role="admin")
        self.customer = User.objects.create(
            phone="+919000000050", name="Ravi Kumar", role="customer",
            kyc_status="verified",
        )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_360_has_all_sections(self):
        data = services.customer_360(self.customer)
        for key in (
            "header", "health", "creditIntelligence", "orderAnalytics",
            "collectionAnalytics", "timeline", "verification", "geographic",
            "notes", "support", "network", "risk", "financialExposure",
            "aiInsights",
        ):
            self.assertIn(key, data)
        self.assertEqual(data["header"]["name"], "Ravi Kumar")
        self.assertEqual(data["header"]["vsId"], f"VS-CUST-{self.customer.id:08d}")

    def test_risk_low_without_credit(self):
        r = services.compute_risk(self.customer)
        self.assertEqual(r["level"], "low")
        self.assertEqual(r["score"], 0)

    def test_risk_high_when_utilized_and_overdue(self):
        acc = CreditAccount.objects.create(
            user=self.customer, credit_limit=Decimal("10000"),
            outstanding=Decimal("9500"),
        )
        from datetime import date

        from credit.models import Statement

        Statement.objects.create(
            account=acc, period_start=date(2026, 1, 1), period_end=date(2026, 1, 31),
            purchases=Decimal("9500"), payments=Decimal("0"),
            closing_balance=Decimal("9500"), due_date=date(2026, 2, 5),
            status="overdue",
        )
        r = services.compute_risk(self.customer)
        self.assertIn(r["level"], ("high", "critical"))
        self.assertGreater(r["score"], 50)

    def test_search_by_phone(self):
        r = self.client.get("/api/v1/admin/crm/customers", {"q": "9000000050"})
        names = {c["name"] for c in r.json()["data"]}
        self.assertIn("Ravi Kumar", names)

    def test_360_endpoint(self):
        r = self.client.get(f"/api/v1/admin/crm/customers/{self.customer.id}")
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["data"]["header"]["phone"], "+919000000050")

    def test_financial_exposure_and_insights(self):
        r = self.client.get(f"/api/v1/admin/crm/customers/{self.customer.id}")
        data = r.json()["data"]
        self.assertIn("financialExposure", data)
        self.assertIn("aiInsights", data)
        self.assertIn("dormant", data["aiInsights"])

    def test_create_support_ticket_action(self):
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "create_support_ticket", "subject": "Overdue follow-up"},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        from support.models import SupportTicket

        self.assertTrue(SupportTicket.objects.filter(user=self.customer).exists())

    def test_categorised_note(self):
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/notes",
            {"body": "Visited, not home", "category": "collection"}, format="json",
        )
        self.assertEqual(r.status_code, 201)
        data = services.customer_360(self.customer)
        self.assertTrue(data["notes"]["collection"])

    def test_add_note(self):
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/notes",
            {"body": "Called customer re: overdue."}, format="json",
        )
        self.assertEqual(r.status_code, 201)
        from crm.models import CustomerNote

        self.assertEqual(CustomerNote.objects.filter(customer=self.customer).count(), 1)

    def test_freeze_credit_action(self):
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "freeze_credit"}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        acc = CreditAccount.objects.get(user=self.customer)
        self.assertEqual(acc.status, "frozen")

    def test_set_limit_action(self):
        self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "set_limit", "limit": 25000}, format="json",
        )
        acc = CreditAccount.objects.get(user=self.customer)
        self.assertEqual(acc.credit_limit, Decimal("25000"))

    def test_suspend_action(self):
        self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "suspend"}, format="json",
        )
        self.customer.refresh_from_db()
        self.assertFalse(self.customer.is_active)

    def test_assign_collection_action(self):
        CreditAccount.objects.create(
            user=self.customer, credit_limit=Decimal("5000"),
            outstanding=Decimal("1200"),
        )
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "assign_collection"}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        from payments.models import CashCollection

        c = CashCollection.objects.filter(user=self.customer).first()
        self.assertIsNotNone(c)
        self.assertEqual(c.amount, Decimal("1200"))

    def test_assign_verification_action(self):
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "assign_verification", "type": "residence"}, format="json",
        )
        self.assertEqual(r.status_code, 200)
        from verification.models import VerificationTask

        self.assertTrue(
            VerificationTask.objects.filter(customer=self.customer, type="residence").exists()
        )

    def test_unknown_action_rejected(self):
        r = self.client.post(
            f"/api/v1/admin/crm/customers/{self.customer.id}/actions",
            {"action": "delete_everything"}, format="json",
        )
        self.assertEqual(r.status_code, 400)

    def test_analytics_endpoint(self):
        r = self.client.get("/api/v1/admin/crm/customers/analytics")
        self.assertEqual(r.status_code, 200)
        self.assertIn("riskDistribution", r.json()["data"])

    def test_non_admin_forbidden(self):
        c = APIClient()
        c.force_authenticate(self.customer)
        r = c.get(f"/api/v1/admin/crm/customers/{self.customer.id}")
        self.assertIn(r.status_code, (401, 403))

    def test_search_filter_by_kyc(self):
        r = self.client.get("/api/v1/admin/crm/customers", {"kyc": "verified"})
        rows = r.json()["data"]
        self.assertTrue(all(row["kycStatus"] == "verified" for row in rows))
        self.assertTrue(any(row["name"] == "Ravi Kumar" for row in rows))

    def test_search_sort_outstanding(self):
        CreditAccount.objects.create(
            user=self.customer, credit_limit=Decimal("5000"),
            outstanding=Decimal("900"),
        )
        r = self.client.get("/api/v1/admin/crm/customers", {"sort": "highest_outstanding"})
        rows = r.json()["data"]
        self.assertEqual(rows[0]["outstanding"], 900.0)

    def test_csv_export(self):
        r = self.client.get("/api/v1/admin/crm/customers/export", {"fmt": "csv"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r["Content-Type"], "text/csv")
        self.assertIn("VS ID", r.content.decode())

    def test_bulk_freeze(self):
        r = self.client.post(
            "/api/v1/admin/crm/customers/bulk",
            {"action": "freeze_credit", "customerIds": [self.customer.id]},
            format="json",
        )
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["data"]["affected"], 1)
        self.assertEqual(
            CreditAccount.objects.get(user=self.customer).status, "frozen"
        )

    def test_bulk_unknown_action_rejected(self):
        r = self.client.post(
            "/api/v1/admin/crm/customers/bulk",
            {"action": "nuke", "customerIds": [self.customer.id]},
            format="json",
        )
        self.assertEqual(r.status_code, 400)


class CustomerCreditStatusFilterTests(TestCase):
    """Staff need to find everyone whose credit is frozen."""

    def setUp(self):
        from rest_framework.test import APIClient

        from accounts.models import User
        from credit.models import CreditAccount

        self.admin = User.objects.create(phone="+919000000700", name="Boss", role="admin")
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

        def cust(phone, name, status=None):
            u = User.objects.create(phone=phone, name=name, role="customer")
            if status:
                CreditAccount.objects.create(user=u, status=status)
            return u

        cust("+919000000701", "FrozenFred", CreditAccount.Status.FROZEN)
        cust("+919000000702", "ActiveAnn", CreditAccount.Status.ACTIVE)
        cust("+919000000703", "NoCreditNina")

    def _names(self, **params):
        r = self.client.get("/api/v1/admin/crm/customers", params)
        body = r.json()["data"]
        rows = body["results"] if isinstance(body, dict) and "results" in body else body
        return {c["name"] for c in rows}

    def test_filter_frozen(self):
        self.assertEqual(self._names(creditStatus="frozen"), {"FrozenFred"})

    def test_filter_active_credit(self):
        self.assertEqual(self._names(creditStatus="active"), {"ActiveAnn"})

    def test_no_filter_returns_everyone(self):
        self.assertEqual(
            self._names(),
            {"FrozenFred", "ActiveAnn", "NoCreditNina"},
        )

    def test_credit_status_is_exposed_on_each_row(self):
        r = self.client.get("/api/v1/admin/crm/customers", {"q": "FrozenFred"})
        body = r.json()["data"]
        rows = body["results"] if isinstance(body, dict) and "results" in body else body
        self.assertEqual(rows[0]["creditStatus"], "frozen")

    def test_snake_case_param_also_works(self):
        self.assertEqual(self._names(credit_status="frozen"), {"FrozenFred"})


class CustomerDirectoryPaginationTests(TestCase):
    """The customer directory used to cap at `min(limit, 200)` with no offset
    parameter at all, so customer 201 onwards was unreachable and nothing told the
    operator the list had been truncated."""

    def setUp(self):
        self.admin = User.objects.create(
            phone="+919888888070", name="Admin", role="admin"
        )
        for i in range(25):
            User.objects.create(
                phone=f"+9190000008{i:02d}", name=f"Cust{i:02d}", role="customer"
            )
        self.client = APIClient()
        self.client.force_authenticate(self.admin)

    def test_envelope_carries_pagination_meta(self):
        r = self.client.get("/api/v1/admin/crm/customers")
        self.assertEqual(r.status_code, 200)
        body = r.json()
        self.assertEqual(body["meta"]["total"], 25)
        self.assertEqual(body["meta"]["page"], 1)
        self.assertGreater(body["meta"]["totalPages"], 1)
        # `data` stays a bare row array, so existing callers keep working.
        self.assertIsInstance(body["data"], list)

    def test_second_page_returns_different_customers(self):
        p1 = self.client.get("/api/v1/admin/crm/customers", {"page": 1}).json()
        p2 = self.client.get("/api/v1/admin/crm/customers", {"page": 2}).json()
        self.assertEqual(p2["meta"]["page"], 2)
        first = {c["id"] for c in p1["data"]}
        second = {c["id"] for c in p2["data"]}
        self.assertTrue(second)
        self.assertFalse(first & second)

    def test_every_customer_is_reachable_by_paging(self):
        seen, page = set(), 1
        while True:
            body = self.client.get(
                "/api/v1/admin/crm/customers", {"page": page}
            ).json()
            seen.update(c["id"] for c in body["data"])
            if page >= body["meta"]["totalPages"]:
                break
            page += 1
        self.assertEqual(len(seen), 25)

    def test_legacy_limit_still_returns_a_bare_list(self):
        body = self.client.get("/api/v1/admin/crm/customers", {"limit": 5}).json()
        self.assertEqual(len(body["data"]), 5)
        self.assertNotIn("meta", body)
