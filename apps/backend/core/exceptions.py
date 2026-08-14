"""DRF exception handler — turns every error into the actionable envelope:

    {success, code, title, message, action, retryable, severity, next_step,
     error:{code, message, fields}}

AppError -> its catalog spec verbatim. DRF/framework exceptions -> mapped to a
catalog code. Each failure also writes the audit trail.
"""
import logging

from django.db import IntegrityError
from django.db.models import ProtectedError, RestrictedError
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from .app_errors import AppError, error_body
from .audit import write_audit
from .response_codes import CATALOG

logger = logging.getLogger("vsmart.api")

# Map DRF's `default_code` (most specific) and then the HTTP status to a catalog code.
_BY_DEFAULT_CODE = {
    "not_authenticated": "AUTH_REQUIRED",
    "authentication_failed": "SESSION_EXPIRED",
    "token_not_valid": "SESSION_EXPIRED",
    "permission_denied": "INSUFFICIENT_PERMISSIONS",
    "throttled": "TOO_MANY_REQUESTS",
    "not_found": "NOT_FOUND",
    "method_not_allowed": "VALIDATION_ERROR",
    "parse_error": "VALIDATION_ERROR",
}
_BY_STATUS = {
    400: "VALIDATION_ERROR", 401: "AUTH_REQUIRED", 403: "INSUFFICIENT_PERMISSIONS",
    404: "NOT_FOUND", 405: "VALIDATION_ERROR", 409: "CONFLICT", 429: "TOO_MANY_REQUESTS",
}


def _extract(detail):
    """Pull (message, fields) out of a DRF error detail."""
    fields, message = {}, None
    if isinstance(detail, dict):
        if "detail" in detail:
            message = str(detail["detail"])
        else:
            fields = {
                k: (v if isinstance(v, list) else [str(v)]) for k, v in detail.items()
            }
    elif isinstance(detail, list):
        message = "; ".join(str(d) for d in detail)
    elif detail is not None:
        message = str(detail)
    return message, fields


def _dependents(exc):
    """Human list of what is blocking a PROTECT/RESTRICT delete, e.g.
    "3 orders, 1 product". Model verbose names keep it in the operator's
    vocabulary rather than exposing table names."""
    objs = getattr(exc, "protected_objects", None) or getattr(exc, "restricted_objects", None) or ()
    counts = {}
    for obj in objs:
        meta = obj._meta
        counts[str(meta.verbose_name)] = counts.get(str(meta.verbose_name), 0) + 1
    if not counts:
        return ""
    parts = [
        f"{n} {name if n == 1 else str(obj_meta_plural(name))}"
        for name, n in sorted(counts.items(), key=lambda kv: -kv[1])
    ]
    return ", ".join(parts[:4])


def obj_meta_plural(name):
    """Naive pluraliser for a verbose name — good enough for a message."""
    if name.endswith(("s", "x", "z", "ch", "sh")):
        return f"{name}es"
    if name.endswith("y") and not name.endswith(("ay", "ey", "iy", "oy", "uy")):
        return f"{name[:-1]}ies"
    return f"{name}s"


def _is_inventory_error(exc):
    """Is this an `inventory.services.InventoryError`?

    Imported lazily inside the function: `core` sits below `inventory`, so a
    module-level import would invert the dependency and risk a cycle at startup.
    """
    try:
        from inventory.services import InventoryError
    except Exception:  # noqa: BLE001 — app not loaded / not installed
        return False
    return isinstance(exc, InventoryError)


def _log_failure(request, code, status, exc=None, message=""):
    """Structured server-side breadcrumb for a failed mutation.

    Deliberately carries no credentials: never the body (it may hold a password
    or an OTP), never the Authorization header, never a token. Identity is the
    user id + role, which is enough to trace the actor.
    """
    user = getattr(request, "user", None)
    # A 4xx is the API working: the client asked for something invalid and was
    # told so. Logging those at WARNING buries the 5xx that actually need
    # attention (and floods the test runner), so they go to INFO.
    log = logger.error if status >= 500 else logger.info
    log(
        "api_failure code=%s status=%s method=%s path=%s user=%s role=%s exc=%s msg=%s",
        code,
        status,
        getattr(request, "method", "?"),
        getattr(request, "path", "?"),
        getattr(user, "id", None) if getattr(user, "is_authenticated", False) else None,
        getattr(user, "role", None) if getattr(user, "is_authenticated", False) else None,
        type(exc).__name__ if exc is not None else "",
        message,
        # Pass the exception object, not True — the handler is also called
        # outside an `except` block (tests, background paths), where `True`
        # resolves to no active exception and logs a bare "NoneType: None".
        exc_info=exc if (status >= 500 and exc is not None) else None,
    )


def api_exception_handler(exc, context):
    request = (context or {}).get("request") if isinstance(context, dict) else None

    # 1) Our own catalog-coded errors — render the spec verbatim.
    if isinstance(exc, AppError):
        body, _ = error_body(
            exc.code, message=exc.message, title=exc.title, action=exc.action,
            next_step=exc.next_step, severity=exc.severity, retryable=exc.retryable,
            fields=exc.fields,
        )
        write_audit(exc.code, exc.spec, request, success=False,
                    entity_type=exc.entity_type, entity_id=exc.entity_id,
                    fields=exc.fields, context=exc.context, message=exc.message)
        return Response(body, status=exc.http)

    # 2) Database integrity failures. These are NOT DRF exceptions, so without
    #    this branch they reached the client as a bare 500 "we hit a temporary
    #    problem" — hiding the one thing the operator needed to know: the delete
    #    was refused because the record is still referenced, or the value they
    #    typed is already taken. Both are 409s with a real explanation.
    if isinstance(exc, (ProtectedError, RestrictedError)):
        blockers = _dependents(exc)
        message = (
            f"This record can't be deleted because {blockers} still depend on it."
            if blockers
            else CATALOG["RECORD_IN_USE"]["message"]
        )
        body, status_code = error_body("RECORD_IN_USE", message=message)
        write_audit("RECORD_IN_USE", CATALOG["RECORD_IN_USE"], request, success=False,
                    message=message)
        _log_failure(request, "RECORD_IN_USE", status_code, exc, message)
        return Response(body, status=status_code)

    # Inventory guards. `InventoryError` is a plain Exception raised all through
    # `inventory.services` (oversell, a pack-less movement on a product sold by
    # pack, an adjustment below zero). It is not a DRF exception, so every one of
    # them rendered as a 500 "We hit a temporary problem on our end." — hiding a
    # message that was already exactly what the operator needed to read.
    if _is_inventory_error(exc):
        message = str(exc) or CATALOG["INVENTORY_RULE"]["message"]
        body, status_code = error_body("INVENTORY_RULE", message=message)
        write_audit("INVENTORY_RULE", CATALOG["INVENTORY_RULE"], request,
                    success=False, message=message)
        _log_failure(request, "INVENTORY_RULE", status_code, exc, message)
        return Response(body, status=status_code)

    if isinstance(exc, IntegrityError):
        detail = str(exc).lower()
        is_dupe = "unique" in detail or "duplicate" in detail
        code = "DUPLICATE_RECORD" if is_dupe else "SYSTEM_ERROR"
        body, status_code = error_body(code)
        write_audit(code, CATALOG[code], request, success=False, message=str(exc))
        _log_failure(request, code, status_code, exc, str(exc))
        return Response(body, status=status_code)

    # 3) Framework exceptions — let DRF classify, then map to a catalog code.
    response = drf_exception_handler(exc, context)
    if response is None:
        # Truly unhandled (a 500) — never leak a stack trace to the client.
        spec = CATALOG["SYSTEM_ERROR"]
        body, _ = error_body("SYSTEM_ERROR")
        write_audit("SYSTEM_ERROR", spec, request, success=False, message=str(exc))
        _log_failure(request, "SYSTEM_ERROR", 500, exc, str(exc))
        return Response(body, status=500)

    default_code = str(getattr(exc, "default_code", "") or "")
    code = (_BY_DEFAULT_CODE.get(default_code)
            or _BY_STATUS.get(response.status_code) or "SYSTEM_ERROR")
    message, fields = _extract(response.data)
    body, _ = error_body(code, message=message, fields=fields)
    write_audit(code, CATALOG[code], request, success=False, fields=fields,
                message=message or CATALOG[code]["message"])
    _log_failure(request, code, response.status_code, exc,
                 message or CATALOG[code]["message"])
    response.data = body  # keep DRF's status_code (accurate to the original error)
    return response
