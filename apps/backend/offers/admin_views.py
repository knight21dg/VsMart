"""Marketing admin (spec §MODULE 18): banners/deals/coupons CRUD + notification
campaigns to customer segments."""
import json
import re

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import serializers
from rest_framework.generics import ListCreateAPIView, RetrieveUpdateDestroyAPIView
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.models import User
from accounts.services import record_audit
from catalog.models import Category, Product
from core.app_errors import AppError, ok
from core.permissions import IsAdmin
from stores.models import Store
from zones.models import Zone

from .imaging import image_urls, normalize_crop_rect, process_banner_image
from .models import Coupon, Offer
from .specs import public_spec_for, public_specs
from .validators import validate_action_payload


class AdminOfferSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all(),
        required=False, allow_null=True,
    )
    category_id = serializers.PrimaryKeyRelatedField(
        source="category", queryset=Category.objects.all(),
        required=False, allow_null=True,
    )
    subcategory_id = serializers.PrimaryKeyRelatedField(
        source="subcategory", queryset=Category.objects.all(),
        required=False, allow_null=True,
    )
    zone_id = serializers.PrimaryKeyRelatedField(
        source="zone", queryset=Zone.objects.all(), required=False, allow_null=True,
    )
    store_id = serializers.PrimaryKeyRelatedField(
        source="store", queryset=Store.objects.all(), required=False, allow_null=True,
    )
    image = serializers.SerializerMethodField()
    ctr = serializers.SerializerMethodField()
    created_by = serializers.CharField(source="created_by_id", read_only=True)
    approved_by = serializers.CharField(source="approved_by_id", read_only=True)

    class Meta:
        model = Offer
        fields = [
            "id", "type", "placement", "title", "subtitle", "code", "image_url",
            "badge", "discount_percent", "deal_price", "original_price", "product_id",
            "category_id", "subcategory_id", "is_fallback",
            "valid_from", "valid_to", "is_active", "sort_order",
            # v1.0
            "state", "is_pinned", "zone_id", "store_id",
            "title_te", "title_hi", "subtitle_te", "subtitle_hi",
            "action", "payload", "audience", "focus_x", "focus_y", "timezone",
            "cta_text", "cta_text_te", "cta_text_hi",
            "text_theme", "text_position", "accent_color", "crop_rect",
            "image", "image_version", "ctr",
            "impressions", "clicks", "orders", "revenue",
            "created_by", "approved_by", "approved_at", "rejection_reason",
        ]
        read_only_fields = [
            # `state` is workflow-driven only (via BannerStateView) so the CRUD PATCH
            # can't bypass the submit->approve gate; approval/counters are read-only too.
            "state", "image_version", "impressions", "clicks", "orders", "revenue",
            "approved_at", "rejection_reason", "crop_rect",
        ]

    def validate_accent_color(self, value):
        value = (value or "").strip()
        if not value:
            return ""
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise serializers.ValidationError("Use a #RRGGBB hex colour.")
        return value.lower()

    def validate(self, attrs):
        """Enforce the deep-link contract and the schedule window.

        ``action``/``payload`` are validated together because either one can be
        absent from a PATCH — fall back to the instance's current value so a
        partial update can't leave the pair inconsistent.
        """
        inst = self.instance
        action = attrs.get("action", getattr(inst, "action", Offer.Action.NONE))
        payload = attrs.get("payload", getattr(inst, "payload", {}) or {})
        attrs["payload"] = validate_action_payload(action, payload)

        vf = attrs.get("valid_from", getattr(inst, "valid_from", None))
        vt = attrs.get("valid_to", getattr(inst, "valid_to", None))
        if vf and vt and vt <= vf:
            raise serializers.ValidationError(
                {"valid_to": "The end of the schedule must be after its start."}
            )
        return attrs

    def get_image(self, obj):
        return image_urls(obj.image_uuid, obj.image_version)

    def get_ctr(self, obj):
        return round(obj.clicks / obj.impressions, 4) if obj.impressions else 0.0


class AdminCouponSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    redemptions = serializers.SerializerMethodField()

    class Meta:
        model = Coupon
        fields = [
            "id", "code", "discount_type", "value", "min_order", "max_discount",
            "usage_limit", "per_user_limit", "valid_to", "is_active", "redemptions",
        ]

    def get_redemptions(self, obj):
        return obj.redemptions.count()


def _reconcile_state(view, offer):
    """Keep the v1.0 `state` machine and the legacy `is_active` flag consistent.

    - New admin UI sends `state` → honour it, sync `is_active`.
    - Legacy UI sends only `is_active` → drive `state` from the toggle.
    The public feed selects on `state`, so this keeps both UIs publishing correctly.
    """
    data = view.request.data
    if "state" not in data and "is_active" in data:
        offer.state = Offer.State.ACTIVE if offer.is_active else Offer.State.DRAFT
    offer.is_active = offer.state in (Offer.State.ACTIVE, Offer.State.SCHEDULED)
    offer.save(update_fields=["state", "is_active"])


class AdminOfferListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = AdminOfferSerializer

    def get_queryset(self):
        qs = Offer.objects.all()
        t = self.request.query_params.get("type")
        if t:
            qs = qs.filter(type=t)
        # Archived banners are soft-deleted: keep them out of the grid unless
        # explicitly asked for. Without this, archiving looked like a no-op —
        # the row stayed on screen, so "delete" appeared broken.
        if self.request.query_params.get("includeArchived") not in ("1", "true"):
            qs = qs.exclude(state=Offer.State.ARCHIVED)
        return qs

    def perform_create(self, serializer):
        offer = serializer.save(created_by=self.request.user)
        _reconcile_state(self, offer)
        record_audit(self.request.user, "offer.create", target=offer, after={"title": offer.title})


class AdminOfferDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = AdminOfferSerializer
    queryset = Offer.objects.all()

    def perform_update(self, serializer):
        offer = serializer.save()
        _reconcile_state(self, offer)
        record_audit(self.request.user, "offer.update", target=offer, after={"title": offer.title})

    def perform_destroy(self, offer):
        """Delete a banner.

        A banner that has ever been served is **archived**, not row-deleted:
        ``BannerEvent`` cascades off this row, so a hard delete would silently
        destroy the impression/click history behind past campaign reporting.
        A banner that never ran has nothing to preserve, so it is really deleted.
        """
        if offer.impressions or offer.clicks or offer.events.exists():
            offer.state = Offer.State.ARCHIVED
            offer.is_active = False
            offer.deleted_at = timezone.now()
            offer.save(update_fields=["state", "is_active", "deleted_at"])
            record_audit(self.request.user, "offer.archive", target=offer,
                         after={"reason": "delete requested; history preserved"})
            return
        record_audit(self.request.user, "offer.delete", target=offer,
                     after={"title": offer.title})
        offer.delete()


class AdminOfferImageView(APIView):
    """POST /admin/marketing/offers/<pk>/image — multipart upload → crop to the
    offer's **placement ratio** → WebP size variants.

    The admin crop tool posts a normalized ``cropRect`` (``{x,y,w,h}`` in 0..1 of
    the source image); without one we fall back to a focal-point crop. Each
    upload bumps image_version for instant cache-busting.
    """

    permission_classes = [IsAdmin]

    def post(self, request, pk):
        offer = get_object_or_404(Offer, pk=pk)
        uploaded = request.FILES.get("file") or request.FILES.get("image")

        def _f(name_a, name_b, default):
            val = request.data.get(name_a, request.data.get(name_b, default))
            try:
                return min(max(float(val), 0.0), 1.0)
            except (TypeError, ValueError):
                return default

        fx, fy = _f("focus_x", "focusX", 0.5), _f("focus_y", "focusY", 0.5)
        # Multipart sends the rect as a JSON string; JSON bodies send it as a dict.
        raw_rect = request.data.get("cropRect", request.data.get("crop_rect"))
        if isinstance(raw_rect, str):
            try:
                raw_rect = json.loads(raw_rect)
            except ValueError:
                raw_rect = None

        version = (offer.image_version + 1) if offer.image_uuid else 1
        bid, ver = process_banner_image(
            uploaded, placement=offer.placement, crop_rect=raw_rect,
            focus_x=fx, focus_y=fy, image_uuid=offer.image_uuid, version=version,
        )
        offer.image_uuid, offer.image_version = bid, ver
        offer.focus_x, offer.focus_y = fx, fy
        offer.crop_rect = normalize_crop_rect(raw_rect) or {}
        offer.save(update_fields=[
            "image_uuid", "image_version", "focus_x", "focus_y", "crop_rect",
        ])
        record_audit(request.user, "offer.image", target=offer, after={"image_version": ver})
        return Response(ok("BANNER_SAVED", data={
            "image": image_urls(bid, ver), "imageVersion": ver,
            "focus": {"x": fx, "y": fy}, "cropRect": offer.crop_rect,
            "spec": public_spec_for(offer.placement),
        }))


class BannerSpecView(APIView):
    """GET /offers/specs — the placement geometry table.

    Public on purpose: the admin crop tool, the store panel's submission form and
    the docs all need the exact pixel sizes, and there is nothing sensitive in a
    list of aspect ratios.
    """

    permission_classes = []
    authentication_classes = []

    def get(self, request):
        return Response(ok("OK", data={"placements": public_specs()}))


class BannerStateView(APIView):
    """POST /admin/marketing/offers/<pk>/<action> — banner workflow transitions:
    submit | approve | reject | pause | resume | archive."""

    permission_classes = [IsAdmin]

    def post(self, request, pk, action):
        offer = get_object_or_404(Offer, pk=pk)
        handler = getattr(self, f"_{action.lower()}", None)
        if handler is None:
            raise AppError("INVALID_BANNER_TRANSITION")
        return handler(request, offer)

    # ── helpers ──
    def _set(self, request, offer, state, code, **extra):
        offer.state = state
        offer.is_active = state in (Offer.State.ACTIVE, Offer.State.SCHEDULED)
        fields = ["state", "is_active"]
        for k, v in extra.items():
            setattr(offer, k, v)
            fields.append(k)
        offer.save(update_fields=list(set(fields)))
        record_audit(request.user, f"offer.{state}", target=offer, after={"state": state})
        return Response(ok(code, data=AdminOfferSerializer(offer).data))

    def _require(self, offer, *allowed):
        if offer.state not in allowed:
            raise AppError("INVALID_BANNER_TRANSITION")

    def _target_live_state(self, offer):
        now = timezone.now()
        if offer.valid_to and offer.valid_to < now:
            return Offer.State.EXPIRED       # already past its window
        if offer.valid_from and offer.valid_from > now:
            return Offer.State.SCHEDULED
        return Offer.State.ACTIVE

    # ── transitions ──
    def _submit(self, request, offer):
        self._require(offer, Offer.State.DRAFT)
        return self._set(request, offer, Offer.State.PENDING, "BANNER_SUBMITTED")

    def _approve(self, request, offer):
        self._require(offer, Offer.State.PENDING, Offer.State.PAUSED,
                      Offer.State.SCHEDULED, Offer.State.EXPIRED)
        return self._set(
            request, offer, self._target_live_state(offer), "BANNER_APPROVED",
            approved_by=request.user, approved_at=timezone.now(), rejection_reason="",
        )

    def _reject(self, request, offer):
        self._require(offer, Offer.State.PENDING)
        reason = (request.data.get("reason") or request.data.get("rejection_reason") or "")[:200]
        return self._set(request, offer, Offer.State.DRAFT, "BANNER_REJECTED",
                         rejection_reason=reason)

    def _pause(self, request, offer):
        self._require(offer, Offer.State.ACTIVE, Offer.State.SCHEDULED)
        return self._set(request, offer, Offer.State.PAUSED, "BANNER_STATE_CHANGED")

    def _resume(self, request, offer):
        self._require(offer, Offer.State.PAUSED, Offer.State.EXPIRED)
        return self._set(request, offer, self._target_live_state(offer), "BANNER_STATE_CHANGED")

    def _archive(self, request, offer):
        if offer.state == Offer.State.ARCHIVED:
            raise AppError("INVALID_BANNER_TRANSITION")
        return self._set(request, offer, Offer.State.ARCHIVED, "BANNER_STATE_CHANGED",
                         deleted_at=timezone.now())


class AdminCouponListCreateView(ListCreateAPIView):
    permission_classes = [IsAdmin]
    pagination_class = None
    serializer_class = AdminCouponSerializer
    queryset = Coupon.objects.all().order_by("-id")

    def perform_create(self, serializer):
        coupon = serializer.save()
        record_audit(self.request.user, "coupon.create", target=coupon, after={"code": coupon.code})


class AdminCouponDetailView(RetrieveUpdateDestroyAPIView):
    permission_classes = [IsAdmin]
    serializer_class = AdminCouponSerializer
    queryset = Coupon.objects.all()

    def perform_update(self, serializer):
        coupon = serializer.save()
        record_audit(self.request.user, "coupon.update", target=coupon, after={"code": coupon.code})

    def perform_destroy(self, coupon):
        """Delete a coupon.

        A coupon that has ever been redeemed is **deactivated**, not row-deleted:
        ``CouponRedemption`` cascades off this row, so a hard delete would wipe
        the redemption history that accounting reconciles discounts against —
        while the console's own dialog promises those records are kept. Mirrors
        the banner archive path above. An unredeemed coupon is really deleted.
        """
        if coupon.redemptions.exists():
            coupon.is_active = False
            coupon.save(update_fields=["is_active"])
            record_audit(self.request.user, "coupon.deactivate", target=coupon,
                         after={"code": coupon.code,
                                "reason": "delete requested; redemptions preserved"})
            return
        record_audit(self.request.user, "coupon.delete", target=coupon,
                     after={"code": coupon.code})
        coupon.delete()


class NotificationCampaignView(APIView):
    """POST /admin/marketing/notify — fan a notification out to a customer segment
    (all | credit | zone). Writes inbox rows (FCM push rides notifications.services
    when configured)."""

    permission_classes = [IsAdmin]

    def _targets(self, segment, zone_id):
        base = User.objects.filter(role="customer", is_active=True)
        if segment == "credit":
            return base.filter(credit_enabled=True)
        if segment == "zone" and zone_id:
            from orders.models import Order

            uids = Order.objects.filter(zone_id=zone_id).values_list("user_id", flat=True).distinct()
            return base.filter(id__in=list(uids))
        return base

    def post(self, request):
        from notifications.services import broadcast

        title = (request.data.get("title") or "").strip()
        body = (request.data.get("body") or "").strip()
        segment = request.data.get("segment", "all")
        zone_id = request.data.get("zone_id") or request.data.get("zoneId")
        # Optional hero image (a public media URL from the picker) → notification image.
        image = (request.data.get("imageUrl") or request.data.get("image_url") or "").strip()
        route = (request.data.get("route") or "offers").strip()
        if not title:
            return Response(
                {"error": {"code": "bad_request", "message": "Title is required.", "fields": {}}},
                status=400,
            )
        data = {"segment": segment, "route": route}
        if image:
            data["image"] = image
        # Writes inbox rows AND fires the real FCM push (branded with the logo/hero).
        sent = broadcast(
            self._targets(segment, zone_id).only("id"),
            type="promo", title=title, body=body, data=data,
        )
        record_audit(request.user, "marketing.notify", after={"segment": segment, "count": sent})
        return Response({"sent": sent, "segment": segment, "at": timezone.now()})
