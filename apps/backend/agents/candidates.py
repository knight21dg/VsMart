"""Who can be handed a new field task — the single source of truth.

Agents are store-owned (``AgentProfile.store``). A task that belongs to store A
must never be auto-assigned to store B's agent: the agent sees a job they can't
physically do, and the store that actually owns the work sees nothing on its
board. That is precisely how a freshly-raised task appears to "vanish" — it was
assigned, just to somebody on the other side of the city.

Assignment previously pooled every active agent platform-wide. Both the
collections engine and the returns-pickup engine now route through
``candidate_agents(store=...)`` instead.

Eligibility, in order:
  1. Agents of that store who are on duty (``is_available``).
  2. Store-less agents — no ``AgentProfile`` at all, or a profile with no store.
     These are legacy/unassigned agents and stay eligible for any store so an
     install that never filled in ``AgentProfile.store`` keeps working.

Agents belonging to a *different* store are never returned when a store is
given. When no store is known (legacy callers, unresolvable customer), the whole
on-duty pool is returned — the old behaviour.
"""
from django.core.exceptions import ObjectDoesNotExist


def agent_store(agent):
    """The store that owns this agent, or None for a legacy/store-less agent."""
    # agent_profile is a reverse OneToOne: it raises when absent, so getattr's
    # default won't catch it.
    try:
        profile = agent.agent_profile
    except (ObjectDoesNotExist, AttributeError):
        return None
    return getattr(profile, "store", None)


def on_duty_agents():
    """Every active agent currently eligible for work, ignoring store."""
    from accounts.models import AgentProfile, User

    agents = list(User.objects.filter(role="agent", is_active=True))
    available = set(
        AgentProfile.objects.filter(is_available=True).values_list("user_id", flat=True)
    )
    profiled = set(AgentProfile.objects.values_list("user_id", flat=True))
    # An agent with no profile has never had a duty toggle to switch on, so
    # excluding them would strand every task in a fresh install.
    return [a for a in agents if a.id in available or a.id not in profiled]


def candidate_agents(store=None):
    """On-duty agents eligible for a task belonging to ``store``.

    Returns ``[]`` when nobody is eligible — callers must handle that (leave the
    task unassigned and alert someone) rather than silently dropping the task.
    """
    pool = on_duty_agents()
    if store is None:
        return pool
    store_id = getattr(store, "id", store)
    scoped, storeless = [], []
    for a in pool:
        owner = agent_store(a)
        if owner is None:
            storeless.append(a)
        elif getattr(owner, "id", owner) == store_id:
            scoped.append(a)
    return scoped or storeless


def assignable_agents(store=None):
    """Agents a HUMAN may (re)assign a task to from a panel.

    Same store-boundary rule as ``candidate_agents`` (that store's agents, else
    the store-less legacy pool), minus the on-duty filter: someone picking a
    name may knowingly choose an agent who is about to start their shift, and
    the panel shows each row's duty state so the choice is informed.

    This is the ONE definition the store panel's agent picker and the reassign
    endpoints both read. When they were computed separately the endpoint
    accepted agents the picker never offered — and a picker is a convenience,
    not a control.
    """
    from accounts.models import User

    pool = list(User.objects.filter(role="agent", is_active=True))
    if store is None:
        return pool
    store_id = getattr(store, "id", store)
    scoped, storeless = [], []
    for a in pool:
        owner = agent_store(a)
        if owner is None:
            storeless.append(a)
        elif getattr(owner, "id", owner) == store_id:
            scoped.append(a)
    return scoped or storeless


def eligible_for_store(agent, store):
    """Whether ``agent`` may be handed a task belonging to ``store`` — the
    server-side guard behind every manual (re)assignment. Defined as membership
    of [assignable_agents], so it can never drift from what the picker shows."""
    if store is None:
        return True
    return any(a.id == agent.id for a in assignable_agents(store))


def unassignable_reason(store=None):
    """Why ``candidate_agents`` came back empty — for the alert sent to staff."""
    from accounts.models import User

    if not User.objects.filter(role="agent", is_active=True).exists():
        return "no_active_agents"
    if not on_duty_agents():
        return "no_agents_on_duty"
    if store is not None:
        return "no_agents_for_store"
    return "no_agents_available"
