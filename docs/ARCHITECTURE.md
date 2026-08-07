# VS Mart — Architecture

How the pieces fit together, and the invariants that hold the system upright. Read
[HANDOFF.md](../HANDOFF.md) first for the overall state; this document explains the *shape*.

---

## 1. Topology

```
   Customer app          Agent app         Marketing site      Store panel      Super-admin
   (Flutter)             (Flutter)         (Next.js)           (Next.js)        (Next.js)
        │                    │                   │                  │                │
        └────────────────────┴─────────┬─────────┴──────────────────┴────────────────┘
                                       │  HTTPS  /api/v1
                              ┌────────▼────────┐
                              │   Caddy (TLS)   │  api. / admin. / store. / thevsmart.com
                              └────────┬────────┘
                                       │
                        ┌──────────────▼──────────────┐
                        │  Django 5 + DRF (41 apps)   │  gunicorn (HTTP) + daphne (WS)
                        │  business logic lives HERE  │
                        └───┬─────────┬─────────┬─────┘
                            │         │         │
                     Postgres 16   Redis    scheduler
                     (durable)  (cache/OTP) (periodic jobs)
```

Every client is a **thin** client. No business rule — pricing, credit eligibility, stock, zone
routing — is decided on a device or in a browser. Clients render state and submit intent; the
backend decides. This is deliberate: a shipped APK cannot be patched quickly, and a client-side rule
is a rule an attacker can edit.

**Realtime** runs over Django Channels (ASGI/daphne) with JWT authentication on the WebSocket
handshake — the live dispatch board and customer order tracking. Both have a polling fallback,
because a rider's phone loses its socket constantly.

---

## 2. The domain, in the order things happen

```
  Customer ──lives in──▶ Zone ──served by──▶ Store ──holds──▶ Inventory
                                                                  │
  Cart ──▶ Checkout ──▶ Order ──routed to the serving Store ──────┘
              │            │
              │            ├──▶ Delivery task ──▶ Agent ──▶ Proof of delivery
              │            └──▶ Invoice
              │
              ├──▶ Payment (online / COD)  or  ▶ Credit ledger entry (BNPL)
              │                                        │
              │                                        ▼
              │                              Statement ──▶ Repayment
              │                                        │
              │                                        ▼
              │                            Collection task ──▶ Agent ──▶ Cash
              │                                                          │
              └──────────────────────────────────────────────────────────┤
                                                                          ▼
                                              Agent deposit ──▶ Finance verification
                                                                          │
                                                                          ▼
                                                            Double-entry General Ledger
```

The chain from "customer owes money" to "money is in the company's books" is fully modelled. That
was not always true: before the cash book existed, physical notes handed to an agent were tracked
nowhere.

---

## 3. Serviceability: how an order finds a store

VS Mart operates polygons, not pincodes. A `Zone` carries a polygon; a point-in-polygon test (pure
Python — deliberately no PostGIS dependency) resolves a customer's coordinates to a zone, and the
zone to its serving store.

Consequences that surprise people:

- The customer app **hard-locks** behind device GPS. Out of coverage means a full-screen "change
  location" state, not a degraded catalog.
- The catalog is **store-scoped**. A store also has *private* products, browsable only within its
  own tree, shareable by an unguessable `share_token` — sequential IDs 404, so the catalog is not
  enumerable.
- Serviceability locks only engage once the account `stage == approved`. Engaging them earlier
  deadlocks registration: the lifecycle guard pins the user to `/register` while the serviceability
  guard pins them to `/not-serviceable`.

---

## 4. Invariants

These are load-bearing. Breaking one produces a bug that shows up as missing money, not as a stack
trace.

### 4.1 Ledgers are append-only
Credit, inventory and loyalty points are all append-only ledgers. A row is never UPDATEd or DELETEd;
you post a compensating entry. Model-level `.save()`/`.delete()` guards enforce this.

Balances are **derived, cached and reconciled** — never authored. Available stock is
`Σ ledger − reserved`; `InventoryService.post_movement` is the sole writer. The `StockItem` row is a
cache of that sum, not the truth.

The failure mode this prevents is the one the 2026-07-22 credit sweep found: a dashboard that summed
a *paginated* ledger page and reported the wrong outstanding balance. `getCreditSummary` is now the
one authoritative computation.

### 4.2 Store scoping is a security boundary
Not a convenience filter. Any query a store can reach must be scoped to that store, and the scope
must be enforced at the endpoint — not merely reflected in the UI picker.

Four separate store-scope leaks have been found and fixed, every one of them a hand-rolled query
that forgot the filter. The worst let one store hand its cash collection to another store's rider.
**Use `agents/candidates.py` (`candidate_agents`, `assignable_agents`) for agent selection** rather
than writing a new query — and make the picker and the guard read the same definition, or they will
disagree.

### 4.3 Money operations are idempotent
`/checkout` and `/pos/checkout` take an `Idempotency-Key`, backed by unique database constraints
(`uniq_order_idempotency`, `uniq_payment_idempotency`) — not just an application-level check. A
double-tap, a retried request and a flaky network all converge on one order.

Stock is **reserved** at checkout and released by a TTL sweep
(`orders.services.release_expired_reservations`) so an abandoned checkout does not hold inventory
forever.

### 4.4 Evidence must be real
Anything recorded as proof of physical presence must come from the device's actual position. The
delivery arrival geofence (50 m) was once bypassable because `LocationService.current()` accepted a
caller-supplied fallback, and every caller filled it with *the destination* — so with GPS switched
off the app answered "where are you?" with the delivery address. Presence evidence now uses a live
fix only, and refuses rather than substitutes.

The same rule covers the proof-of-delivery photo and the GPS stamp on field verification.

### 4.5 The contract is frozen forward
Endpoints are never renamed and existing fields are never removed — a shipped APK cannot be
migrated. Additions are always safe; changes never are. The API is frozen via drf-spectacular into
`apps/backend/docs/api/`.

---

## 5. The response contract

Every response, success or failure, is an envelope:

```jsonc
{ "success": true, "message": "…", "data": { … }, "meta": { … } }
```

Failures add a machine-readable code plus RFC 9457 members (additively — the envelope keys stay):

```jsonc
{ "success": false, "message": "…",
  "error": { "code": "CREDIT_LIMIT_EXCEEDED", "message": "…", "fields": { … } },
  "type": "…", "title": "…", "status": 400, "detail": "…", "instance": "…" }
```

`core/response_codes.py` is the single source of truth: **267 codes across 25 modules**, each
carrying its HTTP status, severity, human title and message, and — the important part — an
**action** telling the client what to *do*: `navigate`, `retry`, `retry_verification`, `logout`,
`reauth`, `refresh`, `contact_support` or nothing. Services raise `AppError("CODE")`; the app's
`presentFailure` turns the action into a toast, dialog, blocker or navigation.

The goal is that no surface ever shows "Something went wrong."

### Casing — the one genuine wart
`/auth/*` and `/users/me` respond in **snake_case**. Everything else responds in **camelCase**. This
is not an oversight and must not be "fixed": the shipped Flutter models parse snake_case on those
endpoints. Store-panel request bodies are camelCase-parsed through `io_utils.field`. Phone numbers
are E.164 everywhere.

---

## 6. Client architecture

### Flutter apps — the cache-mirror pattern
Repositories expose a **synchronous** interface, so widgets read without awaiting. Behind it:

```
Widget ──reads──▶ Repository ──serves──▶ Hive cache   (sync, instant)
                       │
                       └──writes──▶ Backend ──▶ refresh cache ──▶ notify
```

The server is authoritative; Hive is a mirror hydrated on build. New backend integration means a new
`*BackendDataSource` plus a cache-mirror repo and a provider swap — never async-ing the existing
sync callers, which would ripple through the whole widget tree.

State is Riverpod; routing is go_router with layered guards (bootstrap → auth → lifecycle stage →
serviceability). Deep links are **parked and replayed** after those gates rather than handed to the
router on arrival, which is why a notification tap works even from a cold start on a logged-out app.

Logout wipes all user-scoped Hive boxes *and* invalidates in-memory user-scoped providers — both,
or the next account sees the previous one's data.

### Next.js consoles
`apps/admin` is platform-wide; `apps/store-admin` is scoped to exactly one store via `StoreStaff`
plus a permission catalog. The store panel is an installable PWA whose POS works **offline**:
IndexedDB caches the catalog, an outbox queues sales, and sync is idempotent — a till cannot stop
because the internet did.

---

## 7. Media

Media is **self-hosted** rather than delegated to object storage: the `mediastore` app runs a WebP
conversion pipeline, splits public from private assets, and serves private files
(KYC documents, proof-of-delivery photos) through a permission gate with X-Accel handing the actual
bytes to Caddy. The permission check happens in Django; the file transfer does not.

---

## 8. Regulatory shape

VS Mart **cannot lend on its own books**. The credit product is structured as an RBI NBFC/LSP
partnership: no pass-through account, a 5% FLDG cap, and prescribed collections conduct. This is why
KYC deliberately **informs the reviewer and never auto-grants credit**, and why KYC approval is
decoupled from the credit grant — only an approved `CreditApplication` carrying an explicit limit
sets `credit_enabled`. Do not re-fuse those two; they were separated on purpose.
