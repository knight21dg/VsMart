from rest_framework import status as http
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from core.pagination import EnvelopePagination
from core.permissions import IsAdmin

from . import services
from .models import CustomerNote


def _customer(pk):
    return get_object_or_404(User, pk=pk, role="customer")


def _search_kwargs(p):
    """Pull the CRM list filters/sort from query params."""
    return dict(
        zone=p.get("zone") or None,
        store=p.get("store") or None,
        kyc=p.get("kyc") or None,
        credit=p.get("credit") or None,
        status=p.get("status") or None,
        risk=p.get("risk") or None,
        # Accept camelCase too — the admin console sends camelCase params.
        credit_status=p.get("creditStatus") or p.get("credit_status") or None,
        sort=p.get("sort") or "newest",
    )


class CustomerSearchView(APIView):
    """Search + filter + sort the customer directory (mobile/id/name/village/area,
    plus zone/store/risk/kyc/credit/status filters and a sort key) — PAGINATED.

    Emits the standard ``{data, meta:{page,total,totalPages}}`` envelope via
    :class:`core.pagination.EnvelopePagination`, so the console can reach every
    match. It previously sliced to ``min(limit, 200)`` with no offset parameter at
    all, so customer 201 onwards was unreachable and the operator got no hint that
    the list had been cut off.

    A caller may still pass ``limit`` for a legacy unpaginated slice.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        p = request.query_params
        source = services.customer_directory_source(p.get("q", ""), **_search_kwargs(p))
        # Legacy escape hatch: an explicit ?limit= returns a bare list as before.
        if p.get("limit"):
            limit = min(int(p["limit"] or 100), 200)
            return Response(services.customer_rows(source[:limit]))
        paginator = EnvelopePagination()
        page = paginator.paginate_queryset(source, request, view=self)
        return paginator.get_paginated_response(services.customer_rows(page))


class CustomerExportView(APIView):
    """Export the (filtered) customer directory as CSV or Excel."""

    permission_classes = [IsAdmin]

    COLUMNS = ["VS ID", "Name", "Phone", "VS Score", "Outstanding", "Orders",
               "Revenue", "Risk", "KYC", "Status"]

    def get(self, request):
        import csv
        import io

        from django.http import HttpResponse

        p = request.query_params
        rows = services.search_customers(
            p.get("q", ""), limit=5000, **_search_kwargs(p)
        )
        table = [
            [r["vsId"], r["name"], r["phone"], r["vsScore"], r["outstanding"],
             r["orders"], r["revenue"], r["risk"], r["kycStatus"],
             "active" if r["active"] else "suspended"]
            for r in rows
        ]
        fmt = p.get("fmt", "csv")
        if fmt == "excel":
            from openpyxl import Workbook

            wb = Workbook()
            ws = wb.active
            ws.title = "Customers"
            ws.append(self.COLUMNS)
            for row in table:
                ws.append(row)
            buf = io.BytesIO()
            wb.save(buf)
            resp = HttpResponse(
                buf.getvalue(),
                content_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            )
            resp["Content-Disposition"] = 'attachment; filename="customers.xlsx"'
            return resp
        buf = io.StringIO()
        w = csv.writer(buf)
        w.writerow(self.COLUMNS)
        w.writerows(table)
        resp = HttpResponse(buf.getvalue(), content_type="text/csv")
        resp["Content-Disposition"] = 'attachment; filename="customers.csv"'
        return resp


class CustomerBulkView(APIView):
    """Bulk actions over selected customers (freeze/unfreeze credit, assign a
    collection, send a notification)."""

    permission_classes = [IsAdmin]

    def post(self, request):
        action = request.data.get("action")
        ids = request.data.get("customerIds") or request.data.get("customer_ids") or []
        customers = list(User.objects.filter(pk__in=ids, role="customer"))
        if not customers:
            return Response(
                {"error": {"code": "bad_request", "message": "No customers selected", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        handler = {
            "freeze_credit": self._freeze,
            "unfreeze_credit": self._unfreeze,
            "assign_collection": self._assign_collection,
            "send_notification": self._notify,
        }.get(action)
        if handler is None:
            return Response(
                {"error": {"code": "unknown_action", "message": f"Unknown action '{action}'", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        count = handler(customers, request.data, request.user)
        record_audit(request.user, f"crm.bulk.{action}", after={"count": count, "ids": ids})
        return Response({"action": action, "affected": count})

    def _freeze(self, customers, data, actor):
        from credit.models import CreditAccount
        from credit.services import ensure_account

        for c in customers:
            acc = ensure_account(c)
            acc.status = CreditAccount.Status.FROZEN
            acc.save(update_fields=["status"])
        return len(customers)

    def _unfreeze(self, customers, data, actor):
        from credit.models import CreditAccount
        from credit.services import ensure_account

        for c in customers:
            acc = ensure_account(c)
            acc.status = CreditAccount.Status.ACTIVE
            acc.save(update_fields=["status"])
        return len(customers)

    def _assign_collection(self, customers, data, actor):
        from payments.models import CashCollection

        agent = None
        if data.get("agent_id"):
            agent = User.objects.filter(pk=data["agent_id"], role="agent").first()
        made = 0
        for c in customers:
            acc = getattr(c, "credit_account", None)
            amount = acc.outstanding if acc else 0
            if amount and amount > 0:
                CashCollection.objects.create(
                    user=c, amount=amount, agent=agent,
                    status="assigned" if agent else "requested",
                )
                made += 1
        return made

    def _notify(self, customers, data, actor):
        from notifications.services import notify

        title = data.get("title", "Message from VS Mart")
        body = data.get("body", "")
        for c in customers:
            notify(c, type="admin", title=title, body=body, data={})
        return len(customers)


class Customer360View(APIView):
    """The consolidated Customer-360 profile (all nine sections)."""

    permission_classes = [IsAdmin]

    def get(self, request, pk):
        return Response(services.customer_360(_customer(pk)))


class CustomerTimelineView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        return Response(services.build_timeline(_customer(pk)))


class CustomerNotesView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, pk):
        customer = _customer(pk)
        body = (request.data.get("body") or "").strip()
        if not body:
            return Response(
                {"error": {"code": "bad_request", "message": "body required", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        category = request.data.get("category", CustomerNote.Category.ADMIN)
        if category not in CustomerNote.Category.values:
            category = CustomerNote.Category.ADMIN
        note = CustomerNote.objects.create(
            customer=customer, author=request.user, body=body, category=category,
        )
        return Response(
            {"id": str(note.id), "body": note.body, "category": note.category,
             "at": note.created_at},
            status=http.HTTP_201_CREATED,
        )


class CustomerActionView(APIView):
    """Admin actions on a customer (spec §Admin Actions). Each mutates the relevant
    source module and is audit-logged; CRM stores nothing itself."""

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        customer = _customer(pk)
        action = request.data.get("action")
        data = request.data
        handler = {
            "freeze_credit": self._freeze,
            "unfreeze_credit": self._unfreeze,
            "set_limit": self._set_limit,
            "increase_limit": self._set_limit,
            "reduce_limit": self._set_limit,
            "suspend": self._suspend,
            "reactivate": self._reactivate,
            "assign_collection": self._assign_collection,
            "assign_collection_agent": self._assign_collection,
            "create_collection_task": self._assign_collection,
            "assign_verification": self._assign_verification,
            "assign_verification_agent": self._assign_verification,
            "create_verification_task": self._assign_verification,
            "assign_delivery_agent": self._assign_delivery_agent,
            "create_support_ticket": self._create_ticket,
        }.get(action)
        if handler is None:
            return Response(
                {"error": {"code": "unknown_action", "message": f"Unknown action '{action}'", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        result = handler(customer, data, request.user)
        record_audit(request.user, f"crm.{action}", target=customer, after=result)
        return Response({"action": action, "result": result})

    # ── handlers ──
    def _account(self, customer):
        from credit.services import ensure_account

        return ensure_account(customer)

    def _freeze(self, customer, data, actor):
        from credit.models import CreditAccount

        acc = self._account(customer)
        acc.status = CreditAccount.Status.FROZEN
        acc.save(update_fields=["status"])
        return {"creditStatus": acc.status}

    def _unfreeze(self, customer, data, actor):
        from credit.models import CreditAccount

        acc = self._account(customer)
        acc.status = CreditAccount.Status.ACTIVE
        acc.save(update_fields=["status"])
        return {"creditStatus": acc.status}

    def _set_limit(self, customer, data, actor):
        from decimal import Decimal

        acc = self._account(customer)
        acc.credit_limit = Decimal(str(data.get("limit", acc.credit_limit)))
        acc.save(update_fields=["credit_limit"])
        return {"creditLimit": float(acc.credit_limit)}

    def _suspend(self, customer, data, actor):
        customer.is_active = False
        customer.save(update_fields=["is_active"])
        return {"active": False}

    def _reactivate(self, customer, data, actor):
        customer.is_active = True
        customer.save(update_fields=["is_active"])
        return {"active": True}

    def _assign_collection(self, customer, data, actor):
        from decimal import Decimal

        from payments.models import CashCollection

        acc = self._account(customer)
        amount = Decimal(str(data.get("amount") or acc.outstanding))
        agent = None
        if data.get("agent_id"):
            agent = User.objects.filter(pk=data["agent_id"], role="agent").first()
        c = CashCollection.objects.create(
            user=customer, amount=amount, agent=agent,
            status="assigned" if agent else "requested",
        )
        return {"collectionId": str(c.id), "amount": float(amount)}

    def _assign_verification(self, customer, data, actor):
        from verification.models import VerificationTask

        vtype = data.get("type", VerificationTask.Type.RESIDENCE)
        agent = None
        if data.get("agent_id"):
            agent = User.objects.filter(pk=data["agent_id"], role="agent").first()
        t = VerificationTask.objects.create(
            customer=customer, type=vtype, agent=agent,
            status="assigned" if agent else "pending",
        )
        return {"taskId": str(t.id), "type": t.type}

    def _assign_delivery_agent(self, customer, data, actor):
        # No persistent customer→delivery-agent model; record the assignment as a
        # delivery note so it surfaces in the CRM and audit trail.
        agent = User.objects.filter(pk=data.get("agent_id"), role="agent").first()
        if agent:
            CustomerNote.objects.create(
                customer=customer, author=actor, category="delivery",
                body=f"Delivery agent assigned: {agent.name}",
            )
        return {"deliveryAgent": agent.name if agent else None}

    def _create_ticket(self, customer, data, actor):
        from support.models import SupportTicket

        t = SupportTicket.objects.create(
            user=customer,
            category=data.get("category", "general"),
            subject=data.get("subject", "Opened by admin"),
            priority=data.get("priority", "normal"),
        )
        return {"ticketCode": t.code, "ticketId": str(t.id)}


class CustomerAnalyticsView(APIView):
    """Portfolio-level customer analytics for the CRM dashboard (risk distribution,
    totals) — aggregated live."""

    permission_classes = [IsAdmin]

    def get(self, request):
        from django.db.models import Sum

        from credit.models import CreditAccount

        customers = User.objects.filter(role="customer")
        total = customers.count()
        active = customers.filter(is_active=True).count()
        with_credit = CreditAccount.objects.count()
        outstanding = CreditAccount.objects.aggregate(s=Sum("outstanding"))["s"] or 0
        # Risk distribution (sampled over credit customers).
        dist = {"low": 0, "medium": 0, "high": 0, "critical": 0}
        for acc in CreditAccount.objects.select_related("user")[:500]:
            dist[services.compute_risk(acc.user)["level"]] += 1
        return Response({
            "totalCustomers": total,
            "activeCustomers": active,
            "creditCustomers": with_credit,
            "totalOutstanding": float(outstanding),
            "riskDistribution": dist,
        })
