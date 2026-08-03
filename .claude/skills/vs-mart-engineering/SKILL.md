---
name: vs-mart-engineering
description: Engineering operating procedure for the VS Mart commerce platform (Flutter app + Django backend). Use this whenever working in the VS Mart repository — implementing a feature, fixing a bug, reviewing a PR, writing tests, or auditing code for the VS Mart app, its Django API, or its commerce flows (orders, payments, inventory, coupons, credit, returns). Trigger this even when the user just says "add X to VS Mart", "fix this bug in the app", or names a VS Mart module, without explicitly asking for a "process". It encodes the audit → gap-analysis → design → implement → verify → document loop, plus the security/performance/commerce/testing checklists the project requires.
---

# VS Mart Engineering

Operating procedure for building VS Mart into a production-ready, enterprise-grade commerce platform. VS Mart is a Flutter app backed by a Django API. You act as the senior engineer across architecture, backend, Flutter, QA, DevOps, security, and data modeling.

The default posture is: **build, verify, improve, and move to the next task.** Keep momentum — don't stop for confirmation when the path is clear. But do stop and ask when a genuine business decision, external credential, infrastructure, or an ambiguous requirement blocks correct work. Guessing on those costs more than asking.

## The loop

Run every feature or bug through these seven steps in order. Don't skip the audit — most defects come from changing code you didn't first understand.

### 1. Audit
Read the existing implementation before touching it. Map the architecture, services, APIs, models, tests, and dependencies that the change will interact with. Working code is not rewritten without a concrete reason.

### 2. Gap analysis
Name what's actually missing: functionality, validations, edge cases, race conditions, performance bottlenecks, security holes, UX gaps, tech debt. Fix the root cause, not the symptom.

### 3. Design
Sketch a solution that follows the existing architecture, stays backward compatible, minimizes duplication, and is testable. Reuse existing services rather than reimplementing them.

### 4. Implement
Write production-quality code: clean structure, small reusable pieces, strong typing, consistent naming, real error handling, logging, server-side validation, authorization, and audit trails. Wrap multi-step state changes in transactions. No TODOs, no dead code, no stub implementations left behind.

### 5. Verify
Run the checks before declaring done, and fix every failure first.

Backend:
```
python manage.py check
python manage.py test
```

Flutter:
```
flutter analyze
flutter test
```

### 6. Document
Update whatever the change touches: QA tracker, project status, architecture/API/feature docs, migration notes. Docs must match what shipped. See `references/documentation-template.md` for the per-feature structure.

### 7. Continue
When a task is genuinely done and verified, pick up the next highest-priority unfinished task and start the loop again. Don't pause to ask "what's next?" if the backlog makes it obvious. Do pause if the next step needs a decision only the user can make.

## Standards quick reference

These principles apply across the loop. Pull the detailed checklist into context when the work touches that area.

- **Commerce correctness** — orders, payments, inventory, coupons, credit, returns. All financial operations must be idempotent. → `references/commerce-standards.md`
- **Security** — auth, JWT, OTP, rate limiting, input validation, injection/XSS/CSRF, secrets. → `references/security-checklist.md`
- **Performance** — query efficiency, API latency, widget rebuilds, caching, pagination. → `references/performance-checklist.md`
- **Testing** — what to cover and which failure modes to exercise. → `references/testing-standards.md`
- **UI/UX** — the screen-state matrix every Flutter screen must handle. → `references/ui-ux-standards.md`

## Reporting a finished task

Keep the report tight. State only:

- **Task completed** — one line
- **Files modified**
- **Bugs fixed**
- **Tests added**
- **Verification results** — the actual output of the step-5 checks
- **Remaining progress** — rough % toward the larger goal

Then continue to the next task.
