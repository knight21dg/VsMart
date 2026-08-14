import secrets

from django.db import models

from core.models import TimeStampedModel


def gen_share_token() -> str:
    """An unguessable, URL-safe token for a product's public share link.
    ~96 bits of entropy → not enumerable (unlike the sequential integer id)."""
    return secrets.token_urlsafe(12)


class Category(TimeStampedModel):
    name = models.CharField(max_length=80)
    # Catalog CONTENT translations. The app's ARB files localize UI chrome only;
    # a category name is data, so it needs its own columns. The API resolves
    # these server-side into `name` (see core.i18n), so clients are unchanged.
    # Blank falls back to the English `name` — a half-translated catalog must
    # never render an empty title.
    name_te = models.CharField(max_length=80, blank=True)
    name_hi = models.CharField(max_length=80, blank=True)
    slug = models.SlugField(max_length=100, unique=True)
    parent = models.ForeignKey(
        "self", null=True, blank=True, on_delete=models.CASCADE, related_name="children"
    )
    icon_name = models.CharField(max_length=40, blank=True)
    image_url = models.URLField(blank=True, null=True)
    product_count = models.PositiveIntegerField(default=0)
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["sort_order", "name"]
        verbose_name_plural = "categories"

    def __str__(self):
        return self.name


class Product(TimeStampedModel):
    name = models.CharField(max_length=160)
    # Content translations — resolved server-side into `name` / `description`
    # by core.i18n. Blank falls back to English.
    name_te = models.CharField(max_length=160, blank=True)
    name_hi = models.CharField(max_length=160, blank=True)
    # Extra terms a shopper might actually type: local names, transliterations
    # ("biyyam", "బియ్యం" for rice), common misspellings, pack synonyms.
    # Comma/space separated, matched by search but never displayed.
    search_keywords = models.TextField(
        blank=True,
        help_text="Alternate search terms — local names, transliterations, "
                  "synonyms. Comma separated. Never shown to customers.",
    )
    brand = models.CharField(max_length=80, blank=True)
    unit = models.CharField(max_length=40, default="Each")
    # Product Master identifiers (admin-managed). SKU/HSN are free text.
    sku = models.CharField(max_length=60, blank=True, db_index=True)
    hsn = models.CharField(max_length=20, blank=True)
    # GST rate as a PERCENTAGE (18 means 18%), matching the statutory slabs and
    # the number the operator actually types. Null falls back to the platform
    # default. Stored as a percentage rather than a fraction because that is what
    # `OrderItem.gst_rate` snapshots and what a GST return reports; the pricing
    # maths converts via `core.pricing.gst_pct_to_fraction`.
    gst_rate = models.DecimalField(
        max_digits=5, decimal_places=2, null=True, blank=True
    )
    price = models.DecimalField(max_digits=12, decimal_places=2)
    mrp = models.DecimalField(max_digits=12, decimal_places=2)
    credit_price = models.DecimalField(
        max_digits=12, decimal_places=2, null=True, blank=True
    )
    category = models.ForeignKey(
        Category, on_delete=models.PROTECT, related_name="products"
    )
    rating = models.DecimalField(max_digits=2, decimal_places=1, default=0)
    review_count = models.PositiveIntegerField(default=0)
    in_stock = models.BooleanField(default=True)
    stock_count = models.PositiveIntegerField(null=True, blank=True)
    # Sellable units = on-hand − reserved (cache maintained by StockSyncService).
    available_count = models.IntegerField(default=0)
    description = models.TextField(blank=True)
    description_te = models.TextField(blank=True)
    description_hi = models.TextField(blank=True)
    image_url = models.URLField(blank=True, null=True)
    specifications = models.JSONField(default=dict, blank=True)
    is_active = models.BooleanField(default=True)
    # Unguessable public share slug. Shareable links use THIS (not the sequential
    # id), so a store-private product can be shared by link without its id being
    # enumerable. See ProductDetailView (token → open; numeric id → store-scoped).
    share_token = models.CharField(
        max_length=32, unique=True, db_index=True, default=gen_share_token,
        editable=False,
    )
    # When set, this product is PRIVATE to a single store — created from the store
    # panel. Such a product is never shown in the global catalog or any other store's
    # catalog/POS; only its owning store sells it. NULL = a normal company-wide product.
    origin_store = models.ForeignKey(
        "stores.Store",
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name="own_products",
    )

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["category", "is_active"]),
            models.Index(fields=["origin_store"]),
        ]

    def __str__(self):
        return self.name

    @property
    def discount_percent(self):
        if self.mrp and self.mrp > self.price:
            return round((self.mrp - self.price) / self.mrp * 100)
        return 0

    @property
    def discount_amount(self):
        if self.mrp and self.mrp > self.price:
            return self.mrp - self.price
        return self.price * 0  # Decimal 0.00


class ProductImage(models.Model):
    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="gallery"
    )
    url = models.URLField()
    sort = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort"]


class ProductVariant(models.Model):
    """A separately-stocked pack of a product (500g / 1kg / 5kg).

    A variant is its own stock-keeping unit: it has its own on-hand count in each
    warehouse (``StockItem`` keys on product×variant×warehouse) and its own image.
    Two variants of one product are NOT a shared pool divided by pack size — the
    shop counts each pack separately, so selling a 1kg does not decrement 500g.
    """

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="variants"
    )
    label = models.CharField(max_length=60)
    price_delta = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    # DERIVED from this variant's own stock — never hand-set. StockSyncService
    # .broadcast writes it after every movement.
    in_stock = models.BooleanField(default=True)
    # Falls back to the product's image when blank, so a variant only needs its own
    # picture when the pack actually looks different.
    image_url = models.URLField(max_length=500, blank=True)
    # Inventory/POS fields (Phase 5).
    sku = models.CharField(max_length=60, blank=True)
    mrp = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)
    cost = models.DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)


class HomeFeature(TimeStampedModel):
    """An admin-curated slot in a customer home-screen rail.

    The home rails were purely algorithmic — "Popular" was
    ``/products?sort=popular`` (most reviewed) and "Recommended" was
    ``sort=rating``. Neither could be influenced from the console, so a
    merchandiser had no way to push a new line, clear a slow-moving one, or run a
    seasonal front page. The PDF's "Today Deals and Popular Products cannot be
    managed from Admin/Store" is exactly this.

    Curation is **additive and optional**: a section with no active rows keeps
    serving its algorithmic ordering, so nothing changes until someone curates.
    The moment one product is pinned, the rail becomes the pinned list — a
    half-curated rail would let the algorithm silently outrank the merchandiser's
    choice, which is the surprising behaviour, not the useful one.
    """

    class Section(models.TextChoices):
        TODAY_DEALS = "today_deals", "Today's Deals"
        POPULAR = "popular", "Popular Products"
        RECOMMENDED = "recommended", "Recommended For You"
        TOP_SELLING = "top_selling", "Top Selling"

    #: Which rail this pin belongs to. The algorithmic fallback per section is
    #: declared once in `catalog.home.SECTION_FALLBACK_SORT`.
    section = models.CharField(max_length=20, choices=Section.choices, db_index=True)
    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="home_features"
    )
    sort_order = models.PositiveIntegerField(default=0)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["section", "sort_order", "id"]
        # One product cannot occupy the same rail twice — without this, a
        # double-submitted "Add to rail" put the product on screen twice.
        constraints = [
            models.UniqueConstraint(
                fields=["section", "product"], name="uniq_home_feature_section_product"
            )
        ]
        indexes = [models.Index(fields=["section", "is_active", "sort_order"])]

    def __str__(self):
        return f"{self.get_section_display()} · {self.product_id}"
