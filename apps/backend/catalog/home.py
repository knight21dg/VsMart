"""Home-screen rails: admin curation with an algorithmic fallback.

One rule, in one place: **a rail serves its curated pins when any exist, and its
algorithmic ordering when none do.** Everything else (which sort backs which
rail, how many products a rail holds) is declared here so the customer endpoint,
the admin endpoint and the app can't drift apart.
"""
from .models import HomeFeature, Product

#: The ordering each rail falls back to when nothing is curated. These are the
#: exact sorts the app used to request directly from `/products?sort=…`, kept so
#: an uncurated install behaves precisely as it did before.
SECTION_FALLBACK_SORT = {
    HomeFeature.Section.TODAY_DEALS: "discount",   # biggest markdown first
    HomeFeature.Section.POPULAR: "popular",        # most reviewed
    HomeFeature.Section.RECOMMENDED: "rating",     # best rated
    HomeFeature.Section.TOP_SELLING: "top_selling",  # most units sold
}

#: How many products a rail shows. A rail is a horizontal scroller, not a grid —
#: past ~12 nobody scrolls, and every extra row is a wasted query on cold start.
SECTION_LIMIT = 12

VALID_SECTIONS = tuple(SECTION_FALLBACK_SORT)


def _apply_fallback_sort(qs, sort):
    """Order `qs` the way the uncurated rail expects."""
    if sort == "popular":
        return qs.order_by("-review_count", "-rating")
    if sort == "rating":
        return qs.order_by("-rating", "-review_count")
    if sort == "top_selling":
        # Units actually sold, not units listed. Counted from delivered order
        # lines so a cancelled or returned order can't inflate a "top seller".
        from django.db.models import Count, Q, Sum
        from orders.models import OrderStatus

        delivered = Q(orderitem__order__status=OrderStatus.DELIVERED)
        return qs.annotate(
            units_sold=Sum("orderitem__quantity", filter=delivered),
            order_count=Count("orderitem__order", filter=delivered, distinct=True),
        ).order_by("-units_sold", "-order_count", "-review_count")
    if sort == "discount":
        # Mirrors ProductListView's `sort=discount`: annotate the markdown ratio
        # rather than ordering by the computed `discount_percent` property.
        from django.db.models import ExpressionWrapper, FloatField, Value
        from django.db.models.functions import Cast, Coalesce, NullIf

        ratio = ExpressionWrapper(
            (Cast("mrp", FloatField()) - Cast("price", FloatField()))
            / NullIf(Cast("mrp", FloatField()), Value(0.0)),
            output_field=FloatField(),
        )
        return qs.annotate(
            _discount=Coalesce(ratio, Value(0.0), output_field=FloatField())
        ).order_by("-_discount", "-review_count")
    return qs


def section_products(section, *, base_queryset, limit=SECTION_LIMIT):
    """Products for one home rail, in display order.

    `base_queryset` is the caller's already visibility-scoped set (store-scoped
    catalog, active products only) — curation must never widen it. A pinned
    product that the serving store doesn't carry is simply dropped rather than
    shown-and-unbuyable, and the rail tops up from the fallback so it never
    collapses to two items in one town and eight in another.
    """
    if section not in SECTION_FALLBACK_SORT:
        raise ValueError(f"Unknown home section: {section}")

    pinned_ids = list(
        HomeFeature.objects.filter(section=section, is_active=True)
        .order_by("sort_order", "id")
        .values_list("product_id", flat=True)
    )
    if not pinned_ids:
        return list(
            _apply_fallback_sort(base_queryset, SECTION_FALLBACK_SORT[section])[:limit]
        )

    # Fetch the pins in one query, then restore the curator's order in Python —
    # SQL has no portable "order by this list" and the list is at most `limit`.
    by_id = {p.id: p for p in base_queryset.filter(id__in=pinned_ids)}
    products = [by_id[pid] for pid in pinned_ids if pid in by_id][:limit]

    if len(products) < limit:
        # Top up with the algorithmic tail so a thinly-curated rail (or one whose
        # pins this store doesn't stock) still fills out.
        seen = {p.id for p in products}
        filler = _apply_fallback_sort(
            base_queryset.exclude(id__in=seen), SECTION_FALLBACK_SORT[section]
        )[: limit - len(products)]
        products.extend(filler)
    return products


def curated_rows(section):
    """Admin view of one rail's pins, in curator order."""
    return (
        HomeFeature.objects.filter(section=section)
        .select_related("product", "product__category", "product__origin_store")
        .order_by("sort_order", "id")
    )


def active_product_queryset():
    """The unscoped starting set for a rail: live products only.

    Callers layer store visibility on top (see `_StoreContextMixin`); this only
    guarantees an archived product can never surface on the home screen, which
    is how a delisted line kept appearing in "Popular".
    """
    return (
        Product.objects.filter(is_active=True)
        .select_related("category")
        .prefetch_related("variants")
    )
