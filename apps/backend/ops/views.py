from decimal import Decimal

from django.db.models import Count, F, Q, Sum
from django.utils import timezone
from rest_framework.generics import ListAPIView, get_object_or_404
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import AgentProfile, AuditLog, Role, User
from accounts.serializers import normalize_phone
from accounts.services import record_audit
from catalog.models import Product
from core.pagination import CursorEnvelopePagination
from core.permissions import IsAdmin, IsSuperAdmin
from credit.models import CreditAccount, Statement
from credit.services import ensure_account
from inventory.services import InventoryService
from orders.models import Order, OrderItem
from orders.serializers import OrderListSerializer
from payments.models import Payment

from .models import StockAdjustment


class DashboardView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        today = timezone.now().date()
        todays = Order.objects.filter(placed_at__date=today)
        return Response({
            "orders_today": todays.count(),
            "gmv_today": todays.aggregate(s=Sum("total"))["s"] or Decimal("0"),
            "active_credit_outstanding": CreditAccount.objects.aggregate(
                s=Sum("outstanding"))["s"] or Decimal("0"),
            "overdue_statements": Statement.objects.filter(status="overdue").count(),
            "customers": User.objects.filter(role=Role.CUSTOMER).count(),
            "agents": User.objects.filter(role=Role.AGENT).count(),
        })


class StaffSerializerMixin:
    @staticmethod
    def serialize(u):
        return {"id": str(u.id), "phone": u.phone, "name": u.name,
                "role": u.role, "is_active": u.is_active}


class StaffView(APIView, StaffSerializerMixin):
    permission_classes = [IsSuperAdmin]

    def get(self, request):
        staff = User.objects.filter(role__in=[Role.ADMIN, Role.AGENT, Role.SUPERADMIN])
        return Response([self.serialize(u) for u in staff])

    def post(self, request):
        data = request.data
        role = data.get("role")
        if role not in [Role.ADMIN, Role.AGENT]:
            return Response({"error": {"code": "bad_request",
                                       "message": "role must be admin or agent",
                                       "fields": {}}}, status=400)
        # A missing phone used to raise KeyError → 500. It's a validation
        # problem, so answer like one.
        if not data.get("phone"):
            return Response({"error": {"code": "bad_request",
                                       "message": "phone is required",
                                       "fields": {"phone": "This field is required."}}},
                            status=400)
        phone = normalize_phone(data["phone"])
        if User.objects.filter(phone=phone).exists():
            return Response({"error": {"code": "bad_request",
                                       "message": "That phone number already has an account.",
                                       "fields": {"phone": "Already in use."}}},
                            status=400)
        user = User.objects.create_user(
            phone=phone, name=data.get("name", ""), role=role,
            password=data.get("password"),
        )
        if role == Role.AGENT:
            AgentProfile.objects.create(
                user=user, code=f"AG{1000 + user.id}",
                assigned_pincodes=data.get("assigned_pincodes", []),
            )
        record_audit(request.user, "staff.create", target=user, after={"role": role})
        return Response(self.serialize(user), status=201)


class StaffDetailView(APIView, StaffSerializerMixin):
    permission_classes = [IsSuperAdmin]

    def patch(self, request, pk):
        user = get_object_or_404(User, pk=pk)
        before = self.serialize(user)
        new_role = request.data.get("role")
        deactivating = "is_active" in request.data and not bool(request.data["is_active"])
        demoting = (
            new_role in Role.values
            and new_role != user.role
            and user.role == Role.SUPERADMIN
        )
        # Self-lockout guard: nothing stopped a super-admin deactivating or
        # demoting their own account, which would leave the console with one
        # fewer super-admin — and potentially none at all.
        if user.id == request.user.id and (deactivating or demoting):
            return Response({"error": {
                "code": "bad_request",
                "message": "You can't deactivate or change the role of your own account.",
                "fields": {},
            }}, status=400)
        # Never let the last active super-admin be removed, by anyone.
        if user.role == Role.SUPERADMIN and (deactivating or demoting):
            others = User.objects.filter(
                role=Role.SUPERADMIN, is_active=True).exclude(pk=user.pk).exists()
            if not others:
                return Response({"error": {
                    "code": "bad_request",
                    "message": "This is the last active super-admin — promote another one first.",
                    "fields": {},
                }}, status=400)
        if new_role in Role.values:
            user.role = new_role
        if "is_active" in request.data:
            user.is_active = bool(request.data["is_active"])
        user.save()
        record_audit(request.user, "staff.update", target=user,
                     before=before, after=self.serialize(user))
        return Response(self.serialize(user))


class CustomerListView(ListAPIView):
    permission_classes = [IsAdmin]

    def get_queryset(self):
        return User.objects.filter(role=Role.CUSTOMER)

    def list(self, request, *args, **kwargs):
        page = self.paginate_queryset(self.get_queryset())
        data = [
            {"id": str(u.id), "phone": u.phone, "name": u.name,
             "kyc_status": u.kyc_status, "credit_enabled": u.credit_enabled}
            for u in page
        ]
        return self.get_paginated_response(data)


class CustomerDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        user = get_object_or_404(User, pk=pk, role=Role.CUSTOMER)
        account = getattr(user, "credit_account", None)
        orders = Order.objects.filter(user=user)[:10]
        return Response({
            "id": str(user.id), "phone": user.phone, "name": user.name,
            "email": user.email, "kyc_status": user.kyc_status,
            "credit_enabled": user.credit_enabled,
            "credit": {
                "credit_limit": account.credit_limit if account else 0,
                "outstanding": account.outstanding if account else 0,
                "vs_score": account.vs_score if account else None,
                "status": account.status if account else None,
            },
            "recent_orders": OrderListSerializer(orders, many=True).data,
        })


# ── Analytics ────────────────────────────────────────────
def _period_days(request, default=30):
    try:
        return max(1, min(365, int(request.query_params.get("days", default))))
    except (TypeError, ValueError):
        return default


class AnalyticsOverviewView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        days = _period_days(request)
        since = timezone.now() - timezone.timedelta(days=days)
        orders = Order.objects.filter(placed_at__gte=since).exclude(status="cancelled")
        agg = orders.aggregate(
            gmv=Sum("total"), platform=Sum("platform_fee"),
            delivery=Sum("delivery_fee"), n=Count("id"),
        )
        n = agg["n"] or 0
        gmv = agg["gmv"] or Decimal("0")
        repaid = Payment.objects.filter(
            purpose="repayment", status="success", created_at__gte=since
        ).aggregate(s=Sum("amount"))["s"] or Decimal("0")
        return Response({
            "period_days": days,
            "orders": n,
            "gmv": gmv,
            "revenue": (agg["platform"] or Decimal("0")) + (agg["delivery"] or Decimal("0")),
            "platform_fee_collected": agg["platform"] or Decimal("0"),
            "average_order_value": q_div(gmv, n),
            "new_customers": User.objects.filter(
                role=Role.CUSTOMER, created_at__gte=since).count(),
            "credit_outstanding": CreditAccount.objects.aggregate(
                s=Sum("outstanding"))["s"] or Decimal("0"),
            "overdue_statements": Statement.objects.filter(status="overdue").count(),
            "repayments_collected": repaid,
        })


def q_div(total, n):
    return (total / n).quantize(Decimal("0.01")) if n else Decimal("0.00")


class SalesSeriesView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        days = _period_days(request, default=7)
        today = timezone.now().date()
        series = []
        for i in range(days - 1, -1, -1):
            day = today - timezone.timedelta(days=i)
            d = Order.objects.filter(placed_at__date=day).exclude(status="cancelled").aggregate(
                gmv=Sum("total"), n=Count("id"))
            series.append({"date": day.isoformat(),
                           "orders": d["n"] or 0, "gmv": d["gmv"] or Decimal("0")})
        return Response(series)


class TopProductsView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        rows = (
            OrderItem.objects.exclude(order__status="cancelled")
            .values("name", "product_id")
            .annotate(units=Sum("quantity"),
                      revenue=Sum(F("price") * F("quantity")))
            .order_by("-units")[:10]
        )
        return Response([
            {"product_id": str(r["product_id"]) if r["product_id"] else None,
             "name": r["name"], "units": r["units"], "revenue": r["revenue"]}
            for r in rows
        ])


class ZoneSalesView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        rows = (
            Order.objects.exclude(status="cancelled")
            .values("zone__name")
            .annotate(orders=Count("id"), gmv=Sum("total"))
            .order_by("-gmv")
        )
        return Response([
            {"zone": r["zone__name"] or "Unzoned",
             "orders": r["orders"], "gmv": r["gmv"] or Decimal("0")}
            for r in rows
        ])


# ── Inventory ────────────────────────────────────────────
LOW_STOCK_THRESHOLD = 10


class InventoryView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request):
        qs = Product.objects.all().select_related("category")
        if request.query_params.get("low_stock") in ("1", "true"):
            qs = qs.filter(stock_count__lt=LOW_STOCK_THRESHOLD)
        q = request.query_params.get("q")
        if q:
            qs = qs.filter(name__icontains=q)
        data = [
            {"id": str(p.id), "name": p.name, "brand": p.brand,
             "category": p.category.name, "price": p.price,
             "stock_count": p.stock_count, "in_stock": p.in_stock,
             "low": (p.stock_count or 0) < LOW_STOCK_THRESHOLD}
            for p in qs[:200]
        ]
        return Response(data)


class StockAdjustView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, product_id):
        product = get_object_or_404(Product, pk=product_id)
        data = request.data
        reason = data.get("reason", "")
        before = product.stock_count or 0
        # Route the adjustment through the inventory ledger (the system of record);
        # StockSyncService rewrites Product.stock_count/in_stock from Σ ledger.
        if "set" in data:
            new_count = InventoryService.adjust(
                product, set=int(data["set"]), reason=reason, created_by=request.user
            )
        else:
            new_count = InventoryService.adjust(
                product, delta=int(data.get("delta", 0)), reason=reason,
                created_by=request.user,
            )
        product.refresh_from_db()
        StockAdjustment.objects.create(
            product=product, delta=new_count - before, new_count=new_count,
            reason=reason, by=request.user,
        )
        record_audit(request.user, "inventory.adjust", target=product,
                     after={"delta": new_count - before, "new_count": new_count})
        return Response({"id": str(product.id), "stock_count": product.stock_count,
                         "in_stock": product.in_stock})


# ── Admin credit controls ────────────────────────────────
class AdminCreditView(APIView):
    permission_classes = [IsAdmin]

    def patch(self, request, user_id):
        user = get_object_or_404(User, pk=user_id, role=Role.CUSTOMER)
        account = ensure_account(user)
        before = {"credit_limit": str(account.credit_limit), "status": account.status}
        if "credit_limit" in request.data:
            account.credit_limit = Decimal(str(request.data["credit_limit"]))
        if "status" in request.data and request.data["status"] in CreditAccount.Status.values:
            account.status = request.data["status"]
        account.save(update_fields=["credit_limit", "status", "updated_at"])
        record_audit(request.user, "credit.update", target=account,
                     before=before, after={"credit_limit": str(account.credit_limit),
                                            "status": account.status})
        return Response({"credit_limit": account.credit_limit, "outstanding": account.outstanding,
                         "available": account.available, "status": account.status})


class AdminCreditFreezeView(APIView):
    permission_classes = [IsAdmin]

    def post(self, request, user_id):
        user = get_object_or_404(User, pk=user_id, role=Role.CUSTOMER)
        account = ensure_account(user)
        account.status = (
            CreditAccount.Status.FROZEN
            if account.status != CreditAccount.Status.FROZEN
            else CreditAccount.Status.ACTIVE
        )
        account.save(update_fields=["status", "updated_at"])
        record_audit(request.user, "credit.freeze", target=account,
                     after={"status": account.status})
        return Response({"status": account.status})


# ── Audit log (admin) ────────────────────────────────────
def _audit_row(log):
    return {
        "id": str(log.id),
        "actor": (log.actor.name or log.actor.phone) if log.actor else None,
        "action": log.action,
        "target_type": log.target_type,
        "target_id": log.target_id,
        "before": log.before,
        "after": log.after,
        "created_at": log.created_at,
    }


class AuditLogListView(APIView):
    """Append-only audit trail — PAGINATED (cursor).

    Emits the standard ``{data, meta:{nextCursor, previousCursor}}`` envelope via
    :class:`core.pagination.CursorEnvelopePagination`. It previously returned a
    hard ``[:200]`` slice with no pagination at all, so anything older than the
    most recent 200 entries was simply unreachable — and nothing told the operator
    the trail had been truncated. Cursor (not page-number) pagination matches the
    inventory ledger: the audit log is large and append-heavy, so keyset paging
    stays O(1) on deep pages and never skips or repeats rows as new entries land.
    """

    permission_classes = [IsAdmin]

    def get(self, request):
        qs = AuditLog.objects.select_related("actor")
        action = request.query_params.get("action")
        if action:
            qs = qs.filter(action__icontains=action)
        actor = request.query_params.get("actor")
        if actor:
            # The row renders `actor.name or actor.phone`, so filtering on phone
            # alone meant typing the name you could see returned nothing. Match
            # either identifier.
            qs = qs.filter(
                Q(actor__name__icontains=actor) | Q(actor__phone__icontains=actor)
            )
        paginator = CursorEnvelopePagination()
        page = paginator.paginate_queryset(qs, request, view=self)
        return paginator.get_paginated_response([_audit_row(x) for x in page])


class AuditLogDetailView(APIView):
    permission_classes = [IsAdmin]

    def get(self, request, pk):
        return Response(_audit_row(get_object_or_404(AuditLog, pk=pk)))
