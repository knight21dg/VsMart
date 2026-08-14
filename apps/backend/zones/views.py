from rest_framework import status as http
from rest_framework import viewsets
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from core.app_errors import AppError, ok
from core.permissions import IsAdmin, IsSuperAdmin
from stores.models import Store

from .models import ExpansionRequest, Zone, ZoneAgent
from .serializers import (
    ExpansionRequestSerializer,
    StoreSerializer,
    ZoneSerializer,
)
from .services import agents_for_zone, emit_zone_event
from .serviceability import serviceability


def _coords(source):
    return source.get("lat"), source.get("lng"), source.get("pincode")


class ServiceabilityCheckView(APIView):
    """Single source of truth for serviceability. Validates a customer point against
    zone polygons and returns the serving zone + store + policy. Auth-optional so it
    can run at app launch before sign-in (spec §SERVICEABILITY RESPONSE)."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        lat, lng, pincode = _coords(request.query_params)
        return Response(serviceability(lat=lat, lng=lng, pincode=pincode))

    def post(self, request):
        lat, lng, pincode = _coords(request.data)
        return Response(serviceability(lat=lat, lng=lng, pincode=pincode))


class ZoneCheckView(APIView):
    """Legacy serviceability endpoint (kept for the app). Now polygon-first via the
    serviceability engine; response is a superset of the old shape."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        lat, lng, pincode = _coords(request.query_params)
        result = serviceability(lat=lat, lng=lng, pincode=pincode)
        # Back-compat aliases used by older app builds.
        result["zone"] = result["zone_name"]
        result["min_order"] = result["minimum_order"]
        return Response(result)


class ExpansionRequestCreateView(APIView):
    """Capture a not-serviceable lead (spec §NOT SERVICEABLE FLOW / EXPANSION REQUEST)."""

    permission_classes = [AllowAny]

    def post(self, request):
        s = ExpansionRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = request.user if request.user.is_authenticated else None
        obj = s.save(user=user)
        return Response(ExpansionRequestSerializer(obj).data, status=201)


# ── Admin / Super-Admin ──────────────────────────────────
class AdminZoneViewSet(viewsets.ModelViewSet):
    """Admin lists/views zones; only superadmin can create/edit/delete (money +
    serviceability lever). Polygon drawing happens client-side; the GeoJSON lands here."""

    queryset = Zone.objects.select_related("store").all()
    serializer_class = ZoneSerializer
    pagination_class = None

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [IsAdmin()]
        return [IsSuperAdmin()]

    def get_queryset(self):
        qs = super().get_queryset()
        store_id = self.request.query_params.get("store")
        if store_id:
            qs = qs.filter(store_id=store_id)
        return qs

    def perform_create(self, serializer):
        zone = serializer.save()
        record_audit(self.request.user, "zone.create", target=zone, after=serializer.data)
        emit_zone_event("zone_created", zone=zone, actor=self.request.user,
                        store_id=zone.store_id)

    def perform_update(self, serializer):
        had_store = serializer.instance.store_id
        zone = serializer.save()
        record_audit(self.request.user, "zone.update", target=zone, after=serializer.data)
        emit_zone_event("zone_updated", zone=zone, actor=self.request.user)
        if zone.store_id and zone.store_id != had_store:
            emit_zone_event("store_assigned", zone=zone, actor=self.request.user,
                            store_id=zone.store_id)

    def destroy(self, request, *args, **kwargs):
        """Delete a zone, or deactivate it if it has already served orders.

        ``Order.zone`` is SET_NULL, so row-deleting a zone that has traded
        silently strips the zone off every historical order — every per-zone
        revenue, density and delivery-time report quietly loses those rows, with
        nothing in the UI hinting it happened. Deactivating takes the zone out of
        serviceability (the engine only resolves ``is_active`` zones) while the
        history stays attributable. A zone that never served an order is really
        deleted. The response says which, because the two outcomes look different
        in the list afterwards.
        """
        from orders.models import Order

        zone = self.get_object()
        order_count = Order.objects.filter(zone=zone).count()
        if order_count:
            zone.is_active = False
            zone.save(update_fields=["is_active", "updated_at"])
            record_audit(request.user, "zone.deactivate", target=zone,
                         after={"code": zone.code,
                                "reason": f"delete requested; {order_count} order(s) preserved"})
            emit_zone_event("zone_updated", zone=zone, actor=request.user)
            return Response(ok(
                "RECORD_DEACTIVATED",
                message=(
                    f"{zone.name} has {order_count} order(s) on record, so it was "
                    f"deactivated instead of deleted. It no longer serves customers."
                ),
                data={"id": str(zone.id), "outcome": "deactivated", "isActive": False},
            ))
        record_audit(request.user, "zone.delete", target=zone,
                     after={"code": zone.code, "name": zone.name})
        # ZoneEvent.zone is SET_NULL, so the row survives the delete but loses
        # its pointer — carry the identity in the payload or the trail is blank.
        emit_zone_event("zone_deleted", zone=zone, actor=request.user,
                        zone_name=zone.name, zone_code=zone.code)
        name, zone_id = zone.name, str(zone.id)
        zone.delete()
        return Response(ok(
            "RECORD_DELETED",
            message=f"{name} zone has been deleted.",
            data={"id": zone_id, "outcome": "deleted"},
        ))


class AdminStoreViewSet(viewsets.ModelViewSet):
    """Super-Admin creates/edits stores; admins can list/view their stores."""

    queryset = Store.objects.all()
    serializer_class = StoreSerializer
    pagination_class = None

    def get_permissions(self):
        if self.action in ("list", "retrieve"):
            return [IsAdmin()]
        return [IsSuperAdmin()]

    def perform_create(self, serializer):
        from django.db import transaction

        with transaction.atomic():
            store = serializer.save()
            # Store-centric model: the store IS its own warehouse. Auto-provision +
            # link the backing warehouse so a new store can hold stock immediately;
            # the operator never manages warehouses directly.
            if store.warehouse_id is None:
                from inventory.models import Warehouse

                wh = Warehouse.objects.create(
                    name=store.name, code=f"WH-{store.code}", is_active=True
                )
                store.warehouse = wh
                store.save(update_fields=["warehouse"])
            self._link_zone(store)
        record_audit(self.request.user, "store.create", target=store, after=serializer.data)

    def perform_update(self, serializer):
        from django.db import transaction

        with transaction.atomic():
            store = serializer.save()
            self._link_zone(store)
        record_audit(self.request.user, "store.update", target=store, after=serializer.data)

    def destroy(self, request, *args, **kwargs):
        """Delete a store, and say which of the two things actually happened.

        A store that has ever traded is **deactivated**, not row-deleted. The
        delete cascades far wider than the confirm dialog implies: it takes the
        store's own products (``catalog.Product.store``), every store-staff login
        (``storeops.StoreStaff``), POS drafts and delivery batches with it, and
        historical orders lose their store attribution (SET_NULL) — silently
        rewriting past reporting.

        Deactivating stops the store serving orders (checkout gates on
        ``status``) while every record it touched stays intact and attributable.
        A store that never traded is really deleted. Either way it is audited —
        create and update were, the deletion was not.

        This returns 200 + a coded message rather than a bare 204 because the
        outcome is *conditional*: a "Store deleted" toast over a store that was
        only deactivated (and is therefore still sitting in the list, greyed
        out) reads as a bug to the operator. Tell them which one they got.
        """
        from orders.models import Order

        store = self.get_object()
        has_history = (
            Order.objects.filter(store=store).exists()
            or store.own_products.exists()
            or store.staff.exists()
        )
        if has_history:
            store.status = Store.Status.INACTIVE
            store.accepting_orders = False
            store.save(update_fields=["status", "accepting_orders", "updated_at"])
            record_audit(self.request.user, "store.deactivate", target=store,
                         after={"code": store.code,
                                "reason": "delete requested; trading history preserved"})
            return Response(ok(
                "RECORD_DEACTIVATED",
                message=(
                    f"{store.name} has orders, products or staff on record, so it was "
                    f"deactivated instead of deleted. It no longer serves customers."
                ),
                data={"id": str(store.id), "outcome": "deactivated",
                      "status": store.status},
            ))
        record_audit(self.request.user, "store.delete", target=store,
                     after={"code": store.code, "name": store.name})
        name = store.name
        store_id = str(store.id)
        store.delete()
        return Response(ok(
            "RECORD_DELETED",
            message=f"{name} has been deleted.",
            data={"id": store_id, "outcome": "deleted"},
        ))

    def _link_zone(self, store):
        """Optionally bind the serving zone to this store (the store-onboarding flow
        asks for the zone). Sets ``Zone.store`` for the selected zone so the zone now
        routes to this store; non-destructive (ignores a missing/blank zone)."""
        zone_id = self.request.data.get("zone")
        if not zone_id:
            return
        try:
            zone = Zone.objects.filter(pk=zone_id).first()
        except (ValueError, TypeError):
            return
        if zone is None or zone.store_id == store.id:
            return
        zone.store = store
        zone.save(update_fields=["store", "updated_at"])
        record_audit(self.request.user, "zone.assign_store", target=zone,
                     after={"store": store.code})
        emit_zone_event("store_assigned", zone=zone, actor=self.request.user,
                        store_id=store.id)


class AdminStoreAdminView(APIView):
    """Super-Admin onboards / lists the **store admin** (manager login) for a store.

    POST creates an email+password login bound to a manager :class:`StoreStaff`
    membership for this store (the store admin can then sign into the Store-Admin
    panel and manage ONLY this store). GET lists the store's admins."""

    def get_permissions(self):
        if self.request.method == "GET":
            return [IsAdmin()]
        return [IsSuperAdmin()]

    def get(self, request, store_id):
        from storeops.staff_service import list_store_admins

        store = get_object_or_404(Store, pk=store_id)
        return Response(list_store_admins(store))

    def post(self, request, store_id):
        from storeops.staff_service import onboard_store_admin, staff_row

        store = get_object_or_404(Store, pk=store_id)
        d = request.data
        membership = onboard_store_admin(
            store, actor=request.user,
            email=d.get("email"), password=d.get("password"),
            name=d.get("name", ""), phone=d.get("phone", ""),
            title=d.get("title", "Store Manager"),
            employee_code=d.get("employeeCode") or d.get("employee_code") or "",
        )
        emit_zone_event("store_admin_onboarded", actor=request.user,
                        store_id=store.id, email=(d.get("email") or "").strip().lower())
        return Response(staff_row(membership), status=http.HTTP_201_CREATED)


class AdminStoreAdminResetView(APIView):
    """Super-Admin resets a store admin's password."""

    permission_classes = [IsSuperAdmin]

    def post(self, request, store_id):
        from storeops.staff_service import reset_store_admin_password, staff_row

        store = get_object_or_404(Store, pk=store_id)
        membership = reset_store_admin_password(
            store, actor=request.user,
            email=request.data.get("email"), password=request.data.get("password"),
        )
        return Response(staff_row(membership))


class AdminExpansionRequestListView(ListAPIView):
    """Super-Admin reviews where customers want VS Mart next (expansion demand)."""

    serializer_class = ExpansionRequestSerializer
    permission_classes = [IsSuperAdmin]
    pagination_class = None
    queryset = ExpansionRequest.objects.all()


class AdminZoneAgentsView(APIView):
    """Store-Admin zone operations: list / assign / unassign delivery agents for a
    zone (spec §STORE ADMIN DASHBOARD — Assign Agents To Zone)."""

    def get_permissions(self):
        return [IsAdmin()]

    def get(self, request, zone_id, agent_id=None):
        """List the zone's agents.

        ``agent_id`` is accepted but unused: the same view serves
        ``…/agents/<agent_id>`` for the unassign DELETE, and an APIView hands a
        GET on that URL to this method with the extra kwarg. Without the
        parameter that raised TypeError — a **500** on a URL that should simply
        answer 405, which is what the contract sweep caught.
        """
        if agent_id is not None:
            return Response(
                {"error": {"code": "method_not_allowed",
                           "message": "Use DELETE to unassign an agent, or GET "
                                      "the zone's agent list without an id.",
                           "fields": {}}},
                status=http.HTTP_405_METHOD_NOT_ALLOWED,
            )
        zone = get_object_or_404(Zone, pk=zone_id)
        agents = agents_for_zone(zone)
        return Response([
            {"id": str(a.id), "name": a.name, "phone": a.phone} for a in agents
        ])

    def post(self, request, zone_id):
        zone = get_object_or_404(Zone, pk=zone_id)
        agent_id = request.data.get("agent_id") or request.data.get("agentId")
        if not agent_id:
            return Response(
                {"error": {"code": "bad_request", "message": "agent_id required", "fields": {}}},
                status=http.HTTP_400_BAD_REQUEST,
            )
        agent = get_object_or_404(User, pk=agent_id, role="agent")
        ZoneAgent.objects.get_or_create(zone=zone, agent=agent)
        emit_zone_event("agent_assigned", zone=zone, actor=request.user,
                        agent_id=str(agent.id))
        return Response({"status": "assigned"}, status=http.HTTP_201_CREATED)

    def delete(self, request, zone_id, agent_id):
        zone = get_object_or_404(Zone, pk=zone_id)
        ZoneAgent.objects.filter(zone=zone, agent_id=agent_id).delete()
        return Response(status=http.HTTP_204_NO_CONTENT)


class AdminStoreInventoryView(APIView):
    """Store-scoped inventory (spec §INVENTORY ARCHITECTURE — Store Inventory):
    per-product current / reserved / available / damaged for the store's warehouse."""

    def get_permissions(self):
        return [IsAdmin()]

    def get(self, request, store_id):
        from inventory.models import StockItem

        store = get_object_or_404(Store, pk=store_id)
        if store.warehouse_id is None:
            return Response([])
        items = (
            StockItem.objects.filter(warehouse_id=store.warehouse_id)
            .select_related("product")
        )
        low_only = request.query_params.get("low") in ("1", "true", "True")
        rows = []
        for it in items:
            available = it.quantity - it.reserved
            if low_only and available > it.low_stock_threshold:
                continue
            rows.append({
                "productId": str(it.product_id),
                "name": it.product.name,
                "brand": it.product.brand,
                "current": it.quantity,
                "reserved": it.reserved,
                "available": available,
                "damaged": it.damaged,
                "lowStockThreshold": it.low_stock_threshold,
                "lowStock": available <= it.low_stock_threshold,
            })
        return Response(rows)


class AdminZoneStatsView(APIView):
    """Per-zone aggregates for the Super-Admin density maps (customers / orders /
    agents per zone) — spec §SUPER ADMIN DASHBOARD map views."""

    def get_permissions(self):
        return [IsAdmin()]

    def get(self, request):
        from orders.models import Order

        rows = []
        for z in Zone.objects.select_related("store").all():
            orders = Order.objects.filter(zone=z)
            rows.append({
                "zoneId": str(z.id),
                "zoneName": z.name,
                "storeName": z.store.name if z.store else None,
                "active": z.is_active,
                "creditEnabled": z.credit_enabled,
                "orders": orders.count(),
                "customers": orders.values("user").distinct().count(),
                "agents": z.agents.count(),
            })
        return Response(rows)
