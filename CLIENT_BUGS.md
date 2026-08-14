# Client-Side Bug Audit

Sweep of all five VS Mart client surfaces — 2026-08-11.

**Scope audited:** 91 web routes (52 admin, 29 store, 10 landing) + 110 Flutter screens
(79 user_app, 31 agent_app) = **201 routes/screens**; **145 web write paths**
(80 admin, 65 store); 101 `useApiMutation` call sites; 22 `ConfirmDialog` usages;
288 Flutter `setState` calls.

This follows the API/read-contract sweep (109 admin + 51 store endpoints), which is
recorded separately. That pass established the read layer was essentially clean, so
this one deliberately targets **state, write paths, interactions and outcome
reporting** instead.

---

## Critical

None found. No data-corruption, wrong-authorization, wrong-financial-persistence or
cross-store-leak defect survived this sweep.

---

## High

### BUG-001 — POS till close discards the cash variance
- **Surface:** Store console
- **Route:** `/pos` → "Close till"
- **Action:** Count the drawer → Close till
- **Expected:** The variance against expected cash is shown, as the dialog explicitly
  promises ("The variance against expected cash is shown after closing").
- **Actual:** A "Till closed" toast and nothing else. The till screen reset straight to
  "Open till". The variance was never displayed anywhere in the panel.
- **Root cause:** `/store/pos/session/close` answers with a complete day closing —
  `expectedCash`, `countedCash`, `variance`, `totalSales`, the four-way tender split and
  `transactionCount` (`storeops/pos_views.py:140-150`). The client typed the mutation as
  `{ variance, totalSales }` and then ignored the value anyway: `onDone` closed the dialog
  and invalidated the session query, which unmounted the component. Pattern K — correct
  API response, no UI mapping.
- **Why it matters:** This is the one number the counting exercise exists to produce. A
  short drawer has to be visible at the till while the cashier is still standing there,
  not discovered later in a report.
- **Fix:** Hold the response in state and render a closing summary — variance first, as
  "₹250.00 short" / "₹250.00 over" / "Balanced" rather than a signed number that reads
  ambiguously at a till — then expected vs counted and the tender split. The session is
  only invalidated once the cashier acknowledges, because invalidating immediately is what
  unmounted the summary. The count dialog is also no longer dismissible mid-request.
- **Files:** `apps/store-admin/components/pos/close-session.tsx` (extracted from
  `app/(console)/pos/page.tsx` so it can be tested without dragging in the offline
  database and scanner audio), `app/(console)/pos/page.tsx`
- **Test:** `apps/store-admin/test/close-session.test.tsx` — 7 tests. Verified: 5 fail
  against the pre-fix `onDone`, all 7 pass after.
- **Status:** Fixed

---

## Medium

### BUG-002 — Deleting the last row on a page strands the operator on an empty page
- **Surface:** Admin console + Store console (all 13 paginated tables)
- **Route:** every `DataTable` with page-based pagination
- **Action:** Delete the last remaining row on page N (N > 1)
- **Expected:** The table falls back to the last page that still has rows.
- **Actual:** "Page 5 of 4" over "No records found." Next is disabled at that point
  (`page >= totalPages`), so the row just deleted appeared to have taken the entire table
  with it. Recovery required noticing the Prev arrow.
- **Root cause:** The page number lives in the calling page's state; the total lives in the
  response. Nothing reconciled the two, so any shrink behind a stationary cursor stranded
  the view. Delete was only the most obvious trigger — a narrowing filter or another
  operator working the same list did it too.
- **Fix:** Clamp inside `DataTable` rather than in each of the 13 pages, so every cause is
  covered at once and no page has to remember. Guarded on `loading` — mid-flight the
  previous page's meta is still mounted and an unguarded clamp would undo the operator's
  own page click.
- **Files:** `apps/admin/components/data-table.tsx`,
  `apps/store-admin/components/data-table.tsx`
- **Test:** `apps/admin/test/data-table-pagination.test.tsx`,
  `apps/store-admin/test/data-table-pagination.test.tsx`. Verified: the two clamp tests
  fail with the clamp removed, pass with it.
- **Status:** Fixed

### BUG-003 — Row-click guard had no regression test
- **Surface:** Admin console + Store console
- **Root cause:** The guard that stops a clickable row swallowing its own action buttons
  (the original zone-delete failure) was added in the previous session with no client-side
  test. An untested guard on a bug that has already shipped once is a regression waiting
  to happen — this is the defect class with the worst track record in this codebase.
- **Fix:** No behaviour change; added the missing coverage.
- **Files:** `apps/admin/test/data-table-row-click.test.tsx`
- **Test:** 3 tests — row click fires the row handler; a row action button does **not**
  also fire it; links and checkboxes inside a row are left alone.
- **Status:** Fixed (coverage gap closed)

---

## Low

### BUG-004 — Optimistic writes fail silently in the customer app
- **Surface:** Customer Flutter app
- **Routes:** wishlist toggle/remove/clear, notification mark-read / mark-all-read
- **Actual:** State is updated locally and the request is fired without awaiting the
  result; `catch (_) {}` drops any failure. A failed "mark all read" leaves the badge
  cleared while the server still holds them unread, until the next hydrate silently
  reverts it.
- **Assessment:** Deliberate offline-tolerant design (the wishlist one is commented "will
  reconcile on next hydrate") on genuinely low-stakes state — no money, no order state.
  **Not changed**: making these blocking or toast-on-failure would be a UX regression on a
  heart icon, and the reconcile path already exists.
- **Files:** `user_app/lib/features/wishlist/presentation/providers/wishlist_providers.dart:49,61,71`,
  `user_app/lib/features/notifications/presentation/providers/notification_providers.dart:39,49`
- **Status:** Accepted, documented

### BUG-005 — 14 Flutter `setState` calls after `await` without a `mounted` guard
- **Surface:** Customer app (10), Agent app (4)
- **Actual:** If the screen is disposed while the request is in flight, `setState` throws.
  In every case checked the throw lands in an enclosing `catch` whose handlers are
  themselves `mounted`-guarded, so the net effect is a swallowed exception rather than a
  crash or a wrong render.
- **Assessment:** Real but benign; no user-visible symptom. **Not changed** — touching 14
  call sites across two apps for no observable defect is churn, and the surrounding code
  already demonstrates the authors' awareness (`finally { if (mounted) … }`).
- **Files:** listed in the sweep output; notably
  `agent_app/lib/features/auth/login_screen.dart:61`,
  `agent_app/lib/features/deliveries/presentation/batch_route_screen.dart:66`,
  `user_app/lib/features/kyc/presentation/screens/credit_kyc_screen.dart:84,89,95`
- **Status:** Accepted, documented

---

## Verified clean (checked, no defect)

These were audited against the listed bug patterns and found correct. Recording them so
the next sweep doesn't re-walk the same ground.

| Area | Checked | Result |
|---|---|---|
| Dead UI | empty handlers, `TODO`, `FIXME`, "coming soon", `alert()`, `location.reload()` | **Zero** across all five surfaces. The two "coming soon" cases render as non-clickable spans with a badge — the correct intentional-unavailable state. |
| Loading states | 27 manual `set*(true)` flags | 22 use `finally`. The 5 that don't are auth flows that navigate away on success — a `finally` there would re-enable the button mid-navigation. Correct as written. |
| Cache invalidation | 101 `useApiMutation` sites | Every site either invalidates or has nothing cached to invalidate (push send, password change) or invalidates via `onDone`. No stale-after-write found. |
| Double submit | 22 `ConfirmDialog` usages | 21 pass `loading`; the 22nd is a purely local cart clear with no request. `ConfirmDialog` disables both buttons while pending. |
| False success | `useApiMutation` | `onSuccess` fires only after the promise resolves. No toast-before-await anywhere. |
| Delete vs deactivate | all delete call sites, both panels | Honest. 5 admin sites use `api.delWithMessage` and echo the server's coded outcome; the rest hardcode a message that matches what the backend actually does — `/admin/catalog/products` archives and says "Product archived", `/admin/catalog/categories` really deletes (`instance.delete()`) and says "Category deleted". |
| Store panel outcome messages | 39 `successMessage` strings | All accurate, including the compound claims — `process_return` really does post the stock movement **and** the refund, so "Return recorded — stock and refund posted" is true. |
| Null into NOT NULL | store form, offer form, product form | No repeat of the zone bug. Every field these forms null out (`latitude`, `longitude`, `opensAt`, `closesAt`, `dailyOrderCapacity`, `discountPercent`, `dealPrice`) is `null=True` on the model. |
| Filter → page reset | 13 paginated pages | 12 reset to page 1 on filter change; the 13th (procurement) has no filters. |
| Empty vs loading vs error | `DataTable` | Correctly ordered — skeletons while loading, `ErrorState` on error, empty message only when genuinely empty. Never shows "No data" mid-request. |
| Swallowed errors (web) | `catch {}` | None in the panels. The API client converts transport failures and every HTTP status into human text and preserves field-level backend messages, which are surfaced in preference to the generic status line. |

---

## Remaining known gaps

Stated plainly rather than left implied:

1. **The two Flutter apps were audited by code inspection, not on a device.** Lifecycle
   items that need a real handset — background/resume, notification tap routing while
   terminated, keyboard-covers-button, slow-network behaviour — are not verifiable from
   here and remain untested.
2. **No end-to-end cross-panel run was executed** (admin creates product → store stocks →
   customer orders → agent delivers). It needs all four surfaces live against one dataset;
   the per-surface write paths were traced individually instead.
3. **Responsive breakpoints were not visually verified.** No functional defect was found in
   the markup, but tablet/small-laptop rendering was not exercised in a browser.
4. **BUG-004 and BUG-005 are documented, not fixed** — for the reasons given above. Both
   are recorded so the decision is reviewable rather than silent.
