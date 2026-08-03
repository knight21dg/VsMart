"""The store-PRIVATE category tree that drives the customer Categories tab.

The tab browses the serving store's OWN products (``Product.origin_store`` set) —
not the company-wide catalog. A category belongs to that tree only when the store's
private products actually live in it or somewhere beneath it, so the rail never
offers a department that dead-ends in an empty grid.

Every consumer (the level listing, its counts, and the leaf product list) goes
through :func:`private_products_queryset` so they cannot disagree: a product the
store has hidden must not leave a phantom count behind on a rail tile.
"""

# A category nested deeper than this is a mis-seeded cycle, not a real taxonomy.
# Bounds the ancestor walk so bad data degrades instead of hanging the request.
_MAX_DEPTH = 32


def private_products_queryset(store):
    """The store's own products that it currently offers, or an empty queryset.

    "Currently offers" is the same union the storefront uses (:func:`visible_product_ids`
    — stocked, or explicitly carried, minus explicitly hidden), so the tree and the
    storefront agree on what this shop sells.
    """
    from .models import Product

    if store is None:
        return Product.objects.none()
    from stores.services import visible_product_ids

    qs = Product.objects.filter(is_active=True, origin_store=store)
    ids = visible_product_ids(store)
    if ids is not None:
        qs = qs.filter(id__in=ids)
    return qs


def _ancestor_chain(category_id, parents):
    """``category_id`` followed by each of its ancestors, root last."""
    seen = set()
    node = category_id
    while node is not None and node not in seen and len(seen) < _MAX_DEPTH:
        seen.add(node)
        yield node
        node = parents.get(node)


def tree_from_products(product_qs):
    """``(visible_category_ids, subtree_count_by_category_id)`` for any product set.

    Shared by the store-private tree and the ordinary category listing: a category
    is visible when products in the set sit in it or under it, and its count is the
    whole subtree.
    """
    from .models import Category

    direct = {}
    for cid in product_qs.values_list("category_id", flat=True):
        direct[cid] = direct.get(cid, 0) + 1
    if not direct:
        return set(), {}

    parents = dict(Category.objects.values_list("id", "parent_id"))
    visible, counts = set(), {}
    for cid, n in direct.items():
        for node in _ancestor_chain(cid, parents):
            visible.add(node)
            counts[node] = counts.get(node, 0) + n
    return visible, counts


def scoped_category_ids(request):
    """Categories the SERVING STORE can actually fill, or None when unscoped.

    The category endpoints returned the whole company tree regardless of location,
    while ``/products`` was store-scoped — so a customer saw departments their store
    carries nothing in, tapped one, and got an empty listing. Dead tiles.

    Returns None when store scoping isn't active (global catalog), so the caller
    leaves its queryset alone and nothing changes for a single-store deployment.
    """
    from stores.services import resolve_catalog_store, scope_catalog_queryset

    from .models import Product

    _, active = resolve_catalog_store(request)
    if not active:
        return None
    visible, _ = tree_from_products(
        scope_catalog_queryset(Product.objects.filter(is_active=True), request)
    )
    return visible


def private_tree(store):
    """``(visible_category_ids, subtree_product_count_by_category_id)``.

    A category is visible when the store's private products sit in it or under it;
    its count is the size of that whole subtree, so a parent tile reports everything
    reachable through it rather than only what is filed directly against it.
    """
    from .models import Category

    direct = {}
    for cid in private_products_queryset(store).values_list("category_id", flat=True):
        direct[cid] = direct.get(cid, 0) + 1
    if not direct:
        return set(), {}

    parents = dict(Category.objects.values_list("id", "parent_id"))
    visible, counts = set(), {}
    for cid, n in direct.items():
        for node in _ancestor_chain(cid, parents):
            visible.add(node)
            counts[node] = counts.get(node, 0) + n
    return visible, counts


def representative_images(store):
    """``{category_id: image_url}`` — a stand-in picture for every category in the
    tree, taken from a product beneath it.

    Categories created from the store panel usually have no ``image_url`` of their
    own, which left the rail and the grid showing nothing but a generic fallback
    icon. Borrowing a product photo from inside the category gives every tile a real
    image without asking store staff to curate artwork. A category's OWN image_url
    still wins — this only fills the gap (see ``StoreCategorySerializer``).

    The deepest category a product sits in claims its photo first; ancestors then
    inherit from the first product found beneath them, so a department shows
    something representative rather than staying blank.
    """
    from .models import Category

    parents = dict(Category.objects.values_list("id", "parent_id"))
    images = {}
    for cid, img in (
        private_products_queryset(store)
        .exclude(image_url__isnull=True)
        .exclude(image_url="")
        .values_list("category_id", "image_url")
    ):
        for node in _ancestor_chain(cid, parents):
            images.setdefault(node, img)
    return images


def branch_ids(visible):
    """Of the visible categories, those that have at least one visible CHILD.

    The app uses this to decide what a tap does: drill into another level of the
    rail, or open the leaf's product grid.
    """
    from .models import Category

    if not visible:
        return set()
    return {
        pid
        for pid in Category.objects.filter(
            is_active=True, id__in=visible
        ).values_list("parent_id", flat=True)
        if pid is not None
    }
