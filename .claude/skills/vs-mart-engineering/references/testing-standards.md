# Testing Standards

Every feature ships with tests. Cover the happy path, then the ways it breaks.

## What to write

Backend (Django):
- Unit tests for business logic
- Integration tests for API endpoints and multi-step flows

Flutter:
- Unit tests for logic
- Widget tests for screen behavior
- Integration tests where practical

## Failure modes to exercise

Don't stop at the happy path. For each feature, ask which of these apply and test them:

- Invalid inputs
- Empty values
- Boundary values
- Network failures
- Offline mode
- Concurrency (two requests at once)
- Duplicate requests (idempotency)
- Timeouts
- Permission failures
- Expired sessions
- Localization
- Theme changes (light/dark)

For commerce features, concurrency and duplicate-request tests are not optional — they're how you prove the invariants in `commerce-standards.md` actually hold.
