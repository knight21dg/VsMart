# Commerce Standards

Every commerce flow in VS Mart must hold these invariants under concurrent load. Protect them with database constraints and transactions, not just application logic — app-level checks lose races.

## Invariants

**Orders** — One checkout produces exactly one order. Guard against double-submit (idempotency key on the checkout request).

**Payments** — One payment maps to exactly one settlement. Never settle twice for the same payment intent.

**Inventory** — Never oversell. Decrement stock inside the same transaction that creates the order line, with a row lock or a conditional update (`UPDATE ... WHERE quantity >= n`).

**Coupons** — Redemption must be race-safe. Two users redeeming the last use of a coupon at once must not both succeed. Use a database constraint or atomic decrement.

**Credit** — Model the ledger as append-only. Outstanding balance is always *derived* by summing the ledger, never stored as a mutable field that can drift.

**Returns** — One return yields at most one refund. Enforce with a uniqueness constraint on the refund record.

**Notifications** — Deliver exactly once where the channel allows it; otherwise at-least-once with a dedupe key the client can use.

## Idempotency

All financial operations must be idempotent. A retried request (network blip, user double-tap, webhook redelivery) must not create a second order, charge, or refund. The standard pattern: accept a client-supplied idempotency key, persist it with a unique constraint, and short-circuit on replay.

## Checklist before shipping a commerce change

- Is the critical state change wrapped in a transaction?
- Is there a DB-level constraint backing the invariant, not just app logic?
- What happens if this request arrives twice?
- What happens if two users hit it simultaneously?
- Is the audit trail written for the financial event?
