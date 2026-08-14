# VS Mart Agent App — Client QA & Delivery History Audit

Scope: `apps/agent_app` (Flutter) plus the backend contracts it depends on.
Method: full inventory → end-to-end trace of the delivered-order path → targeted
sweeps for the listed defect classes → fix at the shared layer → regression tests.

**Status: PASS**, with the remaining items stated explicitly at the end.

---

## Coverage

| | Count |
|---|---|
| Screens | 31 |
| Feature modules | 19 |
| Providers / notifiers | 10 |
| Data/repository layers | 14 |
| Mutating agent actions traced | 14 (accept, reject, pickup, out-for-delivery, reached, OTP, photo, deliver, fail, collect-cash, return, KYC submit, handover, attendance) |
| Backend contracts traced | `/deliveries/assigned`, `/deliveries/{id}`, `/agents/history`, `/agents/earnings`, `/agents/me` |

---

## The mandatory requirement — delivered orders of every type

**Result: already satisfied. No type-based filtering exists anywhere in the stack.**

I traced it end to end rather than assuming:

```
DeliveryTask (status only)
  → _delivery_qs()          filters on status__in only — no payment/type predicate
  → _delivery_row()         serialises regardless of order type
  → JSON
  → HistoryEntry.fromJson   no type branch; unknown values fall back, never drop
  → HistoryPage             no filtering
  → historyProvider         filters by KIND (delivery/collection/verification) only,
                            and that is passed to the server as `?type=`
  → history_screen          renders whatever the page contains
```

Searches for the suspected pattern found nothing to remove:

- `orderType` / `deliveryType` — **no occurrences in the app**
- `paymentMethod ==` — one occurrence, `delivery_detail_screen.dart:1021`, gating the
  *Collect Cash* button for COD. That is a correct capability check on a detail
  screen, not list filtering.
- No `.where(...)` anywhere filters an order list by status or type.

Rather than "fix" a non-bug, I locked the guarantee down with a matrix test across
**8 order shapes** — COD unpaid, COD paid, prepaid online, UPI, credit, discounted,
coupon, and zero-value — asserting each reaches history with `outcome=success`.

One behaviour worth knowing, and it is deliberate: a **delivered COD order whose cash
is not yet confirmed appears in BOTH the active queue and history.** The money is in
nobody's book yet, so it remains an open action while also being recorded. That is
pinned by its own test so nobody "tidies" it away.

---

## Bugs found

### BUG-A1 — A failed delivery stuck on the agent's queue forever and appeared in no history
- **Screen:** Deliveries (active list) + History
- **Action:** Report a failed delivery (`POST /deliveries/{id}/fail`)
- **Expected:** The attempt leaves the agent's active list and is recorded in their
  history as "Not completed".
- **Actual:** It stayed on the active list permanently — the agent could not clear it
  and had no way to act on it — and it appeared in **no** history at all, so there was
  no record they had ever attempted the delivery.
- **Root cause:** Three consumers each had their own idea of "done" and they
  disagreed:

  | Consumer | Excluded |
  |---|---|
  | `AssignedDeliveriesView` (the agent's queue) | `TERMINAL` |
  | `_agent_active_load` (assignment engine) | `TERMINAL \| {failed}` |
  | `_delivery_qs` (history) | included `TERMINAL` |

  `TERMINAL` omits `failed`, so a failed task was outside history and inside the
  queue — while the assignment engine, using the third definition, correctly treated
  it as not-load and kept assigning fresh work on top of it. The history module's own
  docstring claimed to be "the exact complement" of the queue; it wasn't.
- **Fix:** One definition on the model, used by all three:
  ```python
  TERMINAL         = {delivered, rejected, returned_to_store, reassigned, cancelled}
  CLOSED_FOR_AGENT = TERMINAL | {failed}   # left the AGENT's hands
  ```
  `failed` is closed *for the agent* — only the store can reschedule, reassign or
  return it — but not terminal for the *order*. Keeping the two sets separate says
  that precisely, instead of overloading one.
- **Files:** `delivery/models.py`, `delivery/views.py`, `delivery/services.py`,
  `agents/history_views.py`
- **Test:** `agents/test_agent_history_completeness.py::QueueAndHistoryAreComplementsTests`
  — verified 3 failures + 1 error against the old code.
- **Status:** Fixed

### BUG-A2 — `failed` had no outcome mapping
- **Root cause:** `_DELIVERY_OUTCOME` had no `failed` key. It only ever produced the
  right answer via `.get(status, FAILED)`, i.e. by accident of the default.
- **Fix:** mapped explicitly, so adding a status that should read *success* can't
  silently inherit *failed*.
- **Status:** Fixed

### BUG-A3 — No test covered the queue/history boundary
- **Root cause:** Both views were tested in isolation; nothing asserted they partition
  the status space. That is exactly how BUG-A1 survived.
- **Fix:** `test_no_status_falls_between_the_two_lists` enumerates
  `DeliveryTask.Status.values` and fails if any status is classified neither active
  nor closed — so a new status must be triaged, not defaulted.
- **Status:** Fixed

---

## Audited and found correct

These were checked against the brief's defect classes and needed no change. Recorded
so the next pass doesn't re-walk them.

| Area | Finding |
|---|---|
| **Shared mutation path** | Every delivery action funnels through one `_run()` wrapper: duplicate-tap guard (`if (_busy) return`), `finally` reset with a `mounted` check, toast **only** after success, and it invalidates *both* the detail and the list provider — so completion moves an order active→delivered with **no refresh**. It returns the error object rather than a nullable typed exception, after a past bug where a dropped connection read as success. |
| **Swallowed errors** | **Zero.** No `catch (_) {}`, no `catch (e) {}`, no `print(` anywhere in `lib/`. |
| **Technical strings leaking to agents** | None. `statusCode` appears only inside the error-mapping layer (`core/net_errors.dart`, `core/api_exception.dart`) which converts codes into sentences. |
| **OTP messaging** | Distinguishes invalid / expired / locked / network, each with its own wording and next step — the four-way distinction the brief requires. |
| **Crash risks** | All four `.first` / `[0]` sites are guarded: `_fitRoute` (`length < 2`), `_fitBounds` (`isEmpty`), `RouteMap.build` (early `SizedBox.shrink()`), and status/name initials (`isEmpty` ternary). |
| **Null-safe parsing** | `deliveries_data.dart` has typed `_num/_int/_double/_str/_bool/_doubleOrNull` helpers used throughout; nested `customer` handled via `is Map` check. No force-unwrap on API data. |
| **camelCase / snake_case** | Models read `j['camelKey'] ?? j['snake_key']` defensively. Auth endpoints deliberately serve snake via `SnakeEnvelopeJSONRenderer` — left alone, as instructed. |
| **Client-side money** | None. Earnings, cash-in-hand and collection totals are all server values. |
| **Status normalisation** | Statuses are compared against the backend's own vocabulary in one place per feature; history uses the backend's `outcome` bucket (`success`/`partial`/`failed`) so the app never has to know every status string. |

---

## Delivery-type matrix

Every row verified reaching Delivered history with `outcome=success`:

| Type | Payment | Active | Deliverable | In history |
|---|---|---|---|---|
| COD, cash not yet confirmed | `cod` / pending | ✅ (deliberate) | ✅ | ✅ |
| COD, cash confirmed | `cod` / paid | — | ✅ | ✅ |
| Prepaid online | `online` / paid | — | ✅ | ✅ |
| UPI | `upi` / paid | — | ✅ | ✅ |
| Credit | `credit` / pending | — | ✅ | ✅ |
| Discounted | `online` / paid | — | ✅ | ✅ |
| Coupon | `online` / paid | — | ✅ | ✅ |
| Zero-value | `online` / paid | — | ✅ | ✅ |

Types were taken from the backend's actual `Order.PaymentMethod` and order fields —
none invented.

---

## Tests added

`agents/test_agent_history_completeness.py` — **15 tests**:

- delivered history by type (8-type matrix, plus per-type outcome assertions)
- the deliberate delivered-COD-in-both-lists behaviour
- active statuses on the queue and absent from history
- closed statuses present in history
- **no status falls between the two lists** (enumerates the enum)
- a failed delivery leaves the queue and reads "Not completed"
- all three consumers agree
- pagination: 1 / exactly one page / page+1 / totals describe the whole set
- scoping: an agent never sees another agent's history; non-agents get 401/403

Backend suite: **1550 passing**.

---

## Remaining — stated plainly

1. **No device testing.** Everything here is code-level plus backend integration
   tests. The brief's lifecycle items — background/resume during an active delivery,
   notification tap routing while terminated, GPS permission dialogs, camera capture,
   keyboard-covers-button — cannot be verified from here and remain untested.
2. **No Flutter widget or integration tests added.** The app has no test harness
   (`flutter test` has no suite). Standing one up is worthwhile, but it is new
   infrastructure rather than a fix, and the defect found was server-side — a widget
   test would not have caught it. The 15 backend tests cover the actual bug and the
   mandatory guarantee.
3. **Offline behaviour** was previously audited (2026-08-04) and is not re-verified
   here; that pass found and fixed the "offline reported as SUCCESS" class.
4. **`rescheduled` and `return_initiated` remain active**, deliberately: both are
   in-flight states the agent still owns (a rescheduled task returns to `assigned`; a
   return-initiated task means the agent is carrying goods back).

---

## AGENT APP STATUS: **PASS**

Every visible action has a loading state, a duplicate-tap guard, an error path and a
success path; no swallowed errors; no unguarded crash sites; delivery completion
updates every affected list without a refresh; and **every supported order type that
reaches DELIVERED appears in the agent's history**, now enforced by test rather than
by assumption.
