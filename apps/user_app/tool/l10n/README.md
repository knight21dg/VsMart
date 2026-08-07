# VS Mart Localization System (English · Hindi · Telugu)

A closed-loop system that keeps the app **fully and correctly translated** across
`en` / `hi` / `te`, and **cannot silently drift** as new strings are added.

## The pieces

| Tool | Job | Run |
|------|-----|-----|
| `find_hardcoded.py` | Finds user-facing English literals in Dart that should be localized | `python tool/l10n/find_hardcoded.py` |
| `translate_arb.py` | Fills `app_hi.arb` / `app_te.arb` from `app_en.arb` via **Google Cloud Translation API** | `python tool/l10n/translate_arb.py` |
| `validate_arb.py` | CI gate: key parity + placeholder consistency + no empties | `python tool/l10n/validate_arb.py` |

Source of truth: `lib/l10n/app_en.arb` (the template). `hi`/`te` are **generated** —
never hand-edit them except for the ICU plural/select keys the pipeline flags.

## Architecture — translate at build time, ship static

UI text is translated **once, here** and shipped as static ARB. The app never calls
Google at runtime, so there is zero per-string latency, it works offline, and no user
text is sent to Google. (Dynamic *content* — product names, CMS pages — is data served
by the backend and is out of scope for this UI pipeline.)

## One-time key setup (never paste the key into chat or commit it)

The Cloud Translation API uses the same API-key style as Google Maps. Reuse the Maps
key (with **Cloud Translation API** enabled on its project) or a dedicated key.

Add it to `apps/backend/.env` (this file is git-ignored):

```
GOOGLE_TRANSLATE_API_KEY=YOUR_KEY      # or the pipeline also reads GOOGLE_MAPS_API_KEY
```

The pipeline reads the key from the environment or that `.env` and **never prints it**.

## Daily workflow — adding a new string

1. In Dart, use `context.l10n.someKey` (don't hardcode). Add the key + English to
   `lib/l10n/app_en.arb` (with an `@someKey` `{ "description": ... }` entry).
2. Fill the other two languages:
   ```
   python tool/l10n/translate_arb.py        # only translates missing/new keys
   flutter gen-l10n
   ```
3. Verify:
   ```
   python tool/l10n/validate_arb.py         # parity + placeholders
   flutter analyze
   ```

### Useful flags
- `translate_arb.py --lang hi` — one language · `--force` — re-translate all · `--dry-run`
- `validate_arb.py --strict` — also fail on "identical to English" warnings
- `find_hardcoded.py --baseline N` — CI ratchet: fail if hardcoded count exceeds `N`

## What the pipeline protects (so machine output is safe)

- **Placeholders** `{name}`, `{count}` — wrapped `notranslate`, never translated/reordered.
- **ICU plural/select** — skipped and **flagged for manual translation** (never corrupted).
- **Glossary** (`UPI`, `GST`, `KYC`, `VS Credit`, `WhatsApp`, …) — kept verbatim. Extend
  `GLOSSARY` in `translate_arb.py` rather than fixing the same term repeatedly.

Machine translations should still get a **native-speaker review pass** — new keys are
findable in `app_en.arb` by their `"description"`, and any left flagged with
`MT: needs native review` mark the batches that haven't been reviewed yet.

## CI integration (recommended)

Add to the build pipeline before `flutter build`:

```
python tool/l10n/validate_arb.py            # hard-fail on drift
python tool/l10n/find_hardcoded.py --baseline <current-count>   # ratchet down
```

So a PR that adds an English-only string or breaks placeholder parity fails CI.
