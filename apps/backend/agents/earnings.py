"""The single definition of what an agent has earned.

There were two competing formulas. `agents/views.py` (what the AGENT sees in their
app) read the real `DeliveryEarnings` ledger and then added `collections × ₹30`.
`reports/accounting_views.py` (what FINANCE sees) used neither — it invented
`deliveries × ₹20 + collections × ₹30` over all time. The two could not agree, and
a disagreement about pay between the earner's screen and the payer's screen is the
kind that ends up in an argument nobody can settle from the data.

Both now call this module.

Two semantics matter here and were previously conflated:

**Accrued vs paid.** `DeliveryEarnings.released` looks like a paid flag, and the
first pass of the accounting rewrite read it as one — "payable = unreleased". It
isn't. `delivery/services.py::compute_earnings` writes `released=True,
released_at=now` at the moment of delivery, and *nothing in the codebase ever sets
it back to False or records a payout*. So `released` marks an earning as accrued
and confirmed, not as money handed over, and "payable = unreleased" was
structurally always ₹0 — an unknown rendered as a zero, which is the exact failure
this audit exists to catch.

Until an actual payout ledger exists, what has been paid is **not knowable from the
data**, so this module reports it as unknown rather than guessing in either
direction.

**Collection pay.** ₹30 per collection was a bare constant in a view with no
config, no ledger row, and no per-collection record. It is kept — removing it would
silently cut what agents are shown, which is a business decision and not mine — but
it is now declared here as a named, overridable rate and applied identically to
both surfaces. Delivery pay is already config-driven the same way
(`DELIVERY_BASE_FEE` and friends in `delivery/services.py`).
"""
from decimal import Decimal

from django.conf import settings
from django.db.models import Count, Sum

ZERO = Decimal("0.00")

#: Flat pay per completed cash collection. Unlike delivery pay there is no
#: per-collection earnings row to read, so this is a rate rather than a ledger.
#: Overridable via settings so it stops being a magic number in a view.
COLLECTION_FEE_DEFAULT = Decimal("30")

#: Flip to True when a real agent payout/disbursement ledger exists. Until then
#: `paid` and `payable` are reported as unknown rather than as zero.
PAYOUTS_ARE_TRACKED = False


def collection_fee() -> Decimal:
    return Decimal(str(getattr(settings, "COLLECTION_BASE_FEE", COLLECTION_FEE_DEFAULT)))


def _collections_qs(agent=None):
    from payments.models import CashCollection

    qs = CashCollection.objects.filter(status="collected")
    return qs.filter(agent=agent) if agent is not None else qs


def breakdown(agent):
    """What one agent has earned. Amounts are ACCRUED, not paid."""
    from delivery.models import DeliveryEarnings

    delivery = (
        DeliveryEarnings.objects.filter(agent=agent).aggregate(s=Sum("total"))["s"]
        or ZERO
    )
    deliveries = DeliveryEarnings.objects.filter(agent=agent).count()
    collections = _collections_qs(agent).count()
    collection_pay = collections * collection_fee()

    from .models import AgentIncentive

    incentives = (
        AgentIncentive.objects.filter(agent=agent).aggregate(s=Sum("amount"))["s"]
        or ZERO
    )
    base = delivery + collection_pay
    return {
        "deliveries": deliveries,
        "collections": collections,
        "deliveryPay": delivery,
        "collectionPay": collection_pay,
        "base": base,
        "incentives": incentives,
        "total": base + incentives,
    }


def breakdown_all():
    """`{agent_id: breakdown}` for every agent with any earning activity.

    Grouped queries rather than per-agent loops — the settlements view used to run
    three queries inside a loop over every agent on the platform.
    """
    from delivery.models import DeliveryEarnings

    from .models import AgentIncentive

    out = {}

    def bucket(aid):
        return out.setdefault(aid, {
            "deliveries": 0, "collections": 0, "deliveryPay": ZERO,
            "collectionPay": ZERO, "incentives": ZERO,
        })

    for r in DeliveryEarnings.objects.values("agent_id").annotate(
        s=Sum("total"), n=Count("id")
    ):
        b = bucket(r["agent_id"])
        b["deliveryPay"] = r["s"] or ZERO
        b["deliveries"] = r["n"]

    fee = collection_fee()
    for r in _collections_qs().values("agent_id").annotate(n=Count("id")):
        b = bucket(r["agent_id"])
        b["collections"] = r["n"]
        b["collectionPay"] = r["n"] * fee

    for r in AgentIncentive.objects.values("agent_id").annotate(s=Sum("amount")):
        bucket(r["agent_id"])["incentives"] = r["s"] or ZERO

    for b in out.values():
        b["base"] = b["deliveryPay"] + b["collectionPay"]
        b["total"] = b["base"] + b["incentives"]
    out.pop(None, None)  # earnings/collections with no agent attached
    return out
