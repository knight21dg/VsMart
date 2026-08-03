from django.conf import settings
from django.db import models

from catalog.models import Product
from core.models import TimeStampedModel


class Offer(TimeStampedModel):
    class Type(models.TextChoices):
        BANNER = "banner"
        DEAL = "deal"
        COUPON = "coupon"

    class Placement(models.TextChoices):
        TOP = "top"            # hero carousel at the top of Home
        MIDDLE = "middle"      # secondary carousel lower on Home
        SPOTLIGHT = "spotlight"  # product-spotlight card (PNG over a background)
        PRODUCT_LIST = "product_list"      # banner on category / product-listing screens
        PRODUCT_DETAIL = "product_detail"  # banner on the product-detail screen
        CART = "cart"          # banner above the bill summary in the cart

    class TextTheme(models.TextChoices):
        """How overlay copy is painted over the image."""
        LIGHT = "light"   # white text over a dark bottom scrim (default)
        DARK = "dark"     # near-black text over a light scrim (bright artwork)
        NONE = "none"     # image only — the artwork already carries the copy

    class TextPosition(models.TextChoices):
        BOTTOM_LEFT = "bottom_left"
        BOTTOM_CENTER = "bottom_center"
        CENTER = "center"
        TOP_LEFT = "top_left"

    class State(models.TextChoices):
        DRAFT = "draft"            # being created, never shown
        PENDING = "pending"        # submitted, awaiting super-admin approval
        SCHEDULED = "scheduled"    # approved, waiting for start (valid_from)
        ACTIVE = "active"          # live (within schedule window)
        PAUSED = "paused"          # manual kill-switch, config preserved
        EXPIRED = "expired"        # past valid_to (set by the expiry sweep)
        ARCHIVED = "archived"      # soft-deleted, kept for analytics history

    class Action(models.TextChoices):
        NONE = "none"
        HOME = "home"
        CATEGORY = "category"
        PRODUCT = "product"
        BRAND = "brand"
        SEARCH = "search"
        CREDIT = "credit"
        OFFERS = "offers"
        CART = "cart"
        PROFILE = "profile"
        ORDER = "order"
        STORE = "store"
        EXTERNAL = "external"

    type = models.CharField(max_length=10, choices=Type.choices)
    # Where a banner renders (home placements, or product_list / product_detail).
    placement = models.CharField(
        max_length=20, choices=Placement.choices, default=Placement.TOP
    )
    title = models.CharField(max_length=160)
    subtitle = models.CharField(max_length=200, blank=True)
    code = models.CharField(max_length=40, blank=True)
    image_url = models.URLField(blank=True, null=True)
    badge = models.CharField(max_length=40, blank=True)
    discount_percent = models.PositiveIntegerField(null=True, blank=True)
    deal_price = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    original_price = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    product = models.ForeignKey(
        Product, on_delete=models.SET_NULL, null=True, blank=True
    )
    # Targeting for product_list / product_detail banners. A banner shows on a
    # category's (or sub-category's) screens; `is_fallback` banners show wherever
    # no category-targeted banner matches (the "marketing" default).
    category = models.ForeignKey(
        "catalog.Category", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="offers",
    )
    subcategory = models.ForeignKey(
        "catalog.Category", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="offers_as_sub",
    )
    is_fallback = models.BooleanField(
        default=False,
        help_text="Show on product screens when no category-targeted banner matches.",
    )
    valid_from = models.DateTimeField(null=True, blank=True)
    valid_to = models.DateTimeField(null=True, blank=True)
    # Informational: the wall-clock zone the admin scheduled in. DB always stores UTC.
    timezone = models.CharField(max_length=40, default="Asia/Kolkata")
    is_active = models.BooleanField(default=True)  # legacy; derived from `state` going forward
    sort_order = models.PositiveIntegerField(default=0)

    # ── Lifecycle (v1.0 state machine; supersedes the is_active boolean) ──
    state = models.CharField(
        max_length=12, choices=State.choices, default=State.DRAFT, db_index=True
    )
    is_pinned = models.BooleanField(
        default=False, help_text="Force to the top of its placement, above sort_order."
    )

    # ── Zone / store targeting (reuses the serviceability architecture) ──
    # zone is null AND store is null  =>  GLOBAL (shown to everyone).
    zone = models.ForeignKey(
        "zones.Zone", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="offers",
    )
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True,
        related_name="offers",
    )

    # ── Multilingual overlay text (title/subtitle remain the en default) ──
    title_te = models.CharField(max_length=160, blank=True)
    title_hi = models.CharField(max_length=160, blank=True)
    subtitle_te = models.CharField(max_length=200, blank=True)
    subtitle_hi = models.CharField(max_length=200, blank=True)

    # ── Call-to-action pill drawn under the subtitle (blank => no button) ──
    cta_text = models.CharField(max_length=40, blank=True)
    cta_text_te = models.CharField(max_length=40, blank=True)
    cta_text_hi = models.CharField(max_length=40, blank=True)

    # ── Overlay presentation ──
    text_theme = models.CharField(
        max_length=8, choices=TextTheme.choices, default=TextTheme.LIGHT,
        help_text="`none` renders the artwork with no text/scrim at all.",
    )
    text_position = models.CharField(
        max_length=16, choices=TextPosition.choices, default=TextPosition.BOTTOM_LEFT,
    )
    accent_color = models.CharField(
        max_length=7, blank=True,
        help_text="#RRGGBB for the CTA pill and badge. Blank => brand green.",
    )

    # ── Deep link (enum + payload; the app never parses URLs) ──
    action = models.CharField(max_length=12, choices=Action.choices, default=Action.NONE)
    payload = models.JSONField(default=dict, blank=True)  # e.g. {"product_id": 18}

    # ── Image pipeline (new uploads). Legacy rows keep image_url. ──
    image_uuid = models.UUIDField(null=True, blank=True, db_index=True)  # media folder key
    image_version = models.PositiveIntegerField(default=1)               # cache-bust (in path)
    image_te = models.UUIDField(null=True, blank=True)  # festival per-language image override
    image_hi = models.UUIDField(null=True, blank=True)
    focus_x = models.FloatField(default=0.5)  # 0..1 focal point for safe cropping
    focus_y = models.FloatField(default=0.5)
    # Normalized crop the admin cropper chose on the *source* image, kept so the
    # crop can be re-opened and nudged instead of re-cropped from scratch:
    # {"x": .., "y": .., "w": .., "h": ..} all 0..1. Empty => focal-point crop.
    crop_rect = models.JSONField(default=dict, blank=True)

    # ── Audience targeting (stored from v1; enforcement is Phase 2) ──
    audience = models.JSONField(default=dict, blank=True)

    # ── Approval / audit ──
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="offers_created",
    )
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="offers_approved",
    )
    approved_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.CharField(max_length=200, blank=True)

    # ── Denormalized analytics counters (aggregated from BannerEvent) ──
    impressions = models.PositiveIntegerField(default=0)
    clicks = models.PositiveIntegerField(default=0)
    orders = models.PositiveIntegerField(default=0)
    revenue = models.DecimalField(max_digits=14, decimal_places=2, default=0)

    deleted_at = models.DateTimeField(null=True, blank=True)  # soft delete -> state ARCHIVED

    class Meta:
        ordering = ["-is_pinned", "sort_order", "-id"]

    def __str__(self):
        return self.title


class BannerEvent(TimeStampedModel):
    """Append-only banner interaction log — the source of truth for analytics.
    Denormalized counters on Offer are aggregated from these rows."""

    class Kind(models.TextChoices):
        IMPRESSION = "impression"
        CLICK = "click"
        VIEW = "view"          # downstream product view after a click
        ATC = "atc"            # add-to-cart attributed to the click
        ORDER = "order"        # order attributed to the click (Phase 2 revenue)

    offer = models.ForeignKey(Offer, on_delete=models.CASCADE, related_name="events")
    kind = models.CharField(max_length=12, choices=Kind.choices, db_index=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True
    )
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True
    )
    zone = models.ForeignKey(
        "zones.Zone", on_delete=models.SET_NULL, null=True, blank=True
    )
    # Threads click -> view -> atc -> order for revenue attribution (Phase 2).
    click_id = models.UUIDField(null=True, blank=True, db_index=True)

    def __str__(self):
        return f"{self.kind} / offer {self.offer_id}"


class Coupon(TimeStampedModel):
    class DiscountType(models.TextChoices):
        FLAT = "flat"
        PERCENT = "percent"

    code = models.CharField(max_length=40, unique=True)
    # A PERSONAL coupon belongs to one customer (e.g. issued by redeeming loyalty
    # points). It is rejected for anyone else, so learning the code is useless.
    # NULL = a public campaign code anyone may use.
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True,
        related_name="personal_coupons",
    )
    discount_type = models.CharField(max_length=10, choices=DiscountType.choices)
    value = models.DecimalField(max_digits=12, decimal_places=2)
    min_order = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    max_discount = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    usage_limit = models.PositiveIntegerField(null=True, blank=True)
    per_user_limit = models.PositiveIntegerField(null=True, blank=True)
    valid_to = models.DateField(null=True, blank=True)
    is_active = models.BooleanField(default=True)

    def __str__(self):
        return self.code


class CouponRedemption(TimeStampedModel):
    coupon = models.ForeignKey(
        Coupon, on_delete=models.CASCADE, related_name="redemptions"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="redemptions"
    )
    order_code = models.CharField(max_length=40, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)

    def __str__(self):
        return f"{self.coupon.code} / {self.order_code}"
