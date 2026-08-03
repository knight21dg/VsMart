"""Store dispatch console — the assignment queue, the auto/manual assignment
engine trigger, batch board, and agent capacity management. Store-scoped +
permission-gated like the rest of storeops."""
from rest_framework import status as http
from rest_framework.exceptions import ValidationError
from rest_framework.generics import get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import AgentProfile, Role, User
from accounts.services import record_audit
from core.app_errors import AppError, ok
from delivery import assignment_engine as engine
from delivery.models import DeliveryBatch

from .io_utils import field
from .permissions import StoreScopedMixin


def _f(v):
    return float(v or 0)


def _agent_row(user):
    p = getattr(user, "agent_profile", None)
    lat, lng = engine._agent_last_location(user)
    return {
        "id": str(user.id),
        "name": user.name or user.phone,
        "phone": user.phone,
        # `isActive` is the agent's LOGIN: deactivating revokes app access, which is
        # different from `available` (on shift / off shift).
        "isActive": bool(user.is_active),
        "available": bool(p.is_available) if p else False,
        "vehicle": p.vehicle_type if p else "",
        "bagCapacity": p.bag_capacity if p else 0,
        "weightCapacityKg": p.weight_capacity_kg if p else 0,
        "cashCapacity": _f(p.cash_capacity) if p else 0,
        "maxStops": p.max_stops if p else 0,
        "rating": _f(p.rating) if p else 0,
        "employmentType": p.employment_type if p else AgentProfile.EmploymentType.MONTHLY,
        "activeLoad": engine._agent_active_load(user),
        "lat": _f(lat) if lat is not None else None,
        "lng": _f(lng) if lng is not None else None,
    }


def _batch_row(b):
    stops = b.stops.all()
    return {
        "id": b.id,
        "status": b.status,
        "priority": b.priority,
        "agent": b.agent.name if b.agent else None,
        "agentId": str(b.agent_id) if b.agent_id else None,
        "stops": len(stops),
        "deliveries": sum(1 for s in stops if s.kind == "delivery"),
        "collections": sum(1 for s in stops if s.kind == "collection"),
        "distanceKm": _f(b.total_distance_km),
        "etaMinutes": round((b.estimated_duration_secs or 0) / 60),
        "score": _f(b.score) if b.score is not None else None,
        "pickupCode": b.pickup_code,
        "createdAt": b.created_at,
    }


class StoreDispatchQueueView(StoreScopedMixin, APIView):
    """The assignment queue: orders ready for a rider, pending collections,
    available agents, and headline KPIs for the dispatch dashboard."""

    store_permission = "delivery.view"

    def get(self, request):
        store = self.store
        orders = engine._ready_orders(store)
        collections = engine._pending_collections(store)
        agents = engine._available_agents(store)
        active_batches = DeliveryBatch.objects.filter(
            store=store, status__in=["queued", "assigned", "accepted", "picked_up", "in_progress"]
        )
        queue = [
            {
                "code": o.code,
                "customer": (o.user.name or o.user.phone) if o.user else None,
                "items": o.items.count(),
                "value": _f(o.total),
                "paymentMethod": o.payment_method,
                "priority": engine._order_priority(o),
            }
            for o in orders
        ]
        return Response({
            "queue": queue,
            "collections": [
                {"id": str(c.id), "customer": (c.user.name or c.user.phone) if c.user else None,
                 "amount": _f(c.amount)}
                for c in collections
            ],
            "agents": [_agent_row(a) for a in agents],
            "kpis": {
                "readyOrders": len(orders),
                "availableAgents": len(agents),
                "pendingCollections": len(collections),
                "collectionsValue": _f(sum((c.amount or 0) for c in collections)),
                "activeBatches": active_batches.count(),
            },
        })


class StoreDispatchAutoAssignView(StoreScopedMixin, APIView):
    """Run the assignment engine: cluster + route + score + dispatch batches."""

    store_permission = "delivery.manage"

    def post(self, request):
        summary = engine.run_auto_assign(self.store, by=request.user)
        record_audit(request.user, "store_dispatch.auto_assign", after=summary)
        return Response(summary)


class StoreDispatchManualView(StoreScopedMixin, APIView):
    """Store hand-builds a batch: pick orders (+ collections) for one agent."""

    store_permission = "delivery.manage"

    def post(self, request):
        order_codes = field(request.data, "orderCodes") or []
        agent_id = field(request.data, "agentId")
        collection_ids = field(request.data, "collectionIds") or []
        if not order_codes or not agent_id:
            raise ValidationError({"detail": ["orderCodes and agentId are required."]})
        agent = get_object_or_404(User, pk=agent_id, role=Role.AGENT)
        try:
            batch = engine.create_manual_batch(
                self.store, order_codes, agent,
                collection_ids=collection_ids, by=request.user,
            )
        except ValueError as e:
            raise ValidationError({"detail": [str(e)]})
        record_audit(request.user, "store_dispatch.manual_batch", target=batch,
                     after={"orders": order_codes, "agent": str(agent_id)})
        return Response(_batch_row(batch), status=http.HTTP_201_CREATED)


class StoreBatchListView(StoreScopedMixin, APIView):
    store_permission = "delivery.view"

    def get(self, request):
        qs = DeliveryBatch.objects.filter(store=self.store).select_related("agent").prefetch_related("stops")
        status_f = request.query_params.get("status")
        if status_f == "active":
            qs = qs.exclude(status__in=list(DeliveryBatch.TERMINAL))
        elif status_f:
            qs = qs.filter(status=status_f)
        return Response([_batch_row(b) for b in qs.order_by("-created_at")[:100]])


class StoreBatchDetailView(StoreScopedMixin, APIView):
    store_permission = "delivery.view"

    def get(self, request, batch_id):
        b = get_object_or_404(
            DeliveryBatch.objects.select_related("agent").prefetch_related("stops__task__order"),
            pk=batch_id, store=self.store,
        )
        stops = []
        for s in b.stops.all().order_by("sequence"):
            order = s.task.order if s.task_id and s.task else None
            stops.append({
                "sequence": s.sequence,
                "kind": s.kind,
                "label": s.label,
                "status": s.status,
                "orderCode": order.code if order else None,
                "amount": _f(s.amount),
                "lat": _f(s.latitude) if s.latitude is not None else None,
                "lng": _f(s.longitude) if s.longitude is not None else None,
            })
        return Response({
            **_batch_row(b),
            "encodedPolyline": b.encoded_polyline,
            "stopList": stops,
        })


class StoreBatchCancelView(StoreScopedMixin, APIView):
    store_permission = "delivery.manage"

    def post(self, request, batch_id):
        b = get_object_or_404(DeliveryBatch, pk=batch_id, store=self.store)
        if b.is_terminal:
            raise ValidationError({"detail": ["Batch already closed."]})
        engine.release_batch(b, reason="store_cancelled", by=request.user)
        record_audit(request.user, "store_dispatch.cancel_batch", target=b)
        return Response({"id": b.id, "status": "cancelled"})


class StoreBatchReassignView(StoreScopedMixin, APIView):
    """Pull a batch off its agent (offline / breakdown) and re-plan its unfinished
    stops onto other available agents."""

    store_permission = "delivery.manage"

    def post(self, request, batch_id):
        b = get_object_or_404(DeliveryBatch, pk=batch_id, store=self.store)
        if b.is_terminal:
            raise ValidationError({"detail": ["Batch already closed."]})
        prev_agent = b.agent_id
        summary = engine.reassign_batch(
            b, reason="store_reassign", by=request.user,
            exclude_agent_ids=[prev_agent] if prev_agent else None,
        )
        record_audit(request.user, "store_dispatch.reassign_batch", target=b, after=summary)
        return Response(summary)


# ── Agent management (onboarding + capacity) ─────────────────
class StoreAgentsLiveView(StoreScopedMixin, APIView):
    """Live-duty board for THIS store's roster — position, on-duty, active load.
    The store equivalent of the admin's platform-wide Live Operations."""

    store_permission = "delivery.view"

    def get(self, request):
        from agents.services import store_live_operations

        return Response(store_live_operations(self.store))


class StoreAgentsCashView(StoreScopedMixin, APIView):
    """GET /store/agents/cash — how much cash THIS store's own agents have
    collected, how much each is still holding, and their hand-over history.

    Counting a hand-over is now also a store action (see
    ``StoreAgentsCashActionView`` below) — a store manager is usually the one
    physically receiving the cash, so routing every count through the
    platform-wide Cash Book (apps/admin) added a needless hop. This view
    stays read-only; it just gives the store visibility into its own agents'
    cash. Scoped by ``AgentProfile.store`` (agents are store-owned), so a
    store only ever sees its own riders' cash, never another store's.
    """

    store_permission = "delivery.view"

    def get(self, request):
        from payments.cashbook_services import reconciliation
        from payments.cashbook_views import CashDepositSerializer
        from payments.models import CashDeposit

        p = request.query_params
        summary = reconciliation(
            date_from=p.get("from") or None,
            date_to=p.get("to") or None,
            store=self.store,
        )
        deposits = (
            CashDeposit.objects.filter(store=self.store)
            .select_related("agent", "verified_by")
            .order_by("-created_at")[:100]
        )
        return Response({
            "summary": summary,
            "deposits": CashDepositSerializer(deposits, many=True).data,
        })


class StoreAgentsCashActionView(StoreScopedMixin, APIView):
    """POST /store/agents/cash/deposits/<id>/<action> — verify | reject a
    PENDING hand-over from one of this store's own agents.

    Calls the exact same finance service (and audit trail via
    ``record_audit``) as the platform-wide Cash Book — nothing about the
    verification logic is duplicated, only who's allowed to trigger it.
    Scoped to the deposit's own store: another store's deposit 404s rather
    than leaking that it exists.
    """

    store_permission = "delivery.manage"

    def post(self, request, deposit_id, action):
        from payments.cashbook_services import reject_deposit, verify_deposit
        from payments.cashbook_views import CashDepositSerializer
        from payments.models import CashDeposit

        deposit = get_object_or_404(CashDeposit, pk=deposit_id, store=self.store)
        if action == "verify":
            deposit = verify_deposit(
                deposit, request.user,
                counted_amount=field(request.data, "countedAmount"),
                notes=field(request.data, "notes") or "",
            )
        elif action == "reject":
            deposit = reject_deposit(
                deposit, request.user, reason=field(request.data, "reason") or "",
            )
        else:
            raise AppError("VALIDATION_ERROR",
                           message="action must be 'verify' or 'reject'.")
        return Response(ok("OK", data=CashDepositSerializer(deposit).data))


def _apply_profile_fields(profile, data):
    """Apply capacity/vehicle/availability fields to an AgentProfile. Shared by
    create and update so both accept the same inputs with the same validation —
    add-agent used to take ONLY phone+name, so every new rider silently landed on
    default capacities until someone reopened Edit. Bad input is REJECTED, not
    swallowed. Returns the list of changed attrs (unsaved)."""
    changed = []
    for key, attr, kind in [
        ("vehicle", "vehicle_type", "vehicle"),
        ("bagCapacity", "bag_capacity", "count"),
        ("weightCapacityKg", "weight_capacity_kg", "count"),
        ("cashCapacity", "cash_capacity", "money"),
        ("maxStops", "max_stops", "count"),
        ("available", "is_available", "bool"),
        ("employmentType", "employment_type", "employment_type"),
    ]:
        val = field(data, key)
        if val is None:
            continue
        if kind == "vehicle":
            choices = [c[0] for c in AgentProfile.Vehicle.choices]
            if val not in choices:
                raise ValidationError({key: [f"Choose one of: {', '.join(choices)}."]})
            setattr(profile, attr, val)
        elif kind == "employment_type":
            choices = [c[0] for c in AgentProfile.EmploymentType.choices]
            if val not in choices:
                raise ValidationError({key: [f"Choose one of: {', '.join(choices)}."]})
            setattr(profile, attr, val)
        elif kind == "bool":
            setattr(profile, attr, bool(val))
        else:
            try:
                num = float(val) if kind == "money" else int(val)
            except (TypeError, ValueError):
                raise ValidationError({key: ["Enter a number."]})
            if num < 0:
                raise ValidationError({key: ["Cannot be negative."]})
            setattr(profile, attr, num)
        changed.append(attr)
    return changed


class StoreAgentsView(StoreScopedMixin, APIView):
    store_permissions = {"read": "delivery.view", "write": "delivery.manage"}

    def get(self, request):
        # Agents are STORE-OWNED: a store sees only the riders it hired. This was
        # previously unfiltered, so every store saw the whole platform roster.
        profiles = AgentProfile.objects.select_related("user").filter(
            store=self.store
        )
        rows = [_agent_row(p.user) for p in profiles if p.user.role == Role.AGENT]
        return Response(rows)

    def post(self, request):
        """Onboard a field agent → provisions the phone login the agent app signs
        in with (phone + OTP, gated to registered agents). The agent belongs to
        THIS store."""
        from accounts.serializers import normalize_phone

        phone = normalize_phone(str(field(request.data, "phone") or ""))
        name = str(field(request.data, "name") or "").strip()
        if len(phone.lstrip("+")) < 12:  # 91 + 10 digits
            raise ValidationError(
                {"phone": ["Enter a valid 10-digit mobile number."]})
        existing = User.objects.filter(phone=phone).first()
        if existing is not None and existing.role != Role.AGENT:
            raise ValidationError(
                {"phone": ["This number already belongs to another account."]})
        if existing is not None:
            profile, _ = AgentProfile.objects.get_or_create(
                user=existing, defaults={"code": f"AG{existing.id}", "store": self.store})
            # Don't silently poach another store's agent.
            if profile.store_id and profile.store_id != self.store.id:
                raise ValidationError(
                    {"phone": ["This agent already belongs to another store."]})
            if profile.store_id is None:  # adopt a legacy/unassigned agent
                profile.store = self.store
                profile.save(update_fields=["store"])
            if not existing.is_active:
                existing.is_active = True
                existing.save(update_fields=["is_active"])
            return Response(_agent_row(existing))
        user = User.objects.create(
            phone=phone, name=name, role=Role.AGENT, is_active=True)
        profile = AgentProfile.objects.create(
            user=user, code=f"AG{user.id}", store=self.store)
        # Capacity/vehicle straight from the add form (same contract as PATCH).
        changed = _apply_profile_fields(profile, request.data)
        if changed:
            profile.save(update_fields=changed)
        record_audit(request.user, "store_agent.create", target=user,
                     after={"phone": phone, "name": name, "store": self.store.code,
                            "fields": changed})
        return Response(_agent_row(user), status=http.HTTP_201_CREATED)


class StoreAgentUpdateView(StoreScopedMixin, APIView):
    store_permission = "delivery.manage"

    def patch(self, request, agent_id):
        agent = get_object_or_404(User, pk=agent_id, role=Role.AGENT)
        # Scoped: without this a store could edit another store's agent by id.
        p = get_object_or_404(
            AgentProfile, user=agent, store=self.store
        )
        changed = _apply_profile_fields(p, request.data)
        if changed:
            p.save(update_fields=changed)

        # Activating/deactivating the agent's LOGIN lives on the user, not the profile.
        active = field(request.data, "isActive")
        if active is not None and bool(active) != agent.is_active:
            agent.is_active = bool(active)
            agent.save(update_fields=["is_active"])
            changed.append("is_active")

        if changed:
            record_audit(request.user, "store_agent.update", target=p, after={"fields": changed})
        return Response(_agent_row(agent))
