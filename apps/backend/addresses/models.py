from django.conf import settings
from django.db import models

from core.models import TimeStampedModel


class Address(TimeStampedModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="addresses"
    )
    label = models.CharField(max_length=30, blank=True)  # Home / Work
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=15)
    line1 = models.CharField(max_length=200)
    village = models.CharField(max_length=120, blank=True)
    area = models.CharField(max_length=120, blank=True)
    landmark = models.CharField(max_length=120, blank=True)
    city = models.CharField(max_length=80, blank=True)
    district = models.CharField(max_length=80, blank=True)
    state = models.CharField(max_length=80, blank=True)
    pincode = models.CharField(max_length=6, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    is_default = models.BooleanField(default=False)

    class Meta:
        ordering = ["-is_default", "-created_at"]

    def __str__(self):
        return f"{self.label or 'Address'} — {self.name}"

    @property
    def formatted(self):
        parts = [self.line1, self.village, self.area, self.landmark,
                 self.district or self.city, self.state, self.pincode]
        return ", ".join(p for p in parts if p)

    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if self.is_default:
            Address.objects.filter(user=self.user).exclude(pk=self.pk).update(
                is_default=False
            )
