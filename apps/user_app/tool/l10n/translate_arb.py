#!/usr/bin/env python3
"""VS Mart ARB auto-translation pipeline (Google Cloud Translation API v2).

Fills the Hindi (app_hi.arb) and Telugu (app_te.arb) ARB files from the English
template (app_en.arb) using Google Translate — the single source that keeps the
three languages in sync as new strings are added.

WHY a build-time pipeline (not runtime): UI chrome is translated ONCE here and
shipped as static ARB, so the app has zero per-string latency, works offline, and
never sends user data to Google at runtime.

WHAT IT PROTECTS (so machine output is safe to ship after review):
  * ICU placeholders like {name} / {count}  -> never translated, never reordered.
  * ICU plural/select messages              -> skipped + flagged (translate by hand).
  * A brand/tech glossary (UPI, GST, KYC, VS Credit, WhatsApp, ...) -> kept verbatim.

The Google API key is read from the environment (or apps/backend/.env) and is
NEVER printed or written to any committed file.

USAGE
  # translate only keys missing/empty in the targets (default, safe to re-run):
  python tool/l10n/translate_arb.py

  python tool/l10n/translate_arb.py --lang hi          # one language
  python tool/l10n/translate_arb.py --force            # re-translate everything
  python tool/l10n/translate_arb.py --dry-run          # show work, no API calls/writes

KEY SETUP (never paste the key into chat or commit it)
  Add to apps/backend/.env  (gitignored):
      GOOGLE_TRANSLATE_API_KEY=<your key>   # or reuse GOOGLE_MAPS_API_KEY
  ...with the "Cloud Translation API" enabled on that key's Google Cloud project.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import OrderedDict
from pathlib import Path

L10N_DIR = Path(__file__).resolve().parents[2] / "lib" / "l10n"
TEMPLATE = L10N_DIR / "app_en.arb"
TARGETS = {"hi": L10N_DIR / "app_hi.arb", "te": L10N_DIR / "app_te.arb"}
APP_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = Path(__file__).resolve().parents[3]
# Places the API key may live, in priority order. The Maps key (with Cloud
# Translation API enabled) is reused. Each entry is (file, [accepted var names]).
KEY_SOURCES = [
    (REPO_ROOT / "backend" / ".env",
     ["GOOGLE_TRANSLATE_API_KEY", "GOOGLE_MAPS_API_KEY"]),
    (APP_ROOT / "android" / "local.properties",
     ["GOOGLE_TRANSLATE_API_KEY", "MAPS_API_KEY"]),
    (REPO_ROOT / "admin" / ".env.local",
     ["GOOGLE_TRANSLATE_API_KEY", "NEXT_PUBLIC_GOOGLE_MAPS_API_KEY"]),
]

TRANSLATE_URL = "https://translation.googleapis.com/language/translate/v2"

# Terms that must survive translation verbatim (brands, acronyms, product names).
# Extend this list rather than hand-fixing the same term across languages.
GLOSSARY = [
    "VS Mart", "VSMart", "VS Credit", "VS", "UPI", "GST", "KYC", "CIBIL",
    "EMI", "OTP", "PIN", "MPIN", "COD", "PAN", "Aadhaar", "DigiLocker",
    "WhatsApp", "Telegram", "Facebook", "SMS", "Razorpay", "Play Store",
]
# Longest-first so "VS Credit" is matched before bare "VS".
GLOSSARY.sort(key=len, reverse=True)

PLACEHOLDER_RE = re.compile(r"\{[^{}]*\}")
ICU_COMPLEX_RE = re.compile(r"\{[^{}]*,\s*(plural|select)\s*,", re.IGNORECASE)


def load_arb(path: Path) -> "OrderedDict[str, object]":
    with path.open(encoding="utf-8") as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


def save_arb(path: Path, data: "OrderedDict[str, object]") -> None:
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


def read_api_key() -> str:
    """Resolve the key: env vars first, then the known config files (the Maps key
    with Cloud Translation API enabled is reused). Never logged."""
    for var in ("GOOGLE_TRANSLATE_API_KEY", "GOOGLE_MAPS_API_KEY"):
        val = os.environ.get(var, "").strip()
        if val:
            return val
    for path, names in KEY_SOURCES:
        if not path.exists():
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            for var in names:
                if line.startswith(var + "="):
                    val = line.split("=", 1)[1].strip().strip('"').strip("'")
                    if val:
                        return val
    return ""


def protect(text: str) -> str:
    """Wrap placeholders + glossary terms in <span class=notranslate> so the
    HTML-format Translate call leaves them exactly as-is."""
    def wrap(s: str) -> str:
        return f'<span class="notranslate">{s}</span>'

    # Placeholders first (they can contain arbitrary names).
    text = PLACEHOLDER_RE.sub(lambda m: wrap(m.group(0)), text)
    # Then glossary terms (word-boundary, case-sensitive to avoid over-matching).
    for term in GLOSSARY:
        text = re.sub(rf"(?<![\w]){re.escape(term)}(?![\w])", wrap(term), text)
    return text


TAG_RE = re.compile(r'<span class="notranslate">(.*?)</span>', re.DOTALL)
ANY_TAG_RE = re.compile(r"<[^>]+>")


def unprotect(text: str) -> str:
    text = TAG_RE.sub(lambda m: m.group(1), text)
    # Google may still emit stray tags; strip any leftovers defensively.
    text = ANY_TAG_RE.sub("", text)
    # Google HTML-escapes & < > — undo the common ones.
    return (text.replace("&amp;", "&").replace("&lt;", "<")
                .replace("&gt;", ">").replace("&#39;", "'").replace("&quot;", '"'))


def google_translate(strings: list[str], target: str, key: str,
                     retries: int = 4) -> list[str]:
    """Translate a batch (<=128 segments) EN->target via Translate v2 (HTML mode)."""
    payload = {
        "q": strings, "source": "en", "target": target, "format": "html",
    }
    data = json.dumps(payload).encode("utf-8")
    url = f"{TRANSLATE_URL}?key={urllib.parse.quote(key)}"
    for attempt in range(retries):
        req = urllib.request.Request(
            url, data=data, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                body = json.loads(resp.read().decode("utf-8"))
            return [t["translatedText"] for t in body["data"]["translations"]]
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", "replace")[:300]
            # 429/5xx are transient; back off. 4xx (bad key / API disabled) is fatal.
            if exc.code in (429, 500, 502, 503) and attempt < retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise SystemExit(
                f"Translate API error {exc.code}: {detail}\n"
                "If 403: enable 'Cloud Translation API' on the key's project and "
                "ensure the key allows it.")
        except urllib.error.URLError as exc:
            if attempt < retries - 1:
                time.sleep(2 ** attempt)
                continue
            raise SystemExit(f"Network error reaching Translate API: {exc}")
    return strings


def value_keys(arb: "OrderedDict[str, object]") -> list[str]:
    """Translatable message keys (skip @-metadata and the @@locale header)."""
    return [k for k, v in arb.items()
            if not k.startswith("@") and isinstance(v, str)]


def main() -> int:
    ap = argparse.ArgumentParser(description="Fill hi/te ARB via Google Translate.")
    ap.add_argument("--lang", default="hi,te",
                    help="comma list of targets (default hi,te)")
    ap.add_argument("--force", action="store_true",
                    help="re-translate every key (default: only missing/empty)")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would translate; no API calls or writes")
    args = ap.parse_args()

    en = load_arb(TEMPLATE)
    en_keys = value_keys(en)
    langs = [l.strip() for l in args.lang.split(",") if l.strip()]

    key = "" if args.dry_run else read_api_key()
    if not args.dry_run and not key:
        raise SystemExit(
            "No API key. Set GOOGLE_TRANSLATE_API_KEY (or GOOGLE_MAPS_API_KEY) in\n"
            "the environment or apps/backend/.env, with Cloud Translation API enabled.")

    overall_flagged: list[str] = []
    for lang in langs:
        if lang not in TARGETS:
            print(f"skip unknown lang '{lang}'"); continue
        tgt = load_arb(TARGETS[lang])

        todo, flagged = [], []
        for k in en_keys:
            src = en[k]
            existing = tgt.get(k)
            needs = args.force or not isinstance(existing, str) or not existing.strip()
            if not needs:
                continue
            if ICU_COMPLEX_RE.search(src):
                flagged.append(k)  # plural/select — translate by hand, don't corrupt.
                continue
            todo.append(k)

        print(f"[{lang}] to translate: {len(todo)} | plural/select flagged: "
              f"{len(flagged)} | already done: {len(en_keys)-len(todo)-len(flagged)}")
        overall_flagged += [f"{lang}:{k}" for k in flagged]

        if args.dry_run or not todo:
            continue

        # Translate in protected batches of 100.
        BATCH = 100
        for i in range(0, len(todo), BATCH):
            chunk = todo[i:i + BATCH]
            protected = [protect(en[k]) for k in chunk]
            out = google_translate(protected, lang, key)
            for k, translated in zip(chunk, out):
                tgt[k] = unprotect(translated)
            print(f"[{lang}]   {min(i+BATCH, len(todo))}/{len(todo)}")

        # Rewrite target in TEMPLATE key order (metadata + values), so diffs are clean.
        ordered: "OrderedDict[str, object]" = OrderedDict()
        for k in en:
            if k == "@@locale":
                ordered[k] = lang
            elif k.startswith("@"):
                continue  # metadata lives only in the template
            elif isinstance(en[k], str):
                ordered[k] = tgt.get(k, en[k])
        save_arb(TARGETS[lang], ordered)
        print(f"[{lang}] wrote {TARGETS[lang].name}")

    if overall_flagged:
        print("\nManual-translation needed (ICU plural/select), by design:")
        for f in overall_flagged:
            print(f"  - {f}")
    print("\nNext: run `flutter gen-l10n` then `python tool/l10n/validate_arb.py`.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
