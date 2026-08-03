"""Actionable responses, driven by the catalog (core.response_codes).

Failures:   raise AppError("KYC_REQUIRED")                 # anywhere in a view/service
            raise AppError("LIMIT_EXCEEDED", entity_type="order", entity_id=o.id)
            raise AppError("VALIDATION_ERROR", fields={"phone": ["Required"]})

Successes:  return Response(ok("ORDER_ACCEPTED", data=serializer.data), status=201)

The exception handler (core.exceptions) renders the full envelope and writes the
audit trail; the renderer passes structured bodies through untouched.
"""
from .response_codes import CATALOG


class AppError(Exception):
    """A catalog-coded, actionable error. Overrides default to the catalog spec."""

    def __init__(self, code, *, message=None, title=None, action=None,
                 next_step=None, http=None, severity=None, retryable=None,
                 entity_type="", entity_id="", fields=None, context=None):
        spec = CATALOG.get(code)
        if spec is None:  # unknown code — degrade safely but keep the trail honest
            code, spec = "SYSTEM_ERROR", CATALOG["SYSTEM_ERROR"]
        self.code = code
        self.spec = spec
        self.message = message or spec["message"]
        self.title = title or spec["title"]
        self.action = action if action is not None else spec["action"]
        self.next_step = next_step if next_step is not None else spec["next_step"]
        self.http = http or spec["http"]
        self.severity = severity or spec["severity"]
        self.retryable = spec["retryable"] if retryable is None else retryable
        self.entity_type = entity_type
        self.entity_id = entity_id
        self.fields = fields or {}
        self.context = context or {}
        super().__init__(self.message)


def error_body(code, *, message=None, title=None, action=None, next_step=None,
               severity=None, retryable=None, fields=None):
    """Build the full failure envelope for `code`. Returns (body, http_status)."""
    if code not in CATALOG:
        code = "SYSTEM_ERROR"
    spec = CATALOG[code]
    msg = message or spec["message"]
    body = {
        "success": False,
        "code": code,
        "title": title or spec["title"],
        "message": msg,
        "action": action if action is not None else spec["action"],
        "retryable": spec["retryable"] if retryable is None else retryable,
        "severity": severity or spec["severity"],
        "next_step": next_step if next_step is not None else spec["next_step"],
        # Back-compat: older clients still read error.{code,message,fields}.
        "error": {"code": code, "message": msg, "fields": fields or {}},
    }
    return body, spec["http"]


def ok(code, *, data=None, message=None, title=None, next_step=None, meta=None):
    """Build a success-coded response body (carries a code so the client can show a
    confirmation toast / route onward). Pass the result to DRF's Response()."""
    spec = CATALOG.get(code, {})
    body = {
        "success": True,
        "code": code,
        "title": title or spec.get("title", ""),
        "message": message or spec.get("message", ""),
        "severity": spec.get("severity", "success"),
        "next_step": next_step if next_step is not None else spec.get("next_step", ""),
        "data": {} if data is None else data,
    }
    if meta is not None:
        body["meta"] = meta
    return body
