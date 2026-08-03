from django.conf import settings
from django.db import models

from core.models import TimeStampedModel

from .permissions_catalog import ALL_PERMISSIONS


class StoreStaff(TimeStampedModel):
    """A user's employment at one VS Mart store, with a role and a permission set.

    This is the single gate for the Store-Admin panel: a user may use the panel
    iff they have an active ``StoreStaff`` row whose store is active. The
    ``staff_role`` seeds a default permission bundle, but the effective access is
    the ``permissions`` list — except for ``manager`` (the Store Admin), who
    implicitly holds every permission regardless of the stored list.

    One user works at one store (a single panel login), so this is a OneToOne.
    """

    class StaffRole(models.TextChoices):
        MANAGER = "manager", "Store Manager (Admin)"
        CASHIER = "cashier", "Cashier (POS)"
        INVENTORY = "inventory", "Inventory Staff"
        DELIVERY_COORDINATOR = "delivery_coordinator", "Delivery Coordinator"
        CUSTOM = "custom", "Custom"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="store_staff",
    )
    store = models.ForeignKey(
        "stores.Store", on_delete=models.CASCADE, related_name="staff"
    )
    staff_role = models.CharField(
        max_length=24, choices=StaffRole.choices, default=StaffRole.CASHIER
    )
    permissions = models.JSONField(default=list, blank=True)
    title = models.CharField(max_length=80, blank=True)
    employee_code = models.CharField(max_length=40, blank=True)
    is_active = models.BooleanField(default=True)
    joined_on = models.DateField(null=True, blank=True)

    class Meta:
        ordering = ["store", "staff_role", "-created_at"]
        indexes = [models.Index(fields=["store", "is_active"])]

    def __str__(self):
        return f"{self.user} @ {self.store.code} ({self.staff_role})"

    @property
    def is_manager(self) -> bool:
        return self.staff_role == self.StaffRole.MANAGER

    def effective_permissions(self) -> list:
        """Every permission this staff member actually holds. Managers hold all."""
        if self.is_manager:
            return list(ALL_PERMISSIONS)
        return list(self.permissions or [])

    def has_perm(self, key: str) -> bool:
        if self.is_manager:
            return True
        perms = self.permissions or []
        return key in perms or "*" in perms


class StaffAttendance(TimeStampedModel):
    """Per-day check-in / check-out for a store staff member (spec §EMPLOYEES)."""

    staff = models.ForeignKey(
        StoreStaff, on_delete=models.CASCADE, related_name="attendance"
    )
    date = models.DateField(db_index=True)
    check_in_at = models.DateTimeField(null=True, blank=True)
    check_out_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ("staff", "date")
        ordering = ["-date"]

    def __str__(self):
        return f"{self.staff_id} · {self.date}"

    @property
    def is_present(self) -> bool:
        return self.check_in_at is not None


class POSDraft(TimeStampedModel):
    """A saved (parked) POS cart a cashier can resume later — the "Draft" button.

    Session-independent (survives till close/reopen) and store-scoped. ``payload``
    holds the cart snapshot the POS UI needs to rehydrate: items (productId,
    variantId, name, price, qty), the attached customer, and any coupon code.
    """

    store = models.ForeignKey(
        "stores.Store", on_delete=models.CASCADE, related_name="pos_drafts"
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True,
        related_name="pos_drafts",
    )
    label = models.CharField(max_length=80, blank=True)
    customer = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        related_name="pos_drafts_as_customer",
    )
    payload = models.JSONField(default=dict)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["store", "-created_at"])]

    def __str__(self):
        return f"Draft {self.id} · {self.store_id}"
