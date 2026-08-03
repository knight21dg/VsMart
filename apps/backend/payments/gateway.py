"""Payment-gateway abstraction. A `manual`/mock provider lets the whole payment
flow run and be tested without live keys; swap in Razorpay by implementing the
same two methods and verifying the webhook signature."""
import hashlib
import hmac
import logging
import uuid

from core import runtime_settings as runtime

logger = logging.getLogger(__name__)


class MockGateway:
    """Dev/CI stand-in so the whole payment flow runs without live keys.

    It trusts everything, which is only acceptable because it can never be
    selected when real keys are configured (see :func:`get_gateway`) and its
    trusting paths additionally refuse to run unless the settings module opts in
    via ``PAYMENTS_TRUST_MOCK_GATEWAY`` (see :meth:`_trusted`).
    """

    name = "manual"

    def create_order(self, amount, *, receipt):
        return {"gateway_order_id": f"mock_{uuid.uuid4().hex[:16]}", "amount": str(amount)}

    def _trusted(self) -> bool:
        """Whether this deployment lets the mock accept unsigned callbacks.

        Belt-and-braces against the mock ever being reached in production: an
        unauthenticated webhook endpoint whose signature check returns True
        unconditionally would let anyone mark any order paid.

        Keyed off an explicit settings flag rather than ``DEBUG`` because Django's
        test runner forces ``DEBUG=False`` — so DEBUG says nothing about whether
        this is a real deployment. ``dev.py`` sets it True, ``prod.py`` False.
        Defaults to False when unset: an environment that hasn't opted in is
        treated as production.
        """
        from django.conf import settings

        return bool(getattr(settings, "PAYMENTS_TRUST_MOCK_GATEWAY", False))

    def verify_webhook(self, body: bytes, signature: str) -> bool:
        return self._trusted()

    def verify_checkout_signature(self, order_id, payment_id, signature) -> bool:
        return self._trusted()

    def fetch_order_payment(self, gateway_order_id):
        """No hosted page in mock mode, so there is nothing to reconcile."""
        return None

    def create_payment_link(self, amount, *, reference, description="",
                            customer_phone="", customer_name=""):
        """Mock counter payment link.

        Returned as already `paid` ONLY where the mock is trusted (dev/CI), so a
        keyless environment can run the POS flow end to end. In an untrusted
        environment it stays pending and can never self-settle a real sale.
        """
        link_id = f"mock_plink_{uuid.uuid4().hex[:12]}"
        return {
            "link_id": link_id,
            "short_url": f"https://example.invalid/pay/{link_id}",
            "status": "paid" if self._trusted() else "created",
            "amount": str(amount),
        }

    def fetch_payment_link(self, link_id):
        return {"link_id": link_id,
                "status": "paid" if self._trusted() else "created",
                "payment_id": f"mock_pay_{uuid.uuid4().hex[:10]}"
                if self._trusted() else ""}

    def cancel_payment_link(self, link_id):
        return {"link_id": link_id, "status": "cancelled"}

    def refund(self, gateway_payment_id, amount):
        return {"refund_id": f"mock_rfnd_{uuid.uuid4().hex[:12]}", "amount": str(amount)}


class RazorpayGateway:
    """Live Razorpay. Activates automatically once RAZORPAY_KEY_ID / _SECRET are set
    (needs `pip install razorpay`). Webhook signatures are HMAC-SHA256 over the RAW
    body with RAZORPAY_WEBHOOK_SECRET — verified before any state change."""

    name = "razorpay"

    def __init__(self):
        import razorpay  # imported lazily so dev never needs the SDK

        self._client = razorpay.Client(
            auth=(runtime.cfg("razorpay_key_id"), runtime.cfg("razorpay_key_secret"))
        )

    def create_order(self, amount, *, receipt):
        from decimal import Decimal

        order = self._client.order.create({
            "amount": int(Decimal(str(amount)) * 100),  # paise
            "currency": "INR",
            "receipt": receipt,
            "payment_capture": 1,
        })
        return {"gateway_order_id": order["id"], "amount": str(amount)}

    def verify_webhook(self, body: bytes, signature: str) -> bool:
        secret = runtime.cfg("razorpay_webhook_secret")
        if not secret:
            return False
        expected = hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature or "")

    def verify_checkout_signature(self, order_id, payment_id, signature) -> bool:
        """Verify the Razorpay Checkout handshake: HMAC-SHA256 of ``order_id|payment_id``
        with the API secret (this is how the client-side success callback is trusted,
        distinct from the webhook signature over the raw body)."""
        secret = runtime.cfg("razorpay_key_secret")
        if not secret or not (order_id and payment_id and signature):
            return False
        expected = hmac.new(
            secret.encode(), f"{order_id}|{payment_id}".encode(), hashlib.sha256
        ).hexdigest()
        return hmac.compare_digest(expected, signature)

    def fetch_order_payment(self, gateway_order_id):
        """Ask Razorpay what actually happened to an order we created.

        The recovery path for a payment that was captured but never reported: the
        app was killed before the SDK callback fired AND the webhook didn't land.
        Without this there was no way to learn the money had arrived, so the
        expiry job cancelled the order while the customer had been charged.

        Returns ``{"gateway_payment_id", "status", "amount"}`` for the most
        relevant payment on that order, or None if there is none.
        """
        from decimal import Decimal

        payments = (self._client.order.payments(gateway_order_id) or {}).get("items", [])
        if not payments:
            return None
        # A captured payment settles the order; otherwise report the latest attempt.
        captured = next((p for p in payments if p.get("status") == "captured"), None)
        chosen = captured or payments[-1]
        return {
            "gateway_payment_id": chosen.get("id", ""),
            "status": chosen.get("status", ""),
            "amount": Decimal(str(chosen.get("amount", 0))) / Decimal("100"),
        }

    def create_payment_link(self, amount, *, reference, description="",
                            customer_phone="", customer_name=""):
        """A Razorpay Payment Link for an over-the-counter sale.

        The POS has no card terminal, so the cashier shows this link (as a QR or
        SMS) and the customer pays from their own phone. The POS then polls
        :meth:`fetch_payment_link` until Razorpay reports it paid — the sale is
        never marked paid on the cashier's say-so.
        """
        from decimal import Decimal

        payload = {
            "amount": int(Decimal(str(amount)) * 100),  # paise
            "currency": "INR",
            "accept_partial": False,
            "description": description or f"VS Mart sale {reference}",
            "reference_id": str(reference),
            "notify": {"sms": bool(customer_phone), "email": False},
            "reminder_enable": False,
        }
        if customer_phone or customer_name:
            payload["customer"] = {
                k: v for k, v in
                (("contact", customer_phone), ("name", customer_name)) if v
            }
        link = self._client.payment_link.create(payload)
        return {
            "link_id": link.get("id", ""),
            "short_url": link.get("short_url", ""),
            "status": link.get("status", "created"),
            "amount": str(amount),
        }

    def fetch_payment_link(self, link_id):
        """Current state of a payment link — the authority on whether the
        customer actually paid."""
        link = self._client.payment_link.fetch(link_id)
        payments = link.get("payments") or []
        captured = next(
            (p for p in payments if p.get("status") in ("captured", "paid")), None
        )
        return {
            "link_id": link.get("id", link_id),
            "status": link.get("status", "created"),
            "payment_id": (captured or {}).get("payment_id", "")
            or (captured or {}).get("id", ""),
        }

    def cancel_payment_link(self, link_id):
        """Cancel an unpaid payment link so an abandoned hand-over can't be paid
        later against a deposit we've already released."""
        link = self._client.payment_link.cancel(link_id)
        return {"link_id": link.get("id", link_id),
                "status": link.get("status", "cancelled")}

    def refund(self, gateway_payment_id, amount):
        """Issue a refund against a captured payment via Razorpay's refund API.
        Returns the gateway refund id."""
        from decimal import Decimal

        r = self._client.payment.refund(
            gateway_payment_id, {"amount": int(Decimal(str(amount)) * 100)}  # paise
        )
        return {"refund_id": r.get("id", ""), "amount": str(amount)}


# Public key id the mobile Razorpay SDK uses to open checkout. Mirrors the
# mock-gateway fallback: when no real key is configured we return a harmless mock
# id ('rzp_test_mock') so the app side always has a non-null value to work with.
MOCK_KEY_ID = "rzp_test_mock"


def get_public_key_id() -> str:
    """The Razorpay public key id for the client SDK (settings/env), or a mock
    value when none is configured. Never returns the secret."""
    return runtime.cfg("razorpay_key_id") or MOCK_KEY_ID


def get_gateway():
    """Real Razorpay when keys are configured; the mock otherwise (so dev/CI run
    end-to-end with no keys).

    FAILS CLOSED. This used to swallow any exception from ``RazorpayGateway()`` and
    return the mock — so a deploy missing the ``razorpay`` SDK silently downgraded
    a live, key-configured environment to a gateway that treats every webhook
    signature as valid. The webhook endpoint is unauthenticated by design, so that
    turned a packaging mistake into "anyone can mark any order paid", with nothing
    logged and ``signature_ok=True`` recorded in the audit trail.

    Configured keys mean money is real: if the real gateway can't be constructed,
    raise and let the request 500 rather than process it insecurely.
    """
    if runtime.cfg("razorpay_key_id") and runtime.cfg("razorpay_key_secret"):
        try:
            return RazorpayGateway()
        except Exception:
            logger.exception(
                "Razorpay keys are configured but the gateway could not be "
                "constructed (is the `razorpay` SDK installed?). Refusing to fall "
                "back to the mock gateway."
            )
            raise
    return MockGateway()
