# Phase 4 — Credit Billing & Collections Architecture

VS Mart is a credit-based grocery platform. Phase 4 builds the **Credit Ledger
System** that the entire money side of the product derives from:

```
Orders → Credit Ledger → Billing Cycles → Statements → Invoices
       → Payments → Collections → (Agent App) → (Admin Panel)
```

The guiding rule: **everything derives from the ledger.** No screen recomputes a
balance; every figure (available credit, outstanding, utilization, current bill,
minimum due, late fees) is produced by a single calculation service reading the
ledger. This keeps the customer app, the future agent collection app, and the
admin panel consistent because they all consume the same source of truth.

---

## 1. Layering

Feature: `lib/features/billing/`, Clean + feature-first.

```
domain/
  entities/        billing_enums, credit_ledger_entry, billing_cycle,
                   statement, invoice, repayment, collection_record
  services/        credit_calculation_service     ← the calculation authority
  repositories/    billing_repository (interface)
data/
  datasources/     billing_data_source (+ BillingFixtureDataSource)
  models/          billing_models (JSON ↔ entity for Hive persistence)
  repositories/    billing_repository_impl (BaseRepository, offline-first)
presentation/
  providers/       billing_providers (wiring + derived + controllers)
  widgets/         transaction_tile, credit_due_banner
  screens/         billing_dashboard, statements (+detail),
                   invoices (+detail), payment_history, repayment (+success)
```

The data source is the **single backend seam**: `BillingFixtureDataSource` seeds
a coherent demo ledger today; swapping in a Dio-backed source later requires no
change above the data layer.

---

## 2. The Credit Ledger (4A)

`CreditLedgerEntry` is the atomic unit — one signed line in the customer's
account:

| Field          | Meaning                                            |
| -------------- | -------------------------------------------------- |
| `type`         | purchase / repayment / penalty / adjustment / refund |
| `status`       | pending / completed / failed / reversed            |
| `amount`       | always positive; direction comes from `type`       |
| `signedAmount` | `+amount` for debits, `-amount` for credits        |
| `balanceAfter` | running outstanding after this entry               |
| `orderId`      | links a purchase back to its order                 |
| `cycleId`      | groups entries into a billing cycle                |

Debits (purchase, penalty) increase the balance; credits (repayment, refund)
decrease it. Higher-level entities are **views over the ledger**:

- **BillingCycle** — opening/closing balance + movement for one period.
- **Statement** — the transactions of one cycle plus amount due / minimum due /
  due date; `isOverdue` is derived.
- **Invoice** — a per-order document (status: pending/paid/overdue/cancelled).
- **Repayment** — a credit applied to the balance; doubles as a payment-history
  record.
- **CollectionRecord** — a field cash-collection request, shaped for the future
  Agent App (agent assignment) and Admin Panel (oversight).

---

## 3. The Calculation Engine (4C)

`CreditCalculationService` is `const`, pure, and the **only** place balances are
computed:

| Method                    | Definition                                           |
| ------------------------- | ---------------------------------------------------- |
| `outstandingBalance`      | Σ signed amount of *settled* entries, clamped ≥ 0    |
| `availableCredit`         | `creditLimit − outstanding`, clamped ≥ 0             |
| `utilizationPercentage`   | `outstanding / limit`, clamped 0..1                  |
| `minimumDue`              | `max(10% of amountDue, ₹100)`, capped at amount due  |
| `nextDueDate`             | the current statement's due date                     |
| `lateFees`                | ₹50 per started week past the due date (overdue only)|

Only **settled** (`completed`) entries count toward the balance, so a pending or
failed transaction never moves available credit.

---

## 4. Data Layer & Offline-First (4B)

`BillingRepositoryImpl` mixes in `BaseRepository` and guards every call with
`guard(..., requireConnection: false)` — billing must work offline.

- **Ledger** persists to Hive `creditLedgerBox` (key `entries`), seeded from the
  data source on first run, then read locally.
- **Payment history** persists to `paymentHistoryBox`, seeded likewise.
- **Cycles / statements / invoices / credit limit** are served from the data
  source (read models).
- `makeRepayment` computes the current outstanding via the calculation service,
  appends a completed `Repayment` **and** a matching `repayment`
  `CreditLedgerEntry` (with `balanceAfter`), and saves both — so the ledger and
  the derived figures update atomically.
- `requestCollection` returns a `pending` `CollectionRecord` for the Agent App
  to pick up.

JSON (de)serialization lives in `billing_models.dart`; enums round-trip by
`name` via a tolerant `_byName` helper that defaults gracefully.

Hive boxes registered in `HiveService.init`: `creditLedgerBox`,
`billingCycleBox`, `statementBox`, `invoiceBox`, `paymentHistoryBox`.

---

## 5. Providers — derive once, never in the UI

`billing_providers.dart`:

- **Wiring:** `billingDataSourceProvider` → `billingRepositoryProvider`,
  `creditCalculationServiceProvider`.
- **Source reads:** `creditLimit`, `creditLedger`, `billingCycles`,
  `statements`, `currentStatement`, `invoices`, `paymentHistory`, plus
  `invoiceById` / `statementById` families.
- **Derived figures:** `outstandingBalance`, `availableCredit`,
  `creditUtilization`, `minimumDue`, `nextDueDate` — each computed by the
  service off the ledger providers.
- **`billingOverviewProvider`** — a single aggregated record (limit, outstanding,
  available, utilization, current statement, minimum due, next due, recent
  transactions) so the dashboard renders from one `AsyncValue`.
- **Write controllers:**
  - `RepaymentController` (`repaymentControllerProvider`) — drives a repayment,
    stores the receipt in `lastRepaymentProvider`, then invalidates the ledger /
    history / statement providers so every derived figure refreshes.
  - `CollectionController` (`collectionControllerProvider`) — raises a cash
    collection request.

Invalidating `creditLedgerProvider` cascades: because the derived providers
`watch` it, they recompute automatically — the dashboard reflects a new balance
the moment a repayment lands.

---

## 6. Screens (4D–4H)

All screens are pure presentation over providers; no business logic, no API
calls, design-system tokens only (`AppColors` / `AppTypography` / `AppSpacing` /
`AppRadius`, `context.vsColors`).

- **Credit Dashboard (4D)** — the Credit tab root. Ledger-derived hero
  (available / used / limit / utilization), current-bill card (amount due,
  minimum due, due date, overdue chip), quick actions, and recent activity.
  Pull-to-refresh re-reads the ledger.
- **Statements (4E)** — list (one card per cycle, status chip) → detail
  (summary + transactions + pay action). Download is stubbed via a snackbar.
- **Invoices (4F)** — list → detail with a link back to the originating order.
- **Payment History (4G)** — every repayment newest-first; tap reveals a receipt
  bottom sheet.
- **Repayment (4H)** — choose amount (or 25/50/75/100% of outstanding) and a
  method. UPI / Card / Bank settle the ledger immediately and route to the
  success screen; **Cash Collection** branches to a `CollectionRecord` request
  (Phase 4I) instead of an instant settlement.

The shared `TransactionTile` renders a ledger line identically on the dashboard
and statement detail.

---

## 7. Collections (4I)

`requestCollection` + `CollectionController` produce a `pending`
`CollectionRecord` whose shape already carries `agentId` / `agentName` /
`collectedAt` / `status` (pending → assigned → collected → failed). The customer
app raises the request; the future **Agent App** assigns and updates it, and the
**Admin Panel** oversees it — no schema change required.

---

## 8. Analytics (4J)

Events flow through `AnalyticsService.track` (Firebase with logger fallback):

`credit_dashboard_viewed`, `statement_opened`, `invoice_opened`,
`payment_started`, `payment_completed`, `payment_failed`, `repayment_created`,
`collection_record_created`.

---

## 9. Home Integration (4K)

- The existing `VSCreditSummaryCard` on Home now routes its "Pay Now" into the
  ledger-derived dashboard.
- **`CreditDueBanner`** (new) is a self-collapsing, ledger-derived reminder: it
  watches `currentStatementProvider` and renders only when a statement is unpaid
  (orange when due, red when overdue), deep-linking straight to the repayment
  flow. It returns `SizedBox.shrink()` otherwise, so it drops into the Home
  scroll view unconditionally.

---

## 10. Forward compatibility

| Consumer                    | Reuses                                              |
| --------------------------- | -------------------------------------------------- |
| Agent Collection App        | `CollectionRecord`, `requestCollection`, statuses  |
| Admin Credit Management      | `BillingRepository`, ledger + statement read models |
| Automated Billing Engine     | `BillingCycle` + `CreditCalculationService`         |

Because cycles, statements, invoices, and balances are all projections of the
one ledger, an automated billing engine only needs to (a) append ledger entries
and (b) close cycles — the rest of the system recomputes itself.

---

## 11. Exit criteria — status

| Criterion              | Status                                              |
| ---------------------- | --------------------------------------------------- |
| Credit Domain          | ✅ 7 entities + enums                                |
| Billing Repository      | ✅ offline-first, Hive-backed ledger + history       |
| Statement System        | ✅ list + detail, cycle-grouped transactions         |
| Invoice System          | ✅ list + detail, order linkage                       |
| Payment History         | ✅ list + receipt sheet                               |
| Repayment Flow          | ✅ amount + method, ledger-updating, success          |
| Collection Integration  | ✅ CollectionRecord + cash-collection branch          |
| Analytics               | ✅ 8 events                                            |
| Home Integration        | ✅ summary card + due banner                           |
| Offline Support         | ✅ `requireConnection: false`, Hive persistence       |
| Analyzer Clean          | ✅ `flutter analyze lib` → No issues found            |
