"""drf-spectacular hooks so the generated OpenAPI reflects the actual response
envelope: success → {success, message, data, meta}; error → {success, message, error}."""


def _success_envelope(inner_schema):
    return {
        "type": "object",
        "properties": {
            "success": {"type": "boolean", "example": True},
            "message": {"type": "string", "example": ""},
            "data": inner_schema if inner_schema is not None else {"type": "object"},
            "meta": {"type": "object", "nullable": True},
        },
        "required": ["success", "data"],
    }


_ERROR_ENVELOPE = {
    "type": "object",
    "properties": {
        "success": {"type": "boolean", "example": False},
        "message": {"type": "string"},
        "error": {
            "type": "object",
            "properties": {
                "code": {"type": "string"},
                "message": {"type": "string"},
                "fields": {"type": "object"},
            },
        },
    },
    "required": ["success", "error"],
}


def envelope_responses(result, generator, request, public):
    """Wrap every operation's JSON response schema in the VS Mart envelope."""
    for methods in result.get("paths", {}).values():
        for operation in methods.values():
            if not isinstance(operation, dict):
                continue
            for code, response in (operation.get("responses") or {}).items():
                content = (response.get("content") or {}).get("application/json")
                if not content:
                    continue
                inner = content.get("schema")
                code_str = str(code)
                if code_str.startswith(("2",)):
                    content["schema"] = _success_envelope(inner)
                elif code_str.startswith(("4", "5")):
                    content["schema"] = _ERROR_ENVELOPE
    return result
