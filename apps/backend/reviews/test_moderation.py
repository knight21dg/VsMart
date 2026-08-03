"""Review moderation + verified purchase.

Before this, any user could review any product they had never bought, it
published instantly into the product's rating, and there was no takedown path.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User
from catalog.models import Category, Product
from orders.models import Order, OrderItem, OrderStatus

from .models import Review


def _data(resp):
    body = resp.json()["data"]
    return body["results"] if isinstance(body, dict) and "results" in body else body


class ReviewModerationTests(TestCase):
    def setUp(self):
        self.cat = Category.objects.create(name="Snacks", slug="snacks")
        self.product = Product.objects.create(
            name="Chips", category=self.cat,
            price=Decimal("10"), mrp=Decimal("12"),
        )
        self.buyer = User.objects.create(phone="+919000001001", name="Buyer",
                                         role="customer")
        self.stranger = User.objects.create(phone="+919000001002", name="Stranger",
                                            role="customer")
        self.admin = User.objects.create(phone="+919000001003", name="Mod",
                                         role="admin")

        order = Order.objects.create(
            user=self.buyer, payment_method="cod", status=OrderStatus.DELIVERED,
            total=Decimal("10"), subtotal=Decimal("10"),
        )
        OrderItem.objects.create(order=order, product=self.product, name="Chips",
                                 quantity=1, price=Decimal("10"), mrp=Decimal("12"))

        self.buyer_client = APIClient()
        self.buyer_client.force_authenticate(self.buyer)
        self.stranger_client = APIClient()
        self.stranger_client.force_authenticate(self.stranger)
        self.staff = APIClient()
        self.staff.force_authenticate(self.admin)

    def _post(self, client, rating=5, body="Great"):
        return client.post(
            f"/api/v1/products/{self.product.id}/reviews",
            {"rating": rating, "title": "t", "body": body}, format="json",
        )

    def _public(self):
        r = self.client.get(f"/api/v1/products/{self.product.id}/reviews")
        return r.json()["data"]

    # ── verified purchase auto-approves ──
    def test_a_real_buyer_publishes_immediately(self):
        r = self._post(self.buyer_client)
        self.assertEqual(r.status_code, 201)
        review = Review.objects.get(user=self.buyer)
        self.assertEqual(review.status, Review.Status.APPROVED)
        self.assertTrue(review.is_verified_purchase)
        self.assertIsNotNone(review.order)
        self.assertEqual(len(self._public()["reviews"]), 1)

    def test_someone_who_never_bought_it_is_held_for_moderation(self):
        r = self._post(self.stranger_client)
        self.assertEqual(r.status_code, 201)
        review = Review.objects.get(user=self.stranger)
        self.assertEqual(review.status, Review.Status.PENDING)
        self.assertFalse(review.is_verified_purchase)
        # Not public, and not counted in the rating.
        self.assertEqual(self._public()["reviews"], [])
        self.product.refresh_from_db()
        self.assertEqual(self.product.review_count, 0)

    def test_an_undelivered_order_does_not_count_as_a_purchase(self):
        order = Order.objects.create(
            user=self.stranger, payment_method="cod", status=OrderStatus.PLACED,
            total=Decimal("10"), subtotal=Decimal("10"),
        )
        OrderItem.objects.create(order=order, product=self.product, name="Chips",
                                 quantity=1, price=Decimal("10"), mrp=Decimal("12"))
        self._post(self.stranger_client)
        self.assertFalse(Review.objects.get(user=self.stranger).is_verified_purchase)

    # ── rating integrity ──
    def test_rating_counts_approved_reviews_only(self):
        self._post(self.buyer_client, rating=5)
        self._post(self.stranger_client, rating=1)   # pending spam
        self.product.refresh_from_db()
        self.assertEqual(self.product.review_count, 1)
        self.assertEqual(float(self.product.rating), 5.0)

    def test_approving_a_held_review_moves_the_rating(self):
        self._post(self.buyer_client, rating=5)
        self._post(self.stranger_client, rating=1)
        review = Review.objects.get(user=self.stranger)
        r = self.staff.post(f"/api/v1/admin/reviews/{review.id}/moderate",
                            {"decision": "approve"}, format="json")
        self.assertEqual(r.status_code, 200, r.json())
        self.product.refresh_from_db()
        self.assertEqual(self.product.review_count, 2)
        self.assertEqual(float(self.product.rating), 3.0)

    def test_rejecting_pulls_it_out_of_the_rating_but_keeps_the_row(self):
        self._post(self.buyer_client, rating=5)
        review = Review.objects.get(user=self.buyer)
        self.staff.post(f"/api/v1/admin/reviews/{review.id}/moderate",
                        {"decision": "reject", "reason": "Abusive language"},
                        format="json")
        self.product.refresh_from_db()
        self.assertEqual(self.product.review_count, 0)
        self.assertEqual(self._public()["reviews"], [])
        # Kept for audit, not deleted.
        review.refresh_from_db()
        self.assertEqual(review.status, Review.Status.REJECTED)
        self.assertEqual(review.moderation_reason, "Abusive language")
        self.assertEqual(review.moderated_by_id, self.admin.id)

    # ── edit re-moderation ──
    def test_editing_an_approved_review_re_runs_moderation_for_the_unverified(self):
        """Otherwise a stranger gets benign text approved, then swaps in abuse."""
        self._post(self.stranger_client, body="fine")
        review = Review.objects.get(user=self.stranger)
        self.staff.post(f"/api/v1/admin/reviews/{review.id}/moderate",
                        {"decision": "approve"}, format="json")
        self._post(self.stranger_client, body="now abusive")
        review.refresh_from_db()
        self.assertEqual(review.status, Review.Status.PENDING)
        self.assertEqual(review.moderation_reason, "")

    # ── moderation queue + access ──
    def test_queue_shows_pending_first_and_defaults_to_pending(self):
        self._post(self.buyer_client)          # approved
        self._post(self.stranger_client)       # pending
        rows = _data(self.staff.get("/api/v1/admin/reviews"))
        self.assertEqual([r["authorName"] for r in rows], ["Stranger"])

    def test_queue_can_show_all(self):
        self._post(self.buyer_client)
        self._post(self.stranger_client)
        rows = _data(self.staff.get("/api/v1/admin/reviews?status=all"))
        self.assertEqual(len(rows), 2)

    def test_rejecting_requires_a_reason(self):
        self._post(self.stranger_client)
        review = Review.objects.get(user=self.stranger)
        r = self.staff.post(f"/api/v1/admin/reviews/{review.id}/moderate",
                            {"decision": "reject"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_an_invalid_decision_is_refused(self):
        self._post(self.stranger_client)
        review = Review.objects.get(user=self.stranger)
        r = self.staff.post(f"/api/v1/admin/reviews/{review.id}/moderate",
                            {"decision": "delete"}, format="json")
        self.assertEqual(r.status_code, 400)

    def test_customers_cannot_moderate(self):
        self._post(self.stranger_client)
        review = Review.objects.get(user=self.stranger)
        r = self.buyer_client.post(f"/api/v1/admin/reviews/{review.id}/moderate",
                                   {"decision": "approve"}, format="json")
        self.assertEqual(r.status_code, 403)
        self.assertEqual(self.buyer_client.get("/api/v1/admin/reviews").status_code,
                         403)

    def test_a_customer_can_see_their_own_pending_review(self):
        """It must not look like the review silently vanished."""
        self._post(self.stranger_client)
        rows = _data(self.stranger_client.get("/api/v1/reviews/mine"))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["status"], "pending")
