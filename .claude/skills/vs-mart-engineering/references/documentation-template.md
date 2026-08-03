# Documentation Template

When a feature warrants documentation, make it implementation-ready. Use this structure so anyone could build, test, or audit the feature from the doc alone.

## Per-feature sections

- **Objective** — what the feature is for
- **Actors** — who uses it
- **Permissions** — who's allowed to do what
- **Workflow** — the step-by-step flow
- **Business rules** — the rules the feature enforces
- **Validation rules** — what's checked and rejected
- **Error handling** — how errors surface to the user
- **Failure scenarios** — what happens when things go wrong (and how it recovers)
- **Notifications** — what gets sent, to whom, on which events
- **Audit logs** — what's recorded for traceability
- **Reporting** — what data this feeds into reports
- **APIs** — endpoints, request/response shapes
- **Database changes** — new/changed models, migrations
- **Test cases** — the scenarios that prove it works

Not every feature needs every section — drop the ones that don't apply rather than padding them. But for commerce and financial features, treat business rules, failure scenarios, audit logs, and test cases as mandatory.
