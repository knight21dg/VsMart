from django.conf import settings
from django.db import models

from catalog.models import Product, ProductVariant
from core.models import TimeStampedModel


class Cart(TimeStampedModel):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="cart"
    )
    # The serving store the cart was built against (zone → store at add-time). Lets
    # checkout detect "the customer changed address into a different store's zone" and
    # refuse a Store-A cart → Store-B order. Null when store scoping is off.
    store = models.ForeignKey(
        "stores.Store", on_delete=models.SET_NULL, null=True, blank=True
    )

    def __str__(self):
        return f"Cart({self.user_id})"


class CartItem(TimeStampedModel):
    cart = models.ForeignKey(Cart, on_delete=models.CASCADE, related_name="items")
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    variant = models.ForeignKey(
        ProductVariant, on_delete=models.SET_NULL, null=True, blank=True
    )
    quantity = models.PositiveIntegerField(default=1)
    price_snapshot = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        unique_together = ("cart", "product", "variant")

    @property
    def line_total(self):
        return self.price_snapshot * self.quantity


class WishlistItem(TimeStampedModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="wishlist"
    )
    product = models.ForeignKey(Product, on_delete=models.CASCADE)

    class Meta:
        unique_together = ("user", "product")
