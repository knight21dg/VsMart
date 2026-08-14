import re
import uuid

from django.db.models import Q
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from core.pricing import gst_fraction_to_pct

from .models import Feedback, FeatureFlag


def _maintenance_enabled():
    """True if a FeatureFlag with key="maintenance" exists and is enabled."""
    return FeatureFlag.objects.filter(key="maintenance", enabled=True).exists()


def _feature_flags():
    """Flag key -> enabled.

    The keys here are DATA (``zone_store_visibility``), and the response is
    rendered by ``EnvelopeJSONRenderer``, which camelCases every key it sees — so
    the wire name has always been ``zoneStoreVisibility`` while this code
    appeared to emit the snake one. A client looking a flag up by its real key
    silently read "off". Nothing looks one up by name yet, so it is a trap rather
    than a live fault.

    Emitting the camel name explicitly keeps the wire byte-identical to what
    ships today (no client change) while making the code say what it sends. Look
    a flag up by its camel name: ``flags["zoneStoreVisibility"]``.
    """
    return {_camel(f.key): f.enabled for f in FeatureFlag.objects.all()}


def _camel(key):
    head, *rest = key.split("_")
    return head + "".join(part.title() for part in rest)


class VersionView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        return Response({"version": "1.0.0", "api": "v1", "build": "1"})


class ResponseCodesView(APIView):
    """The machine-readable response catalog. Lets any client (app / store-admin /
    super-admin) sync the full code → {title, message, action, severity, …} map so
    it can localise copy and pre-wire toast/dialog/navigation behaviour. Public."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        from core.response_codes import CATALOG

        module = request.query_params.get("module")
        codes = {
            code: {
                "code": code,
                "title": spec["title"],
                "message": spec["message"],
                "action": spec["action"],
                "retryable": spec["retryable"],
                "severity": spec["severity"],
                "next_step": spec["next_step"],
                "http": spec["http"],
                "success": spec["success"],
                "module": spec["module"],
            }
            for code, spec in CATALOG.items()
            if not module or spec["module"] == module
        }
        return Response({"count": len(codes), "codes": codes})


class AppConfigView(APIView):
    """Client bootstrap config — public so the app can read it pre-login."""

    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        from siteconfig.models import PlatformConfig

        cfg = PlatformConfig.load()
        return Response(
            {
                "currency": cfg.currency,
                # A PERCENTAGE (18), consistent with every other API surface.
                # See core.pricing for the single conversion rule.
                "gst_rate": gst_fraction_to_pct(cfg.gst_rate),
                "delivery_fee": cfg.delivery_fee,
                "free_delivery_threshold": cfg.free_delivery_threshold,
                "support_phone": cfg.support_phone,
                "support_email": cfg.support_email,
                "min_app_version": "1.0.0",
                "maintenance": _maintenance_enabled(),
                "feature_flags": _feature_flags(),
            }
        )


class MaintenanceStatusView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        maintenance = _maintenance_enabled()
        return Response(
            {
                "maintenance": maintenance,
                "message": "We'll be back shortly." if maintenance else "",
            }
        )


class FeatureFlagsView(APIView):
    def get(self, request):
        return Response(_feature_flags())


class UploadView(APIView):
    parser_classes = [MultiPartParser, FormParser]

    def post(self, request):
        upload = request.FILES.get("file")
        if upload is None:
            return Response(
                {"error": {"code": "no_file", "message": "file is required",
                           "fields": {}}},
                status=400,
            )
        # NOTE: real S3/MinIO upload wires in here later — for now we only mint a
        # storage key/url and skip persisting the bytes.
        key = f"uploads/{uuid.uuid4().hex}_{upload.name}"
        return Response({"key": key, "url": f"/media/{key}"})


# ── Global search ────────────────────────────────────────────────────────────
# Per-entity result cap. The dropdown shows a handful of rows per type; anything
# beyond that belongs in the module's own filtered list page.
SEARCH_TYPE_LIMIT = 5
# Below this the query is too broad to be worth a cross-entity scan.
SEARCH_MIN_LEN = 2


def _money(value):
    """₹ amount without decimals — enough to identify a row in a dropdown."""
    return f"₹{value:,.0f}"


def _search_orders(q, digits):
    """Orders by code. Matches a full code (VSORD100029), a prefix, or the bare
    numeric tail, so pasting a code from a ticket lands on the order."""
    from orders.models import Order

    # An order code always carries digits; skip the scan for pure-text queries
    # unless the operator is clearly typing the code prefix.
    if not digits and q[:2].lower() != "vs":
        return []
    rows = (
        Order.objects.filter(code__icontains=q)
        .select_related("user")
        .only("code", "status", "total", "user__name", "user__phone")
        .order_by("-placed_at")[:SEARCH_TYPE_LIMIT]
    )
    return [
        {
            "type": "order",
            "id": o.code,
            "label": o.code,
            "sublabel": " · ".join(
                [o.get_status_display(), _money(o.total), o.user.name or o.user.phone]
            ),
            "href": f"/orders/{o.code}",
        }
        for o in rows
    ]


def _search_customers(q, digits):
    """Customers by name, and by phone once enough digits are typed to be a
    plausible number (a 1–3 digit `icontains` would match nearly everyone)."""
    from accounts.models import Role, User

    conds = Q()
    if not q.isdigit():
        conds |= Q(name__icontains=q)
    if len(digits) >= 4:
        conds |= Q(phone__icontains=digits)
    if not conds:
        return []
    rows = (
        User.objects.filter(conds, role=Role.CUSTOMER)
        .only("id", "name", "phone", "credit_enabled")[:SEARCH_TYPE_LIMIT]
    )
    return [
        {
            "type": "customer",
            "id": str(u.id),
            "label": u.name or u.phone,
            "sublabel": " · ".join(
                [u.phone, "Credit on" if u.credit_enabled else "No credit"]
            ),
            "href": f"/customers/{u.id}",
        }
        for u in rows
    ]


def _search_products(q):
    from catalog.models import Product

    rows = (
        Product.objects.filter(Q(name__icontains=q) | Q(sku__icontains=q))
        .only("id", "name", "price", "sku", "is_active")
        .order_by("-is_active", "name")[:SEARCH_TYPE_LIMIT]
    )
    return [
        {
            "type": "product",
            "id": str(p.id),
            "label": p.name,
            "sublabel": " · ".join(
                [_money(p.price)] + ([p.sku] if p.sku else [])
                + ([] if p.is_active else ["Inactive"])
            ),
            "href": f"/inventory/product/{p.id}",
        }
        for p in rows
    ]


def _search_stores(q):
    from stores.models import Store

    rows = (
        Store.objects.filter(Q(name__icontains=q) | Q(code__icontains=q))
        .only("id", "name", "code", "status")[:SEARCH_TYPE_LIMIT]
    )
    return [
        {
            "type": "store",
            "id": str(s.id),
            "label": s.name,
            "sublabel": " · ".join([s.code, s.get_status_display()]),
            "href": f"/stores/{s.id}/edit",
        }
        for s in rows
    ]


class GlobalSearchView(APIView):
    """Global search.

    Every authenticated caller can search the product catalog (`products`, the
    original shape). Admin/superadmin additionally get `results` — a flat,
    already-navigable list of {type, id, label, sublabel, href} spanning orders,
    customers, products and stores, which powers the admin console's topbar
    search. Non-admins never see the cross-entity rows: order codes, customer
    phone numbers and store records are not customer-visible data.
    """

    def get(self, request):
        from catalog.models import Product

        q = (request.query_params.get("q") or "").strip()
        user = request.user
        is_admin = bool(
            user
            and user.is_authenticated
            and getattr(user, "role", None) in ("admin", "superadmin")
        )

        results = []
        if is_admin and len(q) >= SEARCH_MIN_LEN:
            digits = re.sub(r"\D", "", q)
            results = (
                _search_orders(q, digits)
                + _search_customers(q, digits)
                + _search_products(q)
                + _search_stores(q)
            )

        products = []
        if q:
            products = [
                {
                    "id": str(p.id),
                    "name": p.name,
                    "price": p.price,
                    "image_url": p.image_url,
                }
                for p in Product.objects.filter(is_active=True, name__icontains=q)[:10]
            ]

        return Response({"results": results, "count": len(results), "products": products})


class FeedbackView(APIView):
    def post(self, request):
        Feedback.objects.create(
            user=request.user,
            message=request.data.get("message"),
            rating=request.data.get("rating"),
        )
        return Response({"status": "received"})
