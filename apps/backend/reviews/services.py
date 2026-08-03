"""Review moderation.

Policy: a review backed by a **verified purchase** publishes immediately — the
customer bought and received the product, so holding it adds friction for the
honest majority. Anything else waits for a human. Only approved reviews are
public or counted in a product's rating.
"""
from django.db.models import Q
from django.utils import timezone

from .models import Review


def find_purchase(user, product):
    """The most recent delivered order in which `user` bought `product`, or None.

    Matches on the order item's product FK. A line whose product was since
    deleted (FK nulled) can't prove anything, so it doesn't count.
    """
    from orders.models import Order, OrderStatus

    return (
        Order.objects.filter(
            user=user,
            status=OrderStatus.DELIVERED,
            items__product=product,
        )
        .order_by("-id")
        .first()
    )


def submit_review(user, product, *, rating, title="", body=""):
    """Create or update a review, auto-approving verified purchases.

    Editing an existing review re-runs moderation: the customer could otherwise
    get benign text approved and then swap in abuse.
    """
    order = find_purchase(user, product)
    verified = order is not None
    status = Review.Status.APPROVED if verified else Review.Status.PENDING

    review, _ = Review.objects.update_or_create(
        user=user,
        product=product,
        defaults={
            "rating": rating,
            "title": title or "",
            "body": body or "",
            "order": order,
            "is_verified_purchase": verified,
            "status": status,
            # A re-submission clears any prior decision.
            "moderated_by": None,
            "moderated_at": None,
            "moderation_reason": "",
        },
    )
    sync_product_aggregates(product)
    return review


def moderate(review, moderator, *, approve, reason=""):
    """Approve or reject a review and refresh the product's rating."""
    review.status = Review.Status.APPROVED if approve else Review.Status.REJECTED
    review.moderated_by = moderator
    review.moderated_at = timezone.now()
    review.moderation_reason = (reason or "")[:300]
    review.save(update_fields=[
        "status", "moderated_by", "moderated_at", "moderation_reason", "updated_at",
    ])
    sync_product_aggregates(review.product)
    return review


def visible_reviews(product=None):
    """Approved reviews only — the public feed and rating basis."""
    qs = Review.objects.filter(status=Review.Status.APPROVED)
    return qs.filter(product=product) if product is not None else qs


def sync_product_aggregates(product):
    """Recompute `Product.rating` / `review_count` from APPROVED reviews only.

    Previously every review moved the rating the moment it was posted, so a
    single spam entry could swing a product's score before anyone saw it.
    """
    from decimal import ROUND_HALF_UP, Decimal

    reviews = visible_reviews(product)
    count = reviews.count()
    if count:
        total = sum(r.rating for r in reviews)
        average = Decimal(total / count).quantize(
            Decimal("0.1"), rounding=ROUND_HALF_UP
        )
    else:
        average = Decimal("0.0")
    product.rating = average
    product.review_count = count
    product.save(update_fields=["rating", "review_count", "updated_at"])


def summary(product):
    """Rating summary over approved reviews."""
    reviews = visible_reviews(product)
    distribution = {str(n): 0 for n in range(1, 6)}
    total = 0
    count = 0
    for rating in reviews.values_list("rating", flat=True):
        count += 1
        total += rating
        if 1 <= rating <= 5:
            distribution[str(rating)] += 1
    return {
        "average": round(total / count, 1) if count else 0,
        "count": count,
        "distribution": distribution,
    }


def moderation_queue(status=None, search=""):
    """Reviews for the admin queue, oldest first (a queue is FIFO)."""
    qs = Review.objects.select_related("user", "product", "moderated_by")
    if status == "pending" or not status:
        qs = qs.filter(status=Review.Status.PENDING)
    elif status != "all":
        qs = qs.filter(status=status)
    search = (search or "").strip()
    if search:
        qs = qs.filter(
            Q(user__name__icontains=search)
            | Q(user__phone__icontains=search)
            | Q(product__name__icontains=search)
            | Q(title__icontains=search)
            | Q(body__icontains=search)
        )
    return qs.order_by("created_at", "id")
