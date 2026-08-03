"""Store-scoped banner submission.

A store manager can propose a banner for **their own store** and submit it for
super-admin approval. They can never:

* target another store, a zone, or the global audience (``store`` is forced to
  the caller's store and ``zone`` is never writable),
* approve their own banner (``submit`` is the only transition offered here;
  approve/reject live in the admin console),
* edit a banner once it has left DRAFT — an approved banner is frozen until an
  admin pauses it.

Everything else (image pipeline, placement geometry, action validation) is the
same code path the admin console uses, so a store banner can't bypass the
deep-link or crop rules.
"""
import json

from django.shortcuts import get_object_or_404
from rest_framework import serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from accounts.services import record_audit
from core.app_errors import AppError, ok
from offers.imaging import image_urls, normalize_crop_rect, process_banner_image
from offers.models import Coupon, Offer
from offers.specs import public_spec_for, public_specs
from offers.validators import validate_action_payload

from .permissions import StoreScopedMixin

#: Fields a store may set. Deliberately excludes state, zone, store, is_pinned,
#: is_fallback and every counter — those are admin-only levers.
STORE_WRITABLE = {
    "type", "placement", "title", "subtitle", "title_te", "title_hi",
    "subtitle_te", "subtitle_hi", "badge", "code",
    "cta_text", "cta_text_te", "cta_text_hi",
    "text_theme", "text_position", "accent_color",
    "action", "payload", "valid_from", "valid_to", "sort_order",
}

#: A store may only edit its banner while it is still a draft (or was rejected
#: back to draft). Anything live is admin territory.
EDITABLE_STATES = {Offer.State.DRAFT}


class StoreBannerSerializer(serializers.ModelSerializer):
    id = serializers.CharField(read_only=True)
    image = serializers.SerializerMethodField()

    class Meta:
        model = Offer
        fields = [
            "id", "type", "placement", "title", "subtitle",
            "title_te", "title_hi", "subtitle_te", "subtitle_hi",
            "badge", "code", "cta_text", "cta_text_te", "cta_text_hi",
            "text_theme", "text_position", "accent_color",
            "action", "payload", "valid_from", "valid_to", "sort_order",
            "state", "rejection_reason", "image", "image_version",
            "impressions", "clicks",
        ]
        read_only_fields = [
            "state", "rejection_reason", "image_version", "impressions", "clicks",
        ]

    def get_image(self, obj):
        return image_urls(obj.image_uuid, obj.image_version)

    def validate_accent_color(self, value):
        import re

        value = (value or "").strip()
        if value and not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            raise serializers.ValidationError("Use a #RRGGBB hex colour.")
        return value.lower()

    def validate(self, attrs):
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


def _strip_to_writable(data):
    """Drop any field a store isn't allowed to set, accepting camelCase keys."""
    from .io_utils import field

    out = {}
    for name in STORE_WRITABLE:
        camel = "".join(
            part if i == 0 else part.capitalize()
            for i, part in enumerate(name.split("_"))
        )
        value = field(data, camel)
        if value is None and camel not in data and name not in data:
            continue
        out[name] = value
    return out


class StoreBannerListCreateView(StoreScopedMixin, APIView):
    """GET → this store's banners. POST → create one as a DRAFT for this store."""

    store_permission = "marketing.banners"

    def get(self, request):
        qs = (
            Offer.objects.filter(store=self.store, deleted_at__isnull=True)
            .order_by("-id")
        )
        return Response(ok("OK", data={
            "results": StoreBannerSerializer(qs, many=True).data,
            "specs": public_specs(),
        }))

    def post(self, request):
        serializer = StoreBannerSerializer(data=_strip_to_writable(request.data))
        serializer.is_valid(raise_exception=True)
        # Force the ownership fields rather than trusting the body: this is the
        # only thing standing between a store and a global banner.
        offer = serializer.save(
            store=self.store,
            zone=None,
            state=Offer.State.DRAFT,
            is_active=False,
            created_by=request.user,
        )
        record_audit(request.user, "store_banner.create", target=offer,
                     after={"title": offer.title})
        return Response(ok("BANNER_SAVED", data=StoreBannerSerializer(offer).data),
                        status=201)


class StoreBannerDetailView(StoreScopedMixin, APIView):
    """PATCH → edit a draft. DELETE → archive (soft delete)."""

    store_permission = "marketing.banners"

    def _get(self, pk):
        # Filtering on the caller's store IS the authorization check — a banner
        # belonging to another store 404s rather than leaking its existence.
        return get_object_or_404(
            Offer, pk=pk, store=self.store, deleted_at__isnull=True
        )

    def patch(self, request, pk):
        offer = self._get(pk)
        if offer.state not in EDITABLE_STATES:
            raise AppError(
                "INVALID_BANNER_TRANSITION",
                message="Only draft banners can be edited. Ask an admin to pause it first.",
            )
        serializer = StoreBannerSerializer(
            offer, data=_strip_to_writable(request.data), partial=True
        )
        serializer.is_valid(raise_exception=True)
        offer = serializer.save()
        record_audit(request.user, "store_banner.update", target=offer,
                     after={"title": offer.title})
        return Response(ok("BANNER_SAVED", data=StoreBannerSerializer(offer).data))

    def delete(self, request, pk):
        from django.utils import timezone

        offer = self._get(pk)
        offer.state = Offer.State.ARCHIVED
        offer.is_active = False
        offer.deleted_at = timezone.now()
        offer.save(update_fields=["state", "is_active", "deleted_at"])
        record_audit(request.user, "store_banner.archive", target=offer)
        return Response(ok("BANNER_STATE_CHANGED"))


class StoreBannerImageView(StoreScopedMixin, APIView):
    """POST → upload + crop this banner's image (same pipeline as the admin)."""

    store_permission = "marketing.banners"

    def post(self, request, pk):
        offer = get_object_or_404(
            Offer, pk=pk, store=self.store, deleted_at__isnull=True
        )
        if offer.state not in EDITABLE_STATES:
            raise AppError(
                "INVALID_BANNER_TRANSITION",
                message="Only draft banners can be edited.",
            )
        uploaded = request.FILES.get("file") or request.FILES.get("image")
        raw_rect = request.data.get("cropRect", request.data.get("crop_rect"))
        if isinstance(raw_rect, str):
            try:
                raw_rect = json.loads(raw_rect)
            except ValueError:
                raw_rect = None

        version = (offer.image_version + 1) if offer.image_uuid else 1
        bid, ver = process_banner_image(
            uploaded, placement=offer.placement, crop_rect=raw_rect,
            image_uuid=offer.image_uuid, version=version,
        )
        offer.image_uuid, offer.image_version = bid, ver
        offer.crop_rect = normalize_crop_rect(raw_rect) or {}
        offer.save(update_fields=["image_uuid", "image_version", "crop_rect"])
        record_audit(request.user, "store_banner.image", target=offer,
                     after={"image_version": ver})
        return Response(ok("BANNER_SAVED", data={
            "image": image_urls(bid, ver), "imageVersion": ver,
            "spec": public_spec_for(offer.placement),
        }))


class StoreBannerSubmitView(StoreScopedMixin, APIView):
    """POST → send a draft for super-admin approval (DRAFT → PENDING).

    Submit is the *only* transition a store gets. Approval stays in the admin
    console so a store can never publish to its own customers unreviewed.
    """

    store_permission = "marketing.banners"

    def post(self, request, pk):
        offer = get_object_or_404(
            Offer, pk=pk, store=self.store, deleted_at__isnull=True
        )
        if offer.state != Offer.State.DRAFT:
            raise AppError("INVALID_BANNER_TRANSITION")
        if not offer.image_uuid:
            raise AppError(
                "IMAGE_INVALID",
                message="Add a banner image before submitting for approval.",
            )
        offer.state = Offer.State.PENDING
        offer.rejection_reason = ""
        offer.save(update_fields=["state", "rejection_reason"])
        record_audit(request.user, "store_banner.submit", target=offer)
        return Response(ok("BANNER_SUBMITTED",
                           data=StoreBannerSerializer(offer).data))


class StoreCouponListView(StoreScopedMixin, APIView):
    """GET → active coupons, read-only.

    Coupons are platform-wide (a code is not store-scoped), so store staff can
    see and quote them but not create or edit them.
    """

    store_permission = "marketing.banners"

    def get(self, request):
        qs = Coupon.objects.filter(is_active=True).order_by("-id")
        return Response(ok("OK", data=[
            {
                "id": str(c.id),
                "code": c.code,
                "discountType": c.discount_type,
                "value": c.value,
                "minOrder": c.min_order,
                "maxDiscount": c.max_discount,
                "validTo": c.valid_to,
            }
            for c in qs
        ]))
