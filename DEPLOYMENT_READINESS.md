# VS Mart — Deployment Readiness

Status of every pre-deployment gate. A box is ticked **only** where I ran the
check and saw it pass in this environment. Anything I could not execute here is
marked **NOT VERIFIED** rather than assumed.

**Recommendation: CONDITIONAL GO** — see [Blockers](#deployment-blockers).
Backend, database and both consoles are ready. The two mobile apps are
**NOT VERIFIED** on hardware, which is the one gate no amount of automated
testing substitutes for.

---

## Test totals

| | Before this pass | After |
|---|---|---|
| Backend | 1343 | **1392** (+49) |
| Customer app | 171 | **178** (+7) |
| Agent app | analyze clean | analyze clean |

Every added test accounted for — 1343 + 16 + 26 + 7 = 1392:

| File | Tests | Covers |
|---|---|---|
| `catalog/test_gst_migration.py` | 16 | migration idempotency, no double-conversion, money untouched |
| `core/test_cross_tenant.py` | 26 | IDOR + role boundaries, called directly against the API |
| `delivery/test_otp_expiry.py` (added class) | 7 | expired ≠ invalid, attempt accounting, lockout not weakened |
| `user_app/test/core/push_invalidation_test.dart` | 7 | which order a foreground push refreshes |

No tests were removed or weakened. 4 remain skipped — see
[Skipped tests](#skipped-tests).

---

## DATABASE

- [x] **Snapshot completed** — dev DB copied before migrating; the same step is
      mandatory on production (see [Migration plan](#migration-plan)).
- [x] **Migrations reviewed** — all four, operation by operation.
- [x] **GST migration verified** — applied to real data, before/after diffed.
- [x] **Migration applied safely** — on the **dev** database. **NOT applied to
      production.**

### The four pending migrations

| Migration | Operations | Risk |
|---|---|---|
| `catalog.0010_product_gst_rate_as_percentage` | `AlterField` numeric(4,2)→(5,2); `RunPython` data rewrite | **Data transform** — reviewed below |
| `catalog.0011_homefeature_and_more` | `CreateModel` + 1 index + 1 unique constraint | None — new table only |
| `notifications.0003_notification_dedupe_key_and_more` | `AddField` (blank CharField) + partial unique constraint | None — backfills `""`, which the partial constraint excludes |
| `orders.0012_orderitem_gst_rate_as_percentage` | `RunPython` data rewrite | **Data transform** — added during this audit |

Nothing is destructive. No column or table is dropped, no field becomes
non-nullable, no enum is altered, no foreign key is added, changed or removed.

**Postgres note.** Production is `postgres:16-alpine`, so the partial unique
constraint (`condition=~Q(dedupe_key='')`) is fully supported — it would have
failed on MySQL. `AlterField` on the numeric precision takes an
`ACCESS EXCLUSIVE` lock on `catalog_product`; on a 108-row catalog that is
milliseconds, but it is a lock, so run it in the maintenance window.

### GST representation — the final contract

```
Operator types        18
Admin/Store UI        18 %          (slab dropdown; free-text decimal removed)
API request/response  18            (validated against GST_SLABS)
Product.gst_rate      18.00         ← migrated by catalog.0010
OrderItem.gst_rate    18.00         ← migrated by orders.0012
PlatformConfig        0.1800        ← stays a FRACTION, converted at the API edge
Pricing maths         0.18          ← core.pricing.gst_pct_to_fraction
Customer app          18 %
```

One rule, one place: `core/pricing.py`. `PlatformConfig` deliberately keeps the
fraction — it is the multiplier `compute_bill` and the POS tax split use — and
every API surface converts it (`/admin/config`, `/store/settings`,
`/app-config`). It is **not** touched by any migration.

### Double-conversion safety

Only `0 < value < 1` is scaled. No real GST rate falls in that open interval —
the lowest non-zero slab is 0.25 %, which as a fraction would be 0.0025 — so:

- a value already correct (`5`, `18`, `28`) is **left alone**;
- `0` and `NULL` are **left alone** (NULL means "use the platform default");
- a **second run changes nothing**;
- both migrations are **reversible**, with the reverse guarded the same way.

All 16 properties are asserted in `catalog/test_gst_migration.py`, including
that a migrated value is a legal slab (otherwise the next edit of that product
would fail validation on a field the operator never touched).

> **One judgement call to be aware of.** `orders.0012` repairs *historical order
> lines*. Those recorded `0.18` where 18 % was charged, because `place_order`
> copied the platform fraction into a column documented as a percentage. The
> money (`Order.gst`, `Order.total`) was always correct and is not touched — only
> the rate *label*. It is a separate migration precisely so you can skip it if
> you would rather leave history byte-identical; nothing reads the column today.

### Verified against real data

`scripts/verify_gst_migration.py` is read-only and safe to run on production.
Run it before and after, and diff. On the dev database:

```
 fraction_like (products)     1  ->  0
 histogram                 0.05  ->  5.00
 fraction_like (order lines) 24  ->  0
 histogram                 0.18  ->  18.00
 products_off_slab            1  ->  0
```

**Everything else was byte-identical** — row counts, NULL counts, zero counts,
`sum(price)`, `sum(mrp)`, `sum(stock)`, active count, distinct categories, and
every money total (`orders_sum_subtotal/gst/total/discount`,
`lines_sum_price/qty`). Indexes and constraints confirmed present afterwards; a
28 % write/read round-trip confirmed the widened column.

### Migration plan

1. `pg_dump` the production database. **Do not skip** — `catalog.0010` and
   `orders.0012` rewrite values in place.
2. `python scripts/verify_gst_migration.py > gst_before.txt`
   (set `DJANGO_SETTINGS_MODULE=config.settings.prod`).
3. `python manage.py migrate`
4. `python scripts/verify_gst_migration.py > gst_after.txt`
5. `diff gst_before.txt gst_after.txt` — expect **only** the five lines above to
   move. If any money total or row count changed, restore the dump.
6. Redeploy both consoles (the GST display change is client-side too).

**Rollback:** `python manage.py migrate catalog 0009 && python manage.py migrate
orders 0011 && python manage.py migrate notifications 0002`. The reverse
functions restore the fractions. If anything looks wrong beyond that, restore
the dump — it is the only rollback that is certain.

---

## BACKEND

- [x] **1392 tests passing** (target was 1343+)
- [x] `manage.py check` — no issues
- [x] `makemigrations --check` — no model drift
- [ ] **No skipped critical tests** — 4 skipped, see below
- [x] **API errors handled** — every failure renders the coded envelope;
      `ProtectedError`/`IntegrityError`/`CheckoutError` all map to real statuses
- [x] **Authorization verified** — see [RBAC](#rbac)
- [x] **Financial flows verified** — refund-on-reject, cash-handover
      reconciliation, GST snapshot, minimum order, coupon release

### Skipped tests

All 4 are FCM push-payload tests skipped with *"firebase-admin not installed
(prod-only dep)"*:

```
notifications.BroadcastImageTests.test_send_push_carries_no_image_without_one_explicitly_given
notifications.BroadcastImageTests.test_send_push_still_carries_an_explicit_image
notifications.UrgentAssignmentPushTests.test_ordinary_kind_still_sends_a_notification_block
notifications.UrgentAssignmentPushTests.test_urgent_kind_sends_no_notification_block
```

`firebase-admin==6.*` **is** in `requirements.txt`, so the Docker image has it
and these run there. They have **never run in this environment**. Run the suite
once inside the backend container before cutting over — they cover push payload
shape, and push is a shipped feature.

---

## RBAC

- [x] Role-by-role matrix built from the **actual URL resolver**, not by reading
      the UI
- [x] IDOR scenarios tested by calling the API directly with the wrong principal
- [x] **26/26 cross-tenant tests pass — no authorization holes found**

### Enforcement census — 603 DRF endpoints

| Enforced permission | Endpoints |
|---|---|
| `IsAdmin` | 169 |
| `IsAuthenticated` (explicit) | 125 |
| `IsStoreStaff` | 97 |
| default `IsAuthenticated` | 81 |
| `IsAgent` | 66 |
| `AllowAny` | 39 |
| `IsCashier` | 19 |
| `IsSuperAdmin` | 5 |
| `IsCustomer` | 2 |

The default is `IsAuthenticated`, so an unguarded view **fails closed** for
anonymous callers.

Static introspection flagged ~92 "privileged routes on `IsAuthenticated`". Every
one was inspected and every one is a false positive:

- **Django-admin `RedirectView`s** — `django.contrib.admin` routes, gated by the
  admin site's own `is_staff` session check, not DRF.
- **Dynamic `get_permissions()`** — `AdminStoreViewSet`, `AdminZoneViewSet`,
  `ConfigView`, `AdminStoreAdminView` and friends resolve permissions per
  method (read → `IsAdmin`, write → `IsSuperAdmin`). Correct, just invisible to
  a class-attribute scan.
- **`/credit/ledger`, `/loyalty/ledger`** — "my ledger" endpoints keyed on
  `request.user`; a supplied user id is ignored (tested).

### IDOR results

| Scenario | Result |
|---|---|
| Agent A reads / completes / OTP-verifies / fails Agent B's delivery | **denied** (4 tests) |
| Agent A accepts or collects Agent B's cash collection | **denied** (2 tests) |
| Agent A's task list leaks Agent B's work | **no leak** |
| Customer B reads / raises / lists Alice's return | **denied** (3 tests) |
| Customer decides a return (admin *or* store endpoint) | **denied** |
| Customer reads another customer's credit ledger via `?user=` | **no leak** |
| Customer reaches 9 admin + 4 store surfaces | **denied** (13 paths) |
| Customer edits a product price / deletes a store / moves the GST rate | **denied** |
| Agent reaches payments, cash deposits, trial balance, config | **denied** |
| Agent verifies **their own** cash deposit | **denied** |
| Agent releases their own collection OTP lockout | **denied** |
| Agent curates the customer home screen | **denied** |
| Store A reads B's cash-in-hand / opens B's return / decides B's return | **denied** (3 tests) |
| Store A adjusts B's private product stock | **denied** |
| Anonymous on 5 privileged surfaces | **401/403** |

Two of these initially "passed" for the wrong reason and were fixed — an invalid
`reasonCode` produced a 400 before ownership was ever consulted. That 400 would
have looked like a denial. The tests now send valid payloads so the request
actually reaches the authorization check.

### Public mutation endpoints — 254 API mutations, 15 unauthenticated

All 15 are intentionally pre-auth: the auth/OTP flows, account-deletion request
(Play compliance), `cart/quote` + `cart/validate` (**verified: no persistence**),
the analytics beacon, serviceability check/expansion, and the Razorpay webhook
(**HMAC-SHA256 verified over the raw body**). All inherit the global
`AnonRateThrottle` at 60/min; OTP endpoints are 5/min.

---

## ADMIN CONSOLE

- [x] CRUD verified — create/edit/delete tested via the API contract; delete now
      reports its real outcome (deleted vs deactivated)
- [x] RBAC verified — customer and agent denied on every admin surface
- [x] Returns verified — review dialog added (there was **no detail view at
      all**); evidence photos + settled quantities now reach the reviewer
- [x] Settings verified — GST slab validation, superadmin-only writes
- [x] Marketing / home management verified — 16 tests on curation + fallback
- [x] `tsc --noEmit` clean · `next build` clean
- [ ] **Click-tested in a browser — NOT VERIFIED**

## STORE PANEL

- [x] Orders verified — accept **and reject**, terminal actions confirmed
- [x] Inventory verified — store-scoped, cross-store write denied
- [x] Returns verified — evidence gallery added
- [x] Agent operations verified — cash page store-scoped, reassign flows
- [x] Financial operations verified — hand-over declaration must match claimed
      collections
- [x] `tsc --noEmit` clean · `next build` clean
- [ ] **Click-tested in a browser — NOT VERIFIED**

## CUSTOMER APP

- [x] Location verified *(code-level)* — the cascade is reactive:
      `locationScopeProvider` watches manual pin / selected address / live GPS /
      serviceability, and the catalog data source watches it, so a location
      change rebuilds zone → store → catalog. The SWR cache is namespaced by
      store, so one store's products can never be served for another.
- [x] Cart verified — 178 tests
- [x] Checkout verified
- [x] Minimum order verified — server-authoritative, measured on the subtotal
- [x] Coupon verified
- [x] Order tracking verified *(code-level)* — WebSocket with token refresh
      before every reconnect, 12s REST poll as fallback that **stops** on
      terminal states and on hard errors, pauses on background, catches up on
      resume. No aggressive polling added.
- [x] Returns verified
- [x] Notification state verified — **fixed this pass**: a foreground push only
      drew a banner and invalidated nothing, so an open order screen kept
      showing the old status. Now targeted invalidation of exactly the order the
      push concerns (7 tests).
- [x] `flutter analyze` clean · `flutter test` 178 passing · **APK builds**
- [ ] **Real-device state matrix — NOT VERIFIED**

## AGENT APP

- [x] Order lifecycle verified
- [x] OTP verified — minted at arrival, 3 attempts, lockout, completion guard
      requires REACHED + verified OTP + proof photo
- [x] OTP expiry verified — 15-min TTL, checked before comparison so expiry
      **cannot burn an attempt**; lockout rules unchanged
- [x] **Expired ≠ invalid** — distinct codes, messages and UI. Expired gets a
      persistent panel with a one-tap "Send a new code"; invalid keeps the
      attempts-left toast. 7 contract tests, including full recovery end to end.
- [x] KYC verified — agent self-KYC flow (was missing entirely)
- [x] Cash handover verified — under-declaration now refused
- [x] Returns verified
- [x] `flutter analyze` clean · **APK builds**
- [ ] **Device notifications — NOT VERIFIED**

## MOBILE

- [ ] **Real device test — NOT VERIFIED**
- [ ] **Background / resume — NOT VERIFIED** (code reviewed; lifecycle handling
      is present and correct)
- [ ] **Notification — NOT VERIFIED** (no device, no Firebase credentials here)
- [ ] **Camera — NOT VERIFIED**
- [ ] **Location — NOT VERIFIED** (Android runtime permission behaviour in
      particular; emulator behaviour is not evidence)
- [ ] **Maps — NOT VERIFIED** (also needs a Google Maps API key)
- [ ] **Network recovery — NOT VERIFIED**

I have no Android hardware in this environment. `flutter analyze`, `flutter
test` and a successful `assembleDebug` prove the code compiles and packages —
they prove nothing about permissions, push delivery, camera intents or GPS.

## DEPLOYMENT

- [x] **Environment variables checked** — compose requires `POSTGRES_DB`,
      `POSTGRES_USER`, `POSTGRES_PASSWORD`, `ADMIN_API_BASE_URL`, `ACME_EMAIL`.
      No new variable is introduced by this work. `DELIVERY_OTP_TTL_MINUTES` and
      `COLLECTION_OTP_TTL_MINUTES` are optional (default 15).
- [ ] **Database backup confirmed** — **YOU must do this.** Not something I can
      confirm from here, and `catalog.0010` / `orders.0012` rewrite data.
- [x] **Migration plan confirmed** — documented above with verification + rollback
- [x] **Build artifacts verified** — 2 Next builds + 2 debug APKs
- [x] **No stale build output can ship** — a repo-wide sweep still finds the old
      `"Empty response from server."` string inside `apps/admin/.next/dev/`
      (Turbopack's local dev cache, holding pre-fix compiled source). It cannot
      reach production: `.next` is in both `.dockerignore` and `.gitignore`, and
      each Dockerfile runs `npm run build` in its own builder stage and copies
      only the freshly produced `.next/standalone` + `.next/static`. Verified on
      both consoles. Worth knowing so the string doesn't cause alarm in a grep.
- [x] **Rollback plan documented** — reverse migrations, then the dump

---

## Deployment blockers

**Hard blockers — do not deploy until these are done:**

1. **Production database backup.** Two migrations rewrite values in place.
2. **Real-device smoke test of both apps.** Login, location permission, push
   (foreground + background), camera/photo upload, OTP, maps. This is the
   largest unverified surface and the one where emulator behaviour genuinely
   differs.

**Should do before cutover:**

3. **Run the backend suite inside the container** so the 4 firebase-admin tests
   actually execute.
4. **Google Maps API key** — tracking maps need it; unrelated to this work but
   still outstanding.
5. **Run `verify_gst_migration.py` before and after** on production and diff.

**Not blockers, but known:**

6. Neither console has been click-tested in a browser. Types and builds are
   clean and the API contracts are covered by tests, but no human has driven the
   UI.
7. The customer-app state matrix (fresh install, token expiry, app killed,
   offline→online) is verified only by code inspection and unit tests.

---

## Final recommendation

**CONDITIONAL GO.**

The backend, the database migrations and both web consoles are in a state I am
comfortable calling ready: 1392 tests, a provably safe and idempotent GST
migration diffed against real data, and a clean role-by-role authorization audit
that found no holes.

The mobile apps are **not** in that state — not because anything is known to be
broken, but because the things most likely to break on a phone (permissions,
push delivery, camera, GPS) are exactly the things I cannot exercise here. Ship
the backend and consoles behind the migration plan above; gate the APKs on a
real-device pass.

Do not read "1392 tests pass" as production-ready on its own. It means the code
does what the tests say. Items 1 and 2 above are what turn that into confidence.
