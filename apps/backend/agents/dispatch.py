"""Shared "is this agent free right now" logic for every task-assignment path
(delivery batching, collections auto-assign, field verification) — so a new
task always prefers an idle agent over piling onto someone already working,
and only falls back to a busy agent when nobody is free, picking whoever will
finish soonest rather than whoever merely scores best on distance/rating.

No live-traffic or turn-by-turn ETA feed exists yet (same caveat as the
delivery scoring engine), so "soonest" is approximated as stop count × a
fixed average minutes-per-stop — an honest, explainable estimate rather than
a fabricated precise ETA.
"""
AVG_MINUTES_PER_STOP = 12


def _active_stop_count(agent) -> int:
    """Delivery tasks + collections + field-verification visits this agent
    hasn't finished yet, across every module they can be assigned in."""
    from delivery.models import DeliveryTask
    from payments.models import CashCollection
    from verification.models import VerificationTask

    deliveries = DeliveryTask.objects.filter(agent=agent).exclude(
        status__in=DeliveryTask.TERMINAL
    ).count()
    collections = CashCollection.objects.filter(agent=agent).exclude(
        status__in=CashCollection.TERMINAL
    ).count()
    verifications = VerificationTask.objects.filter(
        agent=agent,
        status__in=["assigned", "in_progress"],
    ).count()
    return deliveries + collections + verifications


def estimated_minutes_remaining(agent):
    """None when the agent is FREE (no active work at all); otherwise a rough
    minutes-until-clear estimate for their current workload."""
    stops = _active_stop_count(agent)
    return None if stops == 0 else stops * AVG_MINUTES_PER_STOP


def rank_for_new_task(candidates):
    """Split `candidates` into (free_agents, busy_agents_by_soonest) — free
    agents are unordered (the caller's own scoring picks among them), busy
    agents are ordered soonest-to-finish first, for use only when no agent is
    free."""
    free, busy = [], []
    for a in candidates:
        eta = estimated_minutes_remaining(a)
        if eta is None:
            free.append(a)
        else:
            busy.append((a, eta))
    busy.sort(key=lambda pair: pair[1])
    return free, [a for a, _eta in busy]
