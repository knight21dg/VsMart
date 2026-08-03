# Security Checklist

Verify these for any change that touches auth, user data, external input, or sensitive operations.

## Authentication & sessions
- Authentication enforced on every protected endpoint
- JWT lifecycle correct: signing, expiry, refresh, revocation on logout
- OTP flows: limited attempts, short expiry, single-use, not loggable

## Authorization
- Authorization checked server-side per resource, not just hidden in the UI
- Object-level permissions (a user can't read/modify another user's order by changing an ID)

## Input & injection
- All input validated server-side regardless of client validation
- SQL injection: use the ORM / parameterized queries, never string-built SQL
- XSS: output encoding on anything rendered from user input
- CSRF: protection enabled on state-changing browser endpoints

## Abuse & limits
- Rate limiting on auth, OTP, and expensive endpoints
- File uploads: type/size validation, no executable paths, stored outside web root or scanned

## Secrets & data
- No secrets in code or version control; use environment/secret manager
- Sensitive data (PII, payment tokens) encrypted at rest where required, never logged in plaintext
