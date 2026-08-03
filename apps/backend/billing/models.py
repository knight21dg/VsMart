from decimal import Decimal

from django.conf import settings
from django.db import models

from core.models import TimeStampedModel
from orders.models import Order
from payments.models import Payment

ZERO = Decimal("0.00")


class Invoice(TimeStampedModel):
    class Status(models.TextChoices):
        DRAFT = "draft"
        ISSUED = "issued"
        PAID = "paid"

    number = models.CharField(max_length=20, unique=True, blank=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="invoices"
    )
    order = models.ForeignKey(
        Order, on_delete=models.SET_NULL, null=True, blank=True
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    gst = models.DecimalField(max_digits=12, decimal_places=2, default=ZERO)
    status = models.CharField(
        max_length=10, choices=Status.choices, default=Status.ISSUED
    )
    issued_at = models.DateTimeField(null=True, blank=True)
    pdf_key = models.CharField(max_length=200, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Invoice({self.number or self.pk}) {self.amount} {self.status}"

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.number:
            self.number = f"INV{10000 + self.pk}"
            super().save(update_fields=["number"])


class InvoiceItem(models.Model):
    invoice = models.ForeignKey(
        Invoice, on_delete=models.CASCADE, related_name="items"
    )
    name = models.CharField(max_length=160)
    quantity = models.PositiveIntegerField()
    price = models.DecimalField(max_digits=12, decimal_places=2)


class Receipt(TimeStampedModel):
    number = models.CharField(max_length=20, unique=True, blank=True)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.PROTECT, related_name="receipts"
    )
    payment = models.ForeignKey(
        Payment, on_delete=models.SET_NULL, null=True, blank=True
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    method = models.CharField(max_length=12, blank=True)
    issued_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"Receipt({self.number or self.pk}) {self.amount}"

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.number:
            self.number = f"RCP{10000 + self.pk}"
            super().save(update_fields=["number"])
