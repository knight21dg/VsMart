"""Store-scoped RBAC for the Store-Admin panel.

Every ``/store/*`` view runs through :class:`IsStoreStaff`, which:

1. resolves the caller's active ``StoreStaff`` membership (and rejects users
   without one — so the panel can never be used by a customer / network admin
   who isn't actually employed at a store), then
2. attaches ``request.membership`` and ``request.store`` for the view, and
3. enforces the view's declared permission (``store_permission`` for a single
   key, or ``store_permissions = {"read": ..., "write": ...}`` for method-split).

The store is *always* taken from the membership — never from a request param —
so a store user is structurally unable to read or mutate another store's data.
"""
from rest_framework.permissions import SAFE_METHODS, BasePermission


def get_membership(user):
    """The caller's active membership at an active store, or None."""
    if not (user and user.is_authenticated):
        return None
    from .models import StoreStaff

    return (
        StoreStaff.objects.select_related("store", "store__warehouse")
        .filter(user=user, is_active=True, store__status="active")
        .first()
    )


class IsStoreStaff(BasePermission):
    """Authenticated store employee, optionally holding a specific permission."""

    message = "You don't have access to this part of the store panel."

    def has_permission(self, request, view):
        membership = get_membership(request.user)
        if membership is None:
            return False
        # Expose for the view.
        request.membership = membership
        request.store = membership.store

        needed = self._needed(request, view)
        if needed and not membership.has_perm(needed):
            return False
        return True

    @staticmethod
    def _needed(request, view):
        perms = getattr(view, "store_permissions", None)
        if isinstance(perms, dict):
            if request.method in SAFE_METHODS:
                return perms.get("read")
            return perms.get("write")
        return getattr(view, "store_permission", None)


class StoreScopedMixin:
    """Convenience base: store-staff gate + handy accessors. View classes set
    ``store_permission`` (str) or ``store_permissions`` (dict)."""

    permission_classes = [IsStoreStaff]

    @property
    def membership(self):
        return self.request.membership

    @property
    def store(self):
        return self.request.store

    @property
    def warehouse_id(self):
        return self.request.store.warehouse_id
