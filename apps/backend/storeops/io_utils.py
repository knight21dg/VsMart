"""Request-field helpers.

The backend's camelCase parser converts incoming JSON bodies from camelCase to
snake_case, so a view that reads ``request.data["productId"]`` would miss the
parsed ``product_id`` key. ``field`` reads a value by its camelCase name while
tolerating the snake_case form, so views are robust either way.
"""
import re


def _snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def field(data, name, default=None):
    """Read ``name`` (camelCase) from a dict, falling back to its snake_case form."""
    if isinstance(data, dict):
        snake = _snake(name)
        if snake in data:
            return data[snake]
        if name in data:
            return data[name]
    return default


def present(data, name) -> bool:
    """Was ``name`` SENT at all (in either casing)?

    Distinguishes "the client omitted this field" from "the client sent null/empty
    to clear it" — a distinction ``field() is not None`` cannot make. Needed for
    PATCH semantics on nullable overrides, where writing a value the client never
    intended to set is a silent data change (e.g. pinning a store price override
    just because the payload echoed the resolved price back)."""
    if not isinstance(data, dict):
        return False
    return _snake(name) in data or name in data
