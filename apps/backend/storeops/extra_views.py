"""Store-scoped views for the remaining modules: KYC decision, collections,
returns, and store reports. All store-scoped via membership + permission-gated.
"""
from datetime import timedelta

from django.db.models import Count, F, Sum
from django.utils import timezone
from rest_framework import status as http
from rest_framework.exceptions import ValidationError
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit

from .permissions import StoreScopedMixin
from .views import _store_customer_ids


def _f(v):
    return float(v or 0)


# ── Verification detail + documents ──────────────────────
class StoreVerificationDetailView(StoreScopedMixin, APIView):
    """The full KYC application for review: submitted documents (with
    permission-gated, store-scoped file URLs) and any gov-source verification
    results, so a reviewer sees the evidence before deciding."""

    store_permission = "verification.view"

    def get(self, request, app_id):
        from kyc.models import KycApplication

        app = get_object_or_404(
            KycApplication.objects.select_related("user", "reviewed_by"), pk=app_id
        )
        if app.user_id not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        base = f"/store/verification/{app.id}/documents"
        documents = [
            {
                "id": str(doc.id),
                "type": doc.type,
                "numberMasked": doc.number_masked,
                "status": doc.status,
                # Store-scoped, auth-gated bytes — never a raw MEDIA url.
                "fileUrl": f"{base}/{doc.id}/file" if doc.file else None,
            }
            for doc in app.documents.all().order_by("type")
        ]
        verifications = [
            {
                "kind": v.kind,
                "provider": v.provider,
                "status": v.status,
                "verifiedName": v.verified_name,
                "idMasked": v.id_masked,
                "nameMatch": v.name_match,
                "verifiedAt": v.verified_at,
            }
            for v in app.verifications.all().order_by("kind")
        ]

        # Credit-bureau onboarding summary: what the customer entered vs the CIBIL
        # record, so the reviewer sees the score + name/PAN match before deciding.
        from credit.services import latest_bureau_report

        report = latest_bureau_report(app.user)
        cred_v = (
            app.verifications.filter(raw__has_key="panMatch").order_by("-created_at").first()
        )
        credit = None
        if report is not None or cred_v is not None:
            raw = (cred_v.raw if cred_v else {}) or {}
            credit = {
                "score": report.score if report else raw.get("score", 0),
                "band": report.band if report else raw.get("band", ""),
                "bureauName": report.name_on_bureau if report else raw.get("bureauName", ""),
                "bureauPan": report.pan if report else raw.get("bureauPan", ""),
                "enteredName": raw.get("enteredName", ""),
                "enteredDob": raw.get("enteredDob", ""),
                "enteredPan": raw.get("enteredPan", ""),
                "nameMatch": raw.get("nameMatch"),
                "panMatch": raw.get("panMatch"),
                "checkedAt": report.created_at if report else None,
            }

        # The field-verification task backing THIS application (assign-agent path).
        # Prefer the linked task; fall back to the customer's latest for legacy rows
        # created before the FK existed.
        from verification.models import VerificationTask

        task = (
            app.field_verifications.select_related("agent").order_by("-created_at").first()
            or VerificationTask.objects.filter(
                customer_id=app.user_id,
                status__in=["pending", "assigned", "in_progress", "submitted"],
            )
            .select_related("agent")
            .order_by("-created_at")
            .first()
        )
        assignment = None
        if task is not None:
            evid_base = f"/store/verification/{app.id}/evidence"
            assignment = {
                "taskId": str(task.id),
                "status": task.status,
                "agent": task.agent.name if task.agent_id else None,
                "agentId": str(task.agent_id) if task.agent_id else None,
                # The agent's field RECOMMENDATION + what they captured — the whole
                # point of the loop: the reviewer sees the field findings, then
                # decides. The recommendation is advisory, never the verdict.
                "recommendation": task.recommendation or None,
                "note": task.note or "",
                "submittedAt": task.submitted_at,
                "evidence": [
                    {
                        "kind": e.kind,
                        "photoUrl": f"{evid_base}/{e.id}/file" if e.photo_key else None,
                        "lat": float(e.latitude) if e.latitude is not None else None,
                        "lng": float(e.longitude) if e.longitude is not None else None,
                        "at": e.created_at,
                    }
                    for e in task.evidence.all().order_by("created_at")
                ],
            }

        return Response({
            "id": str(app.id),
            "customerId": str(app.user_id),
            "name": app.user.name or app.user.phone,
            "phone": app.user.phone,
            "status": app.status,
            "submittedAt": app.submitted_at or app.created_at,
            "reviewedBy": app.reviewed_by.name if app.reviewed_by else None,
            "reviewedAt": app.reviewed_at,
            "rejectionReason": app.rejection_reason,
            "documents": documents,
            "verifications": verifications,
            "credit": credit,
            "assignment": assignment,
        })


class StoreVerificationDocumentFileView(StoreScopedMixin, APIView):
    """Stream a KYC document image to store reviewers, gated by store membership +
    ``verification.view`` and confirmation the document's owner is a customer of
    this store. Mirrors kyc.DocumentFileView's protection for the store panel so
    identity docs are never served on an unauthenticated path."""

    store_permission = "verification.view"

    def get(self, request, app_id, doc_id):
        import mimetypes

        from mediastore.serving import serve_storage_key
        from kyc.models import KycDocument

        doc = get_object_or_404(
            KycDocument.objects.select_related("application"),
            pk=doc_id,
            application_id=app_id,
        )
        if doc.application.user_id not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        if not doc.file:
            return Response(
                {"error": {"code": "not_found", "message": "No file for this document.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        content_type = mimetypes.guess_type(doc.file.name)[0] or "application/octet-stream"
        resp = serve_storage_key(doc.file.name, content_type=content_type)
        resp["Cache-Control"] = "private, max-age=60"
        return resp


class StoreVerificationEvidenceFileView(StoreScopedMixin, APIView):
    """Stream a FIELD-verification evidence photo to a store reviewer, gated by store
    membership + confirmation the evidence's customer belongs to this store. The
    platform-wide EvidencePhotoView only authorises admins/the agent/the customer —
    not store staff — so the panel needs this store-scoped path to show the photos
    the reviewer is meant to weigh."""

    store_permission = "verification.view"

    def get(self, request, app_id, evidence_id):
        from mediastore.models import MediaAsset
        from mediastore.serving import serve_storage_key
        from verification.models import VerificationEvidence

        evidence = get_object_or_404(
            VerificationEvidence.objects.select_related("task", "task__kyc_application"),
            pk=evidence_id,
            task__kyc_application_id=app_id,
        )
        if evidence.task.customer_id not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        if not evidence.photo_key:
            return Response(
                {"error": {"code": "not_found", "message": "No photo.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        try:
            asset = MediaAsset.objects.get(pk=evidence.photo_key)
        except Exception:
            return Response(
                {"error": {"code": "not_found", "message": "No photo.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        resp = serve_storage_key(
            asset.variant_key("medium"), content_type=asset.content_type
        )
        resp["Cache-Control"] = "private, max-age=60"
        return resp


# ── Verification decision ────────────────────────────────
class StoreVerificationDecisionView(StoreScopedMixin, APIView):
    store_permission = "verification.manage"

    def post(self, request, app_id):
        from kyc.models import KycApplication
        from kyc.services import approve, reject

        app = get_object_or_404(KycApplication, pk=app_id)
        if app.user_id not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        decision = request.data.get("decision")
        if decision not in ("approve", "reject"):
            raise ValidationError({"decision": ["decision must be 'approve' or 'reject'."]})
        if decision == "approve":
            approve(app, request.user)
        else:
            reject(app, request.user, request.data.get("note", ""))
        record_audit(request.user, "store_kyc.decision", target=app, after={"decision": decision})
        return Response({"id": str(app.id), "status": app.status})


class StoreVerificationAgentsView(StoreScopedMixin, APIView):
    """Field agents this store can assign a document verification to."""

    store_permission = "verification.view"

    def get(self, request):
        from accounts.models import User

        agents = User.objects.filter(role="agent", is_active=True).order_by("name")
        return Response([
            {"id": str(a.id), "name": a.name or a.phone, "phone": a.phone}
            for a in agents
        ])


class StoreVerificationAssignView(StoreScopedMixin, APIView):
    """Assign a field agent to physically verify a customer's documents. Creates a
    VerificationTask the agent app picks up. The store can still approve directly
    (decision endpoint) instead of assigning."""

    store_permission = "verification.manage"

    def post(self, request, app_id):
        from accounts.models import User
        from kyc.models import KycApplication
        from verification.models import VerificationTask

        app = get_object_or_404(KycApplication, pk=app_id)
        if app.user_id not in _store_customer_ids(self.store):
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        # Global CamelCaseJSONParser snake_cases keys: client sends agentId → agent_id.
        agent = get_object_or_404(User, pk=request.data.get("agent_id"), role="agent")
        task = VerificationTask.objects.create(
            customer=app.user, agent=agent, type=VerificationTask.Type.KYC,
            kyc_application=app,  # so the agent's findings flow back to this app
            status=VerificationTask.Status.ASSIGNED,
            note=request.data.get("note", ""),
        )
        record_audit(request.user, "store_kyc.assign_agent", target=app,
                     after={"taskId": str(task.id), "agentId": str(agent.id)})
        return Response({
            "taskId": str(task.id), "status": task.status,
            "agent": agent.name or agent.phone, "agentId": str(agent.id),
        })


# ── Collections ──────────────────────────────────────────
class StoreCollectionsView(StoreScopedMixin, APIView):
    store_permissions = {"read": "collections.view", "write": "collections.manage"}

    def get(self, request):
        from payments.models import CashCollection

        ids = _store_customer_ids(self.store)
        qs = CashCollection.objects.filter(user_id__in=ids).select_related("user", "payment")
        status_f = request.query_params.get("status")
        if status_f == "pending":
            qs = qs.filter(status__in=["requested", "assigned"])
        elif status_f:
            qs = qs.filter(status=status_f)
        return Response([
            {
                "id": str(c.id),
                "customerId": str(c.user_id),
                "customer": (c.user.name or c.user.phone) if c.user else None,
                "phone": c.user.phone if c.user else None,
                "amount": _f(c.amount),
                "collectedAmount": _f(c.collected_amount),
                "status": c.status,
                "agent": c.agent.name if c.agent_id else None,
                "method": c.payment.method if c.payment_id else None,
                "reference": c.payment.gateway_payment_id if c.payment_id else None,
                "createdAt": c.created_at,
                "collectedAt": c.collected_at,
                "isPriority": c.is_priority,
                "escalated": c.escalated,
            }
            for c in qs.order_by("-created_at")[:200]
        ])

    def post(self, request):
        from accounts.models import User
        from payments.models import CashCollection

        from .io_utils import field

        cid = field(request.data, "customerId")
        amount = field(request.data, "amount")
        if not cid or not amount:
            raise ValidationError({"detail": ["customerId and amount are required."]})
        if int(cid) not in _store_customer_ids(self.store):
            raise ValidationError({"customerId": ["Not a customer of this store."]})
        user = get_object_or_404(User, pk=cid)
        c = CashCollection.objects.create(user=user, amount=amount)
        record_audit(request.user, "store_collection.create", target=c, after={"amount": str(amount)})
        from cashcollections.services import auto_assign

        auto_assign(c, by=request.user)
        c.refresh_from_db()
        return Response({"id": str(c.id), "amount": _f(c.amount), "status": c.status},
                        status=http.HTTP_201_CREATED)


class StoreCollectionCollectView(StoreScopedMixin, APIView):
    """A store-recorded collection (customer paid the store directly — cash at
    the counter, a UPI transfer to the store, etc.) — NOT for closing out a
    collection an agent is actively working. This used to let a store user
    force ANY collection to "collected" regardless of state: it overwrote
    `agent` with the STORE STAFF MEMBER who clicked the button (silently
    replacing whoever was actually assigned), skipped the OTP an agent's own
    collect() requires, and could double-collect a debt the agent was mid-way
    through recovering. Now blocked once an agent has actually started
    working it (assigned onward) — record it as a store collection before
    that, or let the agent's own flow finish it after."""

    store_permission = "collections.manage"

    ACTIVE_AGENT_STATES = {"assigned", "accepted", "en_route", "reached"}

    def post(self, request, collection_id):
        from payments.models import CashCollection
        from payments.services import collect_cash

        ids = _store_customer_ids(self.store)
        c = get_object_or_404(CashCollection, pk=collection_id)
        if c.user_id not in ids:
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        if c.agent_id and c.status in self.ACTIVE_AGENT_STATES:
            return Response(
                {"error": {"code": "COLLECTION_IN_PROGRESS", "message": (
                    f"{c.agent.name or c.agent.phone} is actively working this "
                    f"collection ({c.status}). Wait for them to finish it, or "
                    "reassign it first — recording it here now would silently "
                    "take it out from under them."
                ), "fields": {}}},
                status=http.HTTP_409_CONFLICT,
            )
        was_assigned_to = c.agent if c.agent_id else None
        method = (request.data.get("method") or "cash").strip()
        reference = (request.data.get("reference") or "").strip()
        # This money reached the STORE directly (counter cash, UPI/card to the
        # store), so nobody in the field is holding notes for it: `at_store`
        # keeps it out of cash-in-hand entirely. Attributing it to a holder was
        # wrong either way — the staff member who clicked never touched it, and
        # neither did the assigned agent who failed to recover it, yet both
        # variants made the amount surface as cash somebody owed a hand-over
        # for. Only the OUTSTANDING balance is booked, so closing out a
        # collection an agent already partially recovered no longer
        # double-credits the customer.
        collect_cash(c, was_assigned_to, method=method, reference=reference,
                     at_store=True)
        record_audit(
            request.user, "store_collection.collect", target=c,
            after={"amount": str(c.amount), "method": method, "reference": reference},
        )
        # An agent was assigned (just not actively en route/reached, e.g. it
        # had failed back to them) — tell them the store closed it out so
        # they don't keep chasing a debt that's already settled.
        if was_assigned_to is not None:
            from notifications.services import notify

            notify(was_assigned_to, type="collection", title="Collection closed by store",
                  body=f"{c.user.name or c.user.phone}'s collection was recorded by the store — no need to chase it.",
                  data={"collectionId": str(c.id)})
        return Response({"id": str(c.id), "status": c.status, "collectedAt": c.collected_at})


class StoreCollectionReassignView(StoreScopedMixin, APIView):
    """Retry a FAILED (or disputed/requested/assigned) collection by sending
    it to a different agent — the collections page had no assign/retry
    action at all before this; a failed pickup just sat there with no next
    step short of leaving it forever or the customer re-raising it."""

    store_permission = "collections.manage"

    def post(self, request, collection_id):
        from accounts.models import Role, User
        from cashcollections.services import manual_assign
        from payments.models import CashCollection

        from .io_utils import field

        ids = _store_customer_ids(self.store)
        c = get_object_or_404(CashCollection, pk=collection_id)
        if c.user_id not in ids:
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        agent_id = field(request.data, "agentId")
        if not agent_id:
            raise ValidationError({"agentId": ["Pick an agent to retry with."]})
        agent = get_object_or_404(User, pk=agent_id, role=Role.AGENT, is_active=True)
        manual_assign(c, agent, by=request.user, reason="store retry")
        c.refresh_from_db()
        return Response({"id": str(c.id), "status": c.status, "agent": agent.name})


class StoreCollectionDetailView(StoreScopedMixin, APIView):
    """Full timeline + assignment history for one collection — the store
    collections list used to be a flat table with no drill-down at all, so
    "why is this stuck" or "who handled this" had no answer short of a DB
    query. Every timestamp the state machine actually records, plus the
    append-only CollectionAssignmentHistory (auto/manual assign, accept,
    reject, reassign), so a support conversation doesn't need an engineer."""

    store_permission = "collections.view"

    def get(self, request, collection_id):
        from payments.models import CashCollection

        ids = _store_customer_ids(self.store)
        c = get_object_or_404(
            CashCollection.objects.select_related("user", "agent", "payment"),
            pk=collection_id,
        )
        if c.user_id not in ids:
            return Response(
                {"error": {"code": "not_found", "message": "Not a customer of this store.", "fields": {}}},
                status=http.HTTP_404_NOT_FOUND,
            )
        history = [
            {
                "action": h.action,
                "agent": h.agent.name if h.agent_id else None,
                "by": h.by.name if h.by_id else None,
                "reason": h.reason,
                "at": h.created_at,
            }
            for h in c.assignments.select_related("agent", "by").order_by("created_at")
        ]
        return Response({
            "id": str(c.id),
            "customerId": str(c.user_id),
            "customer": (c.user.name or c.user.phone) if c.user else None,
            "phone": c.user.phone if c.user else None,
            "amount": _f(c.amount),
            "collectedAmount": _f(c.collected_amount),
            "status": c.status,
            "agent": c.agent.name if c.agent_id else None,
            "agentPhone": c.agent.phone if c.agent_id else None,
            "method": c.payment.method if c.payment_id else None,
            "reference": c.payment.gateway_payment_id if c.payment_id else None,
            "isPriority": c.is_priority,
            "escalated": c.escalated,
            "attemptNo": c.attempt_no,
            "otpVerified": c.otp_verified,
            "failureReason": c.failure_reason,
            "disputeNote": c.dispute_note,
            "timeline": {
                "createdAt": c.created_at,
                "assignedAt": c.assigned_at,
                "acceptedAt": c.accepted_at,
                "enRouteAt": c.en_route_at,
                "reachedAt": c.reached_at,
                "failedAt": c.failed_at,
                "collectedAt": c.collected_at,
            },
            "assignmentHistory": history,
        })


# ── Returns ──────────────────────────────────────────────
class StoreReturnsView(StoreScopedMixin, APIView):
    store_permissions = {"read": "orders.view", "write": "returns.manage"}

    def get(self, request):
        from returns.models import ReturnRequest

        qs = ReturnRequest.objects.filter(order__store=self.store).select_related(
            "user", "order"
        ).prefetch_related("items")
        status_f = request.query_params.get("status")
        if status_f:
            qs = qs.filter(status=status_f)
        rows = []
        for r in qs.order_by("-created_at")[:200]:
            rows.append({
                "code": r.code,
                "orderCode": r.order.code if r.order else None,
                "customer": (r.user.name or r.user.phone) if r.user else None,
                "phone": r.user.phone if r.user else None,
                "reason": r.reason,
                "status": r.status,
                "refundAmount": _f(r.refund_amount),
                "items": r.items.count(),
                "createdAt": r.created_at,
                "resolvedAt": r.resolved_at,
            })
        return Response(rows)


class StoreReturnDetailView(StoreScopedMixin, APIView):
    store_permission = "orders.view"

    def get(self, request, code):
        from returns.admin_service import return_detail
        from returns.models import ReturnRequest

        ret = get_object_or_404(
            ReturnRequest.objects.select_related("user", "order", "decided_by").prefetch_related("items"),
            code=code,
            order__store=self.store,
        )
        return Response(return_detail(ret))


class StoreReturnStatusView(StoreScopedMixin, APIView):
    store_permission = "returns.manage"

    def post(self, request, code):
        from returns.admin_service import set_return_status
        from returns.models import ReturnRequest

        ret = get_object_or_404(ReturnRequest, code=code, order__store=self.store)
        new_status = request.data.get("status")
        if not new_status:
            raise ValidationError({"status": ["status is required."]})
        note = (request.data.get("note") or "").strip()
        try:
            set_return_status(ret, new_status, by=request.user, note=note)
        except ValueError as e:
            raise ValidationError({"detail": [str(e)]})
        record_audit(
            request.user, "store_return.status", target=ret,
            after={"status": new_status, "note": note},
        )
        return Response({"code": ret.code, "status": ret.status})


# ── Reports ──────────────────────────────────────────────
class StoreReportsView(StoreScopedMixin, APIView):
    store_permission = "reports.view"

    def get(self, request, name):
        from orders.models import Order, OrderItem

        store = self.store
        sellable = Order.objects.filter(store=store).exclude(status__in=["cancelled", "rejected"])
        today = timezone.localdate()

        if name == "sales":
            # Explicit from/to wins; otherwise fall back to a rolling `days` window.
            start, end = self._range(request, today, default_days=30)
            span = (end - start).days + 1
            agg = (
                sellable.filter(placed_at__date__range=(start, end))
                .values("placed_at__date")
                .annotate(revenue=Sum("total"), orders=Count("id"))
            )
            by_day = {r["placed_at__date"]: r for r in agg}
            rows = []
            for i in range(span):
                d = start + timedelta(days=i)
                r = by_day.get(d, {})
                rows.append({"date": d.isoformat(), "revenue": _f(r.get("revenue")), "orders": r.get("orders", 0) or 0})
            totals = sellable.filter(placed_at__date__range=(start, end)).aggregate(rev=Sum("total"), n=Count("id"))
            return Response({
                "title": f"Sales — {start.isoformat()} to {end.isoformat()}",
                "from": start.isoformat(), "to": end.isoformat(),
                "rows": rows,
                "summary": {"revenue": _f(totals["rev"]), "orders": totals["n"] or 0},
            })

        if name == "top-products":
            start, end = self._range(request, today, default_days=30)
            items = (
                OrderItem.objects.filter(order__store=store, order__placed_at__date__range=(start, end))
                .exclude(order__status__in=["cancelled", "rejected"])
                .values("name")
                .annotate(qty=Sum("quantity"), revenue=Sum(F("price") * F("quantity")))
                .order_by("-qty")[:25]
            )
            rows = [
                {"name": r["name"], "qtySold": r["qty"] or 0, "revenue": _f(r["revenue"])}
                for r in items
            ]
            return Response({
                "title": f"Top products — {start.isoformat()} to {end.isoformat()}",
                "from": start.isoformat(), "to": end.isoformat(),
                "rows": rows,
            })

        if name == "inventory":
            from .services import _expiry_rows, _low_stock_rows, stock_value

            wh = store.warehouse_id
            return Response({
                "title": "Inventory valuation",
                "summary": {
                    "stockValue": stock_value(wh) if wh else 0,
                    "lowStockItems": len(_low_stock_rows(wh)) if wh else 0,
                    "expiringItems": len(_expiry_rows(wh)) if wh else 0,
                },
                "lowStock": _low_stock_rows(wh)[:50] if wh else [],
                "expiring": _expiry_rows(wh)[:50] if wh else [],
            })

        if name == "credit":
            from credit.models import CreditAccount

            accs = CreditAccount.objects.filter(user_id__in=_store_customer_ids(store))
            agg = accs.aggregate(out=Sum("outstanding"), lim=Sum("credit_limit"))
            rows = [
                {"name": a.user.name or a.user.phone, "outstanding": _f(a.outstanding),
                 "creditLimit": _f(a.credit_limit), "status": a.status}
                for a in accs.select_related("user").order_by("-outstanding")[:50]
            ]
            return Response({
                "title": "Credit outstanding",
                "summary": {"totalOutstanding": _f(agg["out"]), "totalLimit": _f(agg["lim"]),
                            "accounts": accs.count()},
                "rows": rows,
            })

        return Response(
            {"error": {"code": "not_found", "message": "Unknown report.", "fields": {}}},
            status=http.HTTP_404_NOT_FOUND,
        )

    @staticmethod
    def _range(request, today, *, default_days=30, max_days=366):
        """Resolve the report window. `from`/`to` (YYYY-MM-DD) take precedence;
        otherwise a rolling `days` window ending today. Clamped so a bad/huge
        range can't blow up the row builder."""
        from datetime import date

        def _parse(v):
            try:
                return date.fromisoformat(v) if v else None
            except (TypeError, ValueError):
                return None

        start = _parse(request.query_params.get("from"))
        end = _parse(request.query_params.get("to")) or today
        if start is None:
            try:
                days = int(request.query_params.get("days") or default_days)
            except (TypeError, ValueError):
                days = default_days
            days = max(1, min(days, max_days))
            start = end - timedelta(days=days - 1)
        if start > end:
            start, end = end, start
        if (end - start).days + 1 > max_days:
            start = end - timedelta(days=max_days - 1)
        return start, end


# ── Delivery returns (store receives failed goods back) ──────────────────────
class StoreDeliveryReturnsView(StoreScopedMixin, APIView):
    """Failed/returning deliveries whose goods are coming back to THIS store.

    The agent flips a failed task to return_initiated; nothing existed for the
    store to see those parcels coming or to confirm they physically arrived —
    stock only restored via an admin shortcut."""

    store_permissions = {"read": "delivery.view", "write": "delivery.manage"}

    def get(self, request):
        from delivery.models import DeliveryTask

        rows = (
            DeliveryTask.objects
            .filter(order__store=self.store,
                    status__in=["failed", "return_initiated"])
            .select_related("order", "order__user", "agent")
            .order_by("-updated_at")[:100]
        )
        return Response([
            {
                "taskId": t.id,
                "orderCode": t.order.code,
                "status": t.status,
                "customer": t.order.user.name if t.order.user else "",
                "agent": t.agent.name if t.agent else "",
                "agentPhone": t.agent.phone if t.agent else "",
                "amount": t.order.total,
                "failureReason": t.failure_reason,
                "failedAt": t.failed_at,
            }
            for t in rows
        ])


class StoreDeliveryReturnReceiveView(StoreScopedMixin, APIView):
    """Confirm the goods physically arrived back: restores stock, reverses any
    credit charge, and closes the order — the second half of the handover."""

    store_permission = "delivery.manage"

    def post(self, request, task_id):
        from core.app_errors import ok
        from delivery import services as delivery_services
        from delivery.models import DeliveryTask

        task = get_object_or_404(
            DeliveryTask, pk=task_id, order__store=self.store)
        delivery_services.return_to_store(task, by=request.user)
        record_audit(request.user, "store_return.received", target=task,
                     after={"order": task.order.code})
        return Response(ok("RETURN_TO_STORE", data={"taskId": task.id,
                                                    "status": task.status}))


# ── Overdue credit (dunning) ─────────────────────────────────────────────────
class StoreOverdueCreditView(StoreScopedMixin, APIView):
    """THIS store's customers with unpaid credit statements past their due date —
    the cycle end (close) date, the due date, days overdue, and whether a cash
    collection is already out for them. Statements now generate hourly, so this
    is the store's live dunning book."""

    store_permissions = {"read": "collections.view", "write": "collections.manage"}

    def get(self, request):
        from credit.models import Statement
        from payments.models import CashCollection

        ids = _store_customer_ids(self.store)
        today = timezone.localdate()
        rows = (
            Statement.objects
            .filter(account__user_id__in=ids,
                    status__in=[Statement.Status.OVERDUE,
                                Statement.Status.PARTIALLY_PAID,
                                Statement.Status.OPEN],
                    closing_balance__gt=0)
            .select_related("account", "account__user")
            .order_by("due_date")[:200]
        )
        open_collections = {
            c.user_id: c
            for c in CashCollection.objects.filter(
                user_id__in=[r.account.user_id for r in rows],
                status__in=["requested", "assigned", "accepted",
                            "en_route", "reached"],
            ).select_related("agent")
        }
        out = []
        for st in rows:
            user = st.account.user
            coll = open_collections.get(user.id)
            out.append({
                "statementId": st.id,
                "customerId": str(user.id),
                "customer": user.name or "",
                "phone": user.phone,
                "periodEnd": st.period_end,
                "dueDate": st.due_date,
                "daysOverdue": max((today - st.due_date).days, 0),
                "outstanding": st.closing_balance,
                "status": st.status,
                "collectionStatus": coll.status if coll else "",
                "collectionAgent": (coll.agent.name if coll and coll.agent
                                    else ""),
            })
        return Response(out)


class StoreOverdueAssignView(StoreScopedMixin, APIView):
    """Send an agent after an overdue statement: creates the cash-collection
    task and assigns it — auto (best-ranked agent) or to a named agent."""

    store_permission = "collections.manage"

    def post(self, request):
        from cashcollections import services as coll_services
        from core.app_errors import AppError, ok
        from credit.models import Statement
        from payments.models import CashCollection

        from .views import field

        statement_id = field(request.data, "statementId")
        statement = get_object_or_404(
            Statement.objects.select_related("account", "account__user"),
            pk=statement_id)
        ids = _store_customer_ids(self.store)
        if statement.account.user_id not in ids:
            raise AppError("INSUFFICIENT_PERMISSIONS",
                           message="That customer doesn't belong to this store.")
        user = statement.account.user
        # One live collection per customer — don't stack duplicate door-knocks.
        existing = CashCollection.objects.filter(
            user=user,
            status__in=["requested", "assigned", "accepted",
                        "en_route", "reached"],
        ).first()
        collection = existing or CashCollection.objects.create(
            user=user, amount=statement.closing_balance, statement=statement)

        agent_id = field(request.data, "agentId")
        if agent_id:
            from accounts.models import Role, User

            agent = get_object_or_404(
                User, pk=agent_id, role=Role.AGENT, is_active=True)
            coll_services.manual_assign(collection, agent, by=request.user)
        else:
            assigned = coll_services.auto_assign(collection, by=request.user)
            if not assigned:
                return Response(ok("COLLECTION_ASSIGNED", data={
                    "id": str(collection.id), "status": collection.status,
                    "assigned": False,
                }))
        record_audit(request.user, "store_collection.assign",
                     target=collection,
                     after={"statement": statement.id,
                            "agent": agent_id or "auto"})
        collection.refresh_from_db()
        return Response(ok("COLLECTION_ASSIGNED", data={
            "id": str(collection.id), "status": collection.status,
            "agent": collection.agent.name if collection.agent else "",
            "assigned": collection.agent_id is not None,
        }))
