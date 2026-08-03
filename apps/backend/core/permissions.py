from rest_framework.permissions import BasePermission, SAFE_METHODS


class _RolePermission(BasePermission):
    role = None

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and user.role == self.role)


class IsCustomer(_RolePermission):
    role = "customer"


class IsAgent(_RolePermission):
    role = "agent"


class IsAdmin(BasePermission):
    """Admin or superadmin."""

    def has_permission(self, request, view):
        user = request.user
        return bool(
            user and user.is_authenticated and user.role in ("admin", "superadmin")
        )


class IsSuperAdmin(_RolePermission):
    role = "superadmin"


class IsCashier(BasePermission):
    """POS operator — store staff. Today that's admin/superadmin (managers run the
    till); widen to a dedicated `cashier` Django group here without touching views."""

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        return user.role in ("admin", "superadmin") or user.groups.filter(
            name="cashier"
        ).exists()


class IsOwner(BasePermission):
    """Object-level: the row belongs to request.user (via `user` or `user_id`)."""

    owner_field = "user"

    def has_object_permission(self, request, view, obj):
        owner = getattr(obj, self.owner_field, None)
        return owner == request.user


class IsOwnerOrStaff(IsOwner):
    def has_object_permission(self, request, view, obj):
        if request.user.is_authenticated and request.user.role in (
            "admin",
            "superadmin",
        ):
            return True
        return super().has_object_permission(request, view, obj)


class ReadOnly(BasePermission):
    def has_permission(self, request, view):
        return request.method in SAFE_METHODS
