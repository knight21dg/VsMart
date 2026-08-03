"""In-app 2FA for POS **credit** sales.

Before a store can bill a customer's VS Credit at the counter, the customer must
confirm: the cashier requests a code → a push (via ``notify``) tells the customer
to open the app → the app shows a 6-digit code → the customer reads it to the
cashier → the cashier enters it → the sale clears. Mirrors the collection-OTP
consent pattern but is cache-backed and bound to the exact amount (no replay).
"""
import secrets
from decimal import Decimal

from django.core.cache import cache

TTL = 300  # seconds the code stays valid
MAX_ATTEMPTS = 3
_PREFIX = "pos_credit_otp:"


def _key(customer_id) -> str:
    return f"{_PREFIX}{customer_id}"


def issue(customer, amount, store) -> None:
    """Generate a code for (customer, amount) and push a 'confirm in the app' prompt.
    The code itself is NOT in the push — the customer reads it from the app."""
    code = f"{secrets.randbelow(10 ** 6):06d}"
    cache.set(
        _key(customer.id),
        {"code": code, "amount": str(amount), "attempts": 0, "store": store.name},
        TTL,
    )
    from notifications.services import notify

    notify(
        customer,
        type="credit",
        title=f"Confirm ₹{amount} on VS Credit",
        body=f"{store.name} wants to bill ₹{amount} to your VS Credit. "
             f"Open the app to see your confirmation code.",
        data={
            "kind": "pos_credit_confirm",
            "amount": str(amount),
            "store": store.name,
            "route": "credit-confirm",
        },
    )


def pending_for(customer):
    """The customer's live confirmation (code + amount), for the in-app screen."""
    v = cache.get(_key(customer.id))
    if not v:
        return None
    return {"code": v["code"], "amount": v["amount"], "store": v.get("store")}


def verify(customer, code, amount):
    """Check a code against the pending confirmation for (customer, amount).

    Returns ``(ok, error_message)``. Consumes the code on success; locks the code
    after ``MAX_ATTEMPTS`` wrong tries (the customer must request a new one)."""
    v = cache.get(_key(customer.id))
    if not v:
        return False, "No pending confirmation — ask the customer to request a code."
    if v.get("locked"):
        return False, "Too many wrong attempts — request a new code."
    if Decimal(v["amount"]) != Decimal(str(amount)):
        return False, "The bill amount changed — request a new confirmation code."
    if str(code).strip() == v["code"]:
        cache.delete(_key(customer.id))
        return True, None
    v["attempts"] = v.get("attempts", 0) + 1
    if v["attempts"] >= MAX_ATTEMPTS:
        v["locked"] = True
    cache.set(_key(customer.id), v, TTL)
    return False, "Incorrect code."
