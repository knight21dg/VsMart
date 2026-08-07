# CODING AGENTS: READ THIS FIRST

This is a **handoff bundle** from Claude Design (claude.ai/design).

A user mocked up designs in HTML/CSS/JS using an AI design tool, then exported this bundle so a coding agent can implement the designs for real.

## What you should do — IMPORTANT

**Read the chat transcripts first.** There are 1 chat transcript(s) in `chats/`. The transcripts show the full back-and-forth between the user and the design assistant — they tell you **what the user actually wants** and **where they landed** after iterating. Don't skip them. The final HTML files are the output, but the chat is where the intent lives.

**Read `project/VS Mart Landing.dc.html` in full.** The user had this file open when they triggered the handoff, so it's almost certainly the primary design they want built. Read it top to bottom — don't skim. Then **follow its imports**: open every file it pulls in (shared components, CSS, scripts) so you understand how the pieces fit together before you start implementing.

**If anything is ambiguous, ask the user to confirm before you start implementing.** It's much cheaper to clarify scope up front than to build the wrong thing.

## About the design files

The design medium is **HTML/CSS/JS** — these are prototypes, not production code. Your job is to **recreate them pixel-perfectly** in whatever technology makes sense for the target codebase (React, Vue, native, whatever fits). Match the visual output; don't copy the prototype's internal structure unless it happens to fit.

**Don't render these files in a browser or take screenshots unless the user asks you to.** Everything you need — dimensions, colors, layout rules — is spelled out in the source. Read the HTML and CSS directly; a screenshot won't tell you anything they don't.

## Bundle contents

- `README.md` — this file
- `chats/` — conversation transcripts (read these!)
- `project/` — the `Landing page design specs` project files (HTML prototypes, assets, components)

---

## Implementation (added by coding agent)

The `VS Mart Landing` design has been implemented as a **Next.js (App Router) +
TypeScript** site. The original design bundle is left untouched under `project/`
and `chats/` for reference.

- `app/` — the Next.js app
  - `layout.tsx` — fonts (Bricolage Grotesque / Plus Jakarta Sans / JetBrains Mono via `next/font`) + SEO metadata
  - `page.tsx` — assembles all 12 sections
  - `globals.css` — reset, color tokens, keyframes, and the hover/focus styles
  - `components/` — one component per section, plus `ScrollAnimations` (counters,
    VS Score ring, animated chart bars) and `LeadForm` / `Faq` (interactive)
- `public/assets/` — brand logo + app icon

Imagery and the lead form match the prototype: CSS-built phone mockups, striped
product placeholders, and a front-end-only "Thank you" on form submit.

## Customer sign-in (phone + OTP)

Customers sign in at `/login` with the same phone-OTP flow as the app, and land
on `/account` (profile + order history). The site is not shoppable — checkout
still lives in the mobile app.

**Tokens never reach page scripts.** The browser talks only to this app's own
route handlers; they attach the JWT server-side and keep the pair in httpOnly,
`SameSite=Lax` cookies (`vsm_at` / `vsm_rt`). That also means the API's CORS
allow-list doesn't need the landing domain.

| Route handler | Backend call | Notes |
| --- | --- | --- |
| `POST /api/auth/otp/send` | `/auth/otp/send` | Normalises to E.164; forwards the client IP so the API's 5/min OTP throttle stays per-customer |
| `POST /api/auth/otp/verify` | `/auth/otp/verify` | Writes the session cookies; returns `needsProfile` |
| `POST /api/auth/profile` | `/auth/register` | Name/email capture and later edits |
| `GET /api/auth/session` | `/users/me` | `{ user: null }` when signed out |
| `POST /api/auth/logout` | `/auth/logout` | Blacklists the refresh token, clears cookies |
| `GET /api/account/orders` | `/orders` | Paginated order history |

`app/lib/session.ts` refreshes an expired access token once per request and
re-writes the cookie; an unrecoverable 401 clears the session instead of looping
the customer between `/login` and `/account`.

### Environment

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | Public API origin — inlined at build time, used by the product pages |
| `API_INTERNAL_BASE_URL` | Server-side API origin. Unset → falls back to the public URL. Set it to `http://backend:8000/api/v1` to keep auth traffic on the compose network — but Django then sees `Host: backend:8000`, so that also needs `backend` in the API's `ALLOWED_HOSTS` (compose exposes it as `LANDING_INTERNAL_API_BASE_URL`) |

### Run it

```bash
npm install
npm run dev      # http://localhost:3000
npm run build    # production build
npm start        # serve the production build
```

For local sign-in, run the Django dev server (`python manage.py runserver 8000`
in `apps/backend`) and point the site at it with `.env.local`:

```bash
printf 'NEXT_PUBLIC_API_BASE_URL=http://127.0.0.1:8000/api/v1\nAPI_INTERNAL_BASE_URL=http://127.0.0.1:8000/api/v1\n' > .env.local
```

Dev OTPs print to the Django console, and `OTP_DEV_BYPASS_CODE` (`123456`) works
for any number.
