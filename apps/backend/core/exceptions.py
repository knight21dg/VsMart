"""DRF exception handler — turns every error into the actionable envelope:

    {success, code, title, message, action, retryable, severity, next_step,
     error:{code, message, fields}}

AppError -> its catalog spec verbatim. DRF/framework exceptions -> mapped to a
catalog code. Each failure also writes the audit trail.
"""
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

from .app_errors import AppError, error_body
from .audit import write_audit
from .response_codes import CATALOG

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

    # 2) Framework exceptions — let DRF classify, then map to a catalog code.
    response = drf_exception_handler(exc, context)
    if response is None:
        # Truly unhandled (a 500) — never leak a stack trace to the client.
        spec = CATALOG["SYSTEM_ERROR"]
        body, _ = error_body("SYSTEM_ERROR")
        write_audit("SYSTEM_ERROR", spec, request, success=False, message=str(exc))
        return Response(body, status=500)

    default_code = str(getattr(exc, "default_code", "") or "")
    code = (_BY_DEFAULT_CODE.get(default_code)
            or _BY_STATUS.get(response.status_code) or "SYSTEM_ERROR")
    message, fields = _extract(response.data)
    body, _ = error_body(code, message=message, fields=fields)
    write_audit(code, CATALOG[code], request, success=False, fields=fields,
                message=message or CATALOG[code]["message"])
    response.data = body  # keep DRF's status_code (accurate to the original error)
    return response
