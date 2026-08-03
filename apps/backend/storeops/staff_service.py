"""Store staff lifecycle: hire, edit role/permissions, deactivate, attendance.

Creating staff provisions (or adopts) a phone-login User with role
``store_staff`` and attaches a :class:`StoreStaff` membership. The Store Admin
(manager) assigns the exact permission set for ``custom`` staff. We never hard
delete — deactivation flips ``is_active`` so audit history is preserved.
"""
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import validate_email
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from accounts.models import Role, User
from accounts.services import record_audit

from .models import StaffAttendance, StoreStaff
from .permissions_catalog import (
    PERMISSION_GROUPS,
    ROLE_DEFAULT_PERMISSIONS,
    clean_permissions,
    default_permissions_for,
)


def staff_row(staff: StoreStaff) -> dict:
    u = staff.user
    today = timezone.localdate()
    att = staff.attendance.filter(date=today).first()
    return {
        "id": str(staff.id),
        "userId": str(u.id),
        "name": u.name or u.phone,
        "phone": u.phone,
        "email": u.email or None,
        "staffRole": staff.staff_role,
        "staffRoleLabel": staff.get_staff_role_display(),
        "title": staff.title or staff.get_staff_role_display(),
        "employeeCode": staff.employee_code,
        "isManager": staff.is_manager,
        "isActive": staff.is_active,
        "joinedOn": staff.joined_on,
        "permissions": staff.effective_permissions(),
        "permissionCount": len(staff.effective_permissions()),
        "presentToday": bool(att and att.check_in_at),
        "checkInAt": att.check_in_at if att else None,
        "checkOutAt": att.check_out_at if att else None,
        "createdAt": staff.created_at,
    }


def list_staff(store):
    qs = store.staff.select_related("user").prefetch_related("attendance")
    return [staff_row(s) for s in qs]


def _normalize_role(staff_role: str) -> str:
    valid = {c.value for c in StoreStaff.StaffRole}
    if staff_role not in valid:
        raise ValidationError({"staffRole": ["Unknown staff role."]})
    return staff_role


def create_staff(store, *, actor=None, phone, name="", staff_role="cashier",
                 permissions=None, title="", employee_code="", joined_on=None,
                 email="", password=""):
    """Add a staff member to ``store`` AND give them a working login.

    The panel authenticates with email + password (`/store/auth/login`), but this
    used to create a phone-only ``User`` with neither — so the row appeared, the
    toast said success, and the person could never sign in. Credentials are now
    required whenever the account being created or adopted can't already log in;
    an existing account that already has a usable password keeps it.
    """
    phone = (phone or "").strip()
    name = (name or "").strip()
    email = (email or "").strip().lower()
    if not phone:
        raise ValidationError({"phone": ["Phone number is required."]})
    staff_role = _normalize_role(staff_role)

    def _require_credentials():
        if not email:
            raise ValidationError({"email": ["Email is required — staff sign in with it."]})
        try:
            validate_email(email)
        except DjangoValidationError:
            raise ValidationError({"email": ["Enter a valid email address."]})
        if not password or len(str(password)) < 8:
            raise ValidationError({"password": ["Password must be at least 8 characters."]})
        clash = User.objects.filter(email__iexact=email).exclude(phone=phone)
        if clash.exists():
            raise ValidationError({"email": ["This email already belongs to another account."]})

    user = User.objects.filter(phone=phone).first()
    if user is None:
        _require_credentials()
        user = User.objects.create(
            phone=phone, name=name, email=email, role=Role.STORE_STAFF)
        user.set_password(password)
        user.save(update_fields=["password"])
    else:
        if hasattr(user, "store_staff"):
            raise ValidationError(
                {"phone": ["This number is already a staff member of a store."]}
            )
        if user.role in (Role.ADMIN, Role.SUPERADMIN, Role.AGENT):
            raise ValidationError(
                {"phone": [f"This number belongs to a {user.get_role_display()} account."]}
            )
        # Adopt a plain customer number as store staff. A customer account signs
        # in by OTP and has no email/password, so it still needs credentials
        # before it can reach the panel.
        fields = ["role", "name"]
        if not user.email or not user.has_usable_password():
            _require_credentials()
            user.email = email
            user.set_password(password)
            fields += ["email", "password"]
        user.role = Role.STORE_STAFF
        if name and not user.name:
            user.name = name
        user.save(update_fields=fields)

    # Managers implicitly hold everything; for others, use the supplied set or the
    # role's default bundle.
    if staff_role == StoreStaff.StaffRole.MANAGER:
        perms = []
    elif permissions is not None:
        perms = clean_permissions(permissions)
    else:
        perms = default_permissions_for(staff_role)

    staff = StoreStaff.objects.create(
        store=store, user=user, staff_role=staff_role, permissions=perms,
        title=title.strip(), employee_code=employee_code.strip(),
        joined_on=joined_on or timezone.localdate(),
    )
    record_audit(actor, "store_staff.create", target=staff,
                 after={"phone": phone, "staffRole": staff_role, "permissions": perms})
    return staff


def update_staff(staff: StoreStaff, *, actor=None, staff_role=None, permissions=None,
                 title=None, employee_code=None, is_active=None, name=None):
    before = {
        "staffRole": staff.staff_role,
        "permissions": staff.permissions,
        "isActive": staff.is_active,
        "name": staff.user.name,
    }
    # The name lives on the User, not the membership. It was accepted by the API
    # and then dropped here, so editing a staff member's name changed nothing
    # while still reporting "Staff updated".
    if name is not None and name.strip() and name.strip() != staff.user.name:
        staff.user.name = name.strip()
        staff.user.save(update_fields=["name"])
    fields = []
    if staff_role is not None:
        staff.staff_role = _normalize_role(staff_role)
        fields.append("staff_role")
        # Switching INTO a non-manager role with no explicit perms → seed defaults.
        if permissions is None and staff.staff_role != StoreStaff.StaffRole.MANAGER and not staff.permissions:
            staff.permissions = default_permissions_for(staff.staff_role)
            fields.append("permissions")
    if permissions is not None:
        staff.permissions = clean_permissions(permissions)
        fields.append("permissions")
    if title is not None:
        staff.title = title.strip()
        fields.append("title")
    if employee_code is not None:
        staff.employee_code = employee_code.strip()
        fields.append("employee_code")
    if is_active is not None:
        staff.is_active = bool(is_active)
        fields.append("is_active")
    if fields:
        staff.save(update_fields=list(set(fields)) + ["updated_at"])
    record_audit(actor, "store_staff.update", target=staff, before=before,
                 after={"staffRole": staff.staff_role, "permissions": staff.permissions,
                        "isActive": staff.is_active, "name": staff.user.name})
    return staff


# ── Store Admin onboarding (Super-Admin) ─────────────────
def _synth_phone(store) -> str:
    """A guaranteed-unique sentinel phone for an email-login store admin who didn't
    supply a mobile number. Uses a non-dialable ``+99`` prefix so it can never collide
    with a real Indian (+91) customer number and can't be hijacked through OTP."""
    base = f"+9900{store.id:04d}"
    candidate, n = base, 0
    while User.objects.filter(phone=candidate).exists():
        n += 1
        candidate = f"{base}{n:02d}"[:15]
    return candidate


def onboard_store_admin(store, *, actor=None, email, password, name="", phone="",
                        title="Store Manager", employee_code=""):
    """Super-Admin onboards (or re-credentials) a store's admin — an email+password
    login bound to a **manager**-role :class:`StoreStaff` membership for THIS store.
    Managers implicitly hold every store permission. Idempotent per email: re-running
    resets the password/name and (re)activates the manager membership for the store.

    Security: rejects emails that belong to a super-admin / admin / agent account, and
    a person already employed at a DIFFERENT store. The membership is the ONLY thing
    that scopes the panel, so a store admin can never reach another store's data."""
    from accounts.serializers import normalize_phone

    email = (email or "").strip().lower()
    name = (name or "").strip()
    if not email:
        raise ValidationError({"email": ["Email is required."]})
    try:
        validate_email(email)
    except DjangoValidationError:
        raise ValidationError({"email": ["Enter a valid email address."]})
    if not password or len(str(password)) < 8:
        raise ValidationError({"password": ["Password must be at least 8 characters."]})

    user = User.objects.filter(email__iexact=email).first()

    # A supplied mobile number must not already belong to a different person.
    norm_phone = ""
    if phone and str(phone).strip():
        try:
            norm_phone = normalize_phone(phone)
        except Exception:
            raise ValidationError({"phone": ["Enter a valid mobile number."]})
        clash = User.objects.filter(phone=norm_phone)
        if user is not None:
            clash = clash.exclude(pk=user.pk)
        if clash.exists():
            raise ValidationError(
                {"phone": ["This mobile number already belongs to another account."]}
            )

    if user is None:
        user = User.objects.create(
            phone=norm_phone or _synth_phone(store),
            email=email, name=name, role=Role.STORE_STAFF,
        )
        user.set_password(password)
        user.save()
    else:
        if user.role in (Role.SUPERADMIN, Role.ADMIN, Role.AGENT):
            raise ValidationError(
                {"email": [f"This email belongs to a {user.get_role_display()} account."]}
            )
        existing = getattr(user, "store_staff", None)
        if existing is not None and existing.store_id != store.id:
            raise ValidationError(
                {"email": ["This person is already staff at another store."]}
            )
        user.role = Role.STORE_STAFF
        if name:
            user.name = name
        if norm_phone:
            user.phone = norm_phone
        user.set_password(password)
        user.save()

    membership = getattr(user, "store_staff", None)
    if membership is None:
        membership = StoreStaff.objects.create(
            store=store, user=user, staff_role=StoreStaff.StaffRole.MANAGER,
            permissions=[], title=(title or "Store Manager").strip(),
            employee_code=(employee_code or "").strip(), joined_on=timezone.localdate(),
            is_active=True,
        )
    else:
        membership.store = store
        membership.staff_role = StoreStaff.StaffRole.MANAGER
        membership.is_active = True
        if title:
            membership.title = title.strip()
        if employee_code:
            membership.employee_code = employee_code.strip()
        membership.save(update_fields=["store", "staff_role", "is_active", "title",
                                       "employee_code", "updated_at"])
    record_audit(actor, "store_admin.onboard", target=membership,
                 after={"email": email, "store": store.code, "role": "manager"})
    return membership


def reset_store_admin_password(store, *, actor=None, email, password):
    """Super-Admin resets a store admin's password (manager at this store)."""
    email = (email or "").strip().lower()
    if not password or len(str(password)) < 8:
        raise ValidationError({"password": ["Password must be at least 8 characters."]})
    membership = (
        StoreStaff.objects.select_related("user")
        .filter(store=store, user__email__iexact=email,
                staff_role=StoreStaff.StaffRole.MANAGER)
        .first()
    )
    if membership is None:
        raise ValidationError({"email": ["No store admin with that email at this store."]})
    membership.user.set_password(password)
    membership.user.save(update_fields=["password"])
    record_audit(actor, "store_admin.reset_password", target=membership,
                 after={"email": email, "store": store.code})
    return membership


def list_store_admins(store) -> list:
    """The store's admin (manager) logins, for the Super-Admin store page."""
    qs = (
        store.staff.select_related("user")
        .filter(staff_role=StoreStaff.StaffRole.MANAGER)
        .order_by("-is_active", "-created_at")
    )
    return [
        {
            "id": str(s.id),
            "userId": str(s.user_id),
            "name": s.user.name or s.user.email or s.user.phone,
            "email": s.user.email or None,
            "phone": s.user.phone if not str(s.user.phone).startswith("+9900") else None,
            "title": s.title or "Store Manager",
            "isActive": s.is_active,
            "createdAt": s.created_at,
        }
        for s in qs
    ]


def permission_catalog() -> dict:
    """Catalog payload for the assign-permissions UI."""
    return {
        "groups": [
            {
                "module": g["module"],
                "permissions": [{"key": k, "label": label} for (k, label) in g["permissions"]],
            }
            for g in PERMISSION_GROUPS
        ],
        "roleDefaults": ROLE_DEFAULT_PERMISSIONS,
        "roles": [
            {"value": c.value, "label": c.label} for c in StoreStaff.StaffRole
        ],
    }


# ── Attendance ───────────────────────────────────────────
def check_in(staff: StoreStaff):
    today = timezone.localdate()
    att, _ = StaffAttendance.objects.get_or_create(staff=staff, date=today)
    if att.check_in_at is None:
        att.check_in_at = timezone.now()
        att.save(update_fields=["check_in_at", "updated_at"])
    return att


def check_out(staff: StoreStaff):
    today = timezone.localdate()
    att, _ = StaffAttendance.objects.get_or_create(staff=staff, date=today)
    att.check_out_at = timezone.now()
    if att.check_in_at is None:
        att.check_in_at = att.check_out_at
    att.save(update_fields=["check_in_at", "check_out_at", "updated_at"])
    return att


def attendance_roster(store):
    today = timezone.localdate()
    rows = []
    for s in store.staff.select_related("user").filter(is_active=True):
        att = s.attendance.filter(date=today).first()
        rows.append({
            "staffId": str(s.id),
            "name": s.user.name or s.user.phone,
            "staffRole": s.staff_role,
            "checkInAt": att.check_in_at if att else None,
            "checkOutAt": att.check_out_at if att else None,
            "present": bool(att and att.check_in_at),
        })
    return rows
