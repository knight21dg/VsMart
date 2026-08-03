from django.utils import timezone
from rest_framework.generics import ListAPIView
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from core.app_errors import ok

from .models import Coupon, Offer
from .serializers import CouponSerializer, OfferSerializer
from .services import record_banner_events, resolve_coupon, resolve_request_zone_store


def visible_offers_qs(now=None):
    """Offers the public may currently see: ACTIVE/SCHEDULED state, inside the schedule
    window, not soft-deleted. The window check makes auto-publish/auto-expire correct
    even if the housekeeping sweep hasn't flipped `state` yet."""
    from django.db.models import Q

    now = now or timezone.now()
    return (
        Offer.objects.filter(state__in=[Offer.State.ACTIVE, Offer.State.SCHEDULED])
        .filter(Q(valid_from__isnull=True) | Q(valid_from__lte=now))
        .filter(Q(valid_to__isnull=True) | Q(valid_to__gte=now))
        .filter(deleted_at__isnull=True)
    )


class OfferListView(ListAPIView):
    """Public list of active offers — backend does ALL selection; the app never filters.

    Filters: ?type=banner ?placement=top|middle|product_list|product_detail and, for
    product screens, ?category / ?subcategory. Zone/store are resolved SERVER-SIDE from
    the request (lat/lng/pincode or the user's saved address). Specificity order:
    pinned → store-specific → zone-specific → global, then category match, then sort.
    """

    permission_classes = [AllowAny]
    authentication_classes = []  # public; zone/store resolved from lat/lng/pincode params
    pagination_class = None
    serializer_class = OfferSerializer

    def get_queryset(self):
        from django.db.models import Case, IntegerField, Q, When

        params = self.request.query_params
        qs = visible_offers_qs()
        if params.get("type"):
            qs = qs.filter(type=params["type"])

        placement = params.get("placement")
        if placement:
            qs = qs.filter(placement=placement)

        # ── Zone / store targeting (resolved server-side) ──
        # Degrade OPEN: a resolver fault (malformed polygon, DB error) must fall
        # back to global banners, never 500 the public home feed.
        try:
            zone, store = resolve_request_zone_store(self.request)
        except Exception:
            zone, store = None, None
        zid = zone.id if zone is not None else None
        sid = store.id if store is not None else None
        # store-specific OR zone-specific(non-store) OR global(no zone & no store)
        target = Q(zone__isnull=True, store__isnull=True)
        if sid:
            target |= Q(store_id=sid)
        if zid:
            target |= Q(zone_id=zid, store__isnull=True)
        qs = qs.filter(target).annotate(
            _zspec=Case(
                When(store_id=sid or 0, then=0),
                When(zone_id=zid or 0, store__isnull=True, then=1),
                default=2, output_field=IntegerField(),
            )
        )

        # ── Category targeting + fallback (product screens) ──
        category = params.get("category")
        subcategory = params.get("subcategory")
        if placement in ("product_list", "product_detail") and (category or subcategory):
            cond = Q(is_fallback=True, category__isnull=True, subcategory__isnull=True)
            if subcategory:
                cond |= Q(subcategory_id=subcategory)
            if category:
                cond |= Q(category_id=category)
            qs = qs.filter(cond).annotate(
                _cspec=Case(
                    When(subcategory_id=subcategory or 0, then=0),
                    When(category_id=category or 0, then=1),
                    default=2, output_field=IntegerField(),
                )
            ).order_by("-is_pinned", "_zspec", "_cspec", "sort_order")
        else:
            qs = qs.order_by("-is_pinned", "_zspec", "sort_order")

        return self._drop_unavailable_products(qs, store)

    def _drop_unavailable_products(self, qs, store):
        """Hide PRODUCT-action banners whose product isn't carried/in-stock at the
        serving store. Returns a queryset (excludes the unavailable ids) so DRF's filter
        backends keep working. Degrades OPEN: any error → unfiltered (a rare dead-tap
        beats a slow or empty home screen)."""
        try:
            from stores.services import store_visibility_enabled, visible_product_ids

            if store is None or not store_visibility_enabled():
                return qs
            available = visible_product_ids(store)
            if available is None:
                return qs
            drop = []
            for o in qs:
                if o.action != Offer.Action.PRODUCT:
                    continue
                pid = (o.payload or {}).get("product_id") or o.product_id
                if pid is not None and int(pid) not in available:
                    drop.append(o.id)
            return qs.exclude(id__in=drop) if drop else qs
        except Exception:
            return qs


class BannerEventView(APIView):
    """POST /offers/events — batched banner impression/click ingestion from the app.
    Body: {"events": [{"offer_id": 1, "kind": "impression"|"click", "click_id"?: "..."}]}.
    """

    permission_classes = [AllowAny]
    authentication_classes = []

    def post(self, request):
        try:
            zone, store = resolve_request_zone_store(request)
        except Exception:
            zone, store = None, None
        stored = record_banner_events(
            request.data.get("events") or [],
            user=getattr(request, "user", None), store=store, zone=zone,
        )
        return Response(ok("BANNER_EVENTS_RECORDED", data={"stored": stored}))


class CouponWalletView(ListAPIView):
    """Active coupons available to the authenticated user.

    "Available to the user" was not enforced: this returned EVERY active coupon,
    including other customers' PERSONAL loyalty vouchers (``Coupon.owner`` — minted
    by redeeming points), and expired ones. Anyone could read a stranger's private
    code, its value and expiry. ``resolve_coupon`` would still reject them at
    redemption, so it wasn't directly spendable — but it was a straight disclosure
    of someone else's property, and it filled the wallet with codes that could
    never work.
    """

    pagination_class = None
    serializer_class = CouponSerializer

    def get_queryset(self):
        from django.db.models import Q

        if getattr(self, "swagger_fake_view", False):
            return Coupon.objects.none()
        today = timezone.now().date()
        return (
            Coupon.objects.filter(is_active=True)
            # Public campaign codes, plus this user's own personal vouchers.
            .filter(Q(owner__isnull=True) | Q(owner=self.request.user))
            # An expired code in the wallet is just a failed redemption later.
            .filter(Q(valid_to__isnull=True) | Q(valid_to__gte=today))
        )


class CouponValidateView(APIView):
    def post(self, request):
        coupon, discount, message = resolve_coupon(
            request.data.get("code"), request.data.get("cart_total", "0"),
            user=request.user if request.user.is_authenticated else None,
        )
        return Response(
            {
                "valid": coupon is not None,
                "discount": float(discount),
                "message": message,
            }
        )
