from django.db import models

from core.models import TimeStampedModel


class State(TimeStampedModel):
    name = models.CharField(max_length=80)
    code = models.CharField(max_length=20, unique=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class District(TimeStampedModel):
    state = models.ForeignKey(
        State, on_delete=models.CASCADE, related_name="districts"
    )
    name = models.CharField(max_length=80)
    code = models.CharField(max_length=20)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class GeoZone(TimeStampedModel):
    district = models.ForeignKey(
        District, on_delete=models.CASCADE, related_name="zones"
    )
    name = models.CharField(max_length=80)
    code = models.CharField(max_length=20)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Area(TimeStampedModel):
    zone = models.ForeignKey(
        GeoZone, on_delete=models.CASCADE, related_name="areas"
    )
    name = models.CharField(max_length=80)
    code = models.CharField(max_length=20, db_index=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Village(TimeStampedModel):
    area = models.ForeignKey(
        Area, on_delete=models.CASCADE, related_name="villages"
    )
    name = models.CharField(max_length=80)
    code = models.CharField(max_length=20)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Warehouse(TimeStampedModel):
    name = models.CharField(max_length=120)
    code = models.CharField(max_length=20, unique=True)
    area = models.ForeignKey(
        Area,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="warehouses",
    )
    latitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True
    )
    longitude = models.DecimalField(
        max_digits=9, decimal_places=6, null=True, blank=True
    )
    serviceable_pincodes = models.JSONField(default=list, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name
