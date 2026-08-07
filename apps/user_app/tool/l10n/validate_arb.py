#!/usr/bin/env python3
"""VS Mart ARB validator — the CI gate that keeps en/hi/te perfectly in sync.

Fails (exit 1) when any of these drift, so a broken translation can never merge:
  1. KEY PARITY   — every message key in the English template exists in hi and te
                    (and no target has stray keys the template lost).
  2. PLACEHOLDERS — every {name}/{count} token in the English value appears, with
                    the same set, in the hi and te values (a dropped/renamed
                    placeholder throws at runtime or renders wrong).
  3. EMPTIES      — no target value is blank.
  4. UNTRANSLATED — reports (warning, not failure) target values identical to
                    English, excluding an allow-list of terms that are meant to
                    stay identical (UPI, GST, WhatsApp, ...).

USAGE
  python tool/l10n/validate_arb.py            # validate, exit non-zero on error
  python tool/l10n/validate_arb.py --strict   # also fail on untranslated warnings

Wire into CI before `flutter build` so releases can't ship broken localization.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

L10N_DIR = Path(__file__).resolve().parents[2] / "lib" / "l10n"
TEMPLATE = L10N_DIR / "app_en.arb"
TARGETS = {"hi": L10N_DIR / "app_hi.arb", "te": L10N_DIR / "app_te.arb"}

# A real ICU placeholder is `{name}` or `{name, plural/select, ...}` — the arg
# name is immediately followed by `}` or `,`. This intentionally does NOT match
# plural sub-message text like `{No items}` (where a space follows the word).
PLACEHOLDER_RE = re.compile(r"\{\s*([a-zA-Z][\w]*)\s*[,}]")

# Values allowed to be identical to English (brands/acronyms with no local form).
SAME_AS_EN_OK = {
    "UPI", "GST", "WhatsApp", "Telegram", "Facebook", "SMS", "OTP", "PIN",
    "COD", "PAN", "EMI", "KYC", "CIBIL", "VS Mart", "VSMart", "VS Credit",
}


def load(path: Path) -> "OrderedDict[str, object]":
    with path.open(encoding="utf-8") as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


def value_keys(arb) -> set[str]:
    return {k for k, v in arb.items() if not k.startswith("@") and isinstance(v, str)}


def placeholders(text: str) -> set[str]:
    return set(PLACEHOLDER_RE.findall(text))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true",
                    help="treat 'untranslated' warnings as errors")
    args = ap.parse_args()

    en = load(TEMPLATE)
    en_keys = value_keys(en)
    errors: list[str] = []
    warnings: list[str] = []

    for lang, path in TARGETS.items():
        if not path.exists():
            errors.append(f"[{lang}] missing file {path.name}")
            continue
        tgt = load(path)
        tkeys = value_keys(tgt)

        # 1. parity
        missing = en_keys - tkeys
        extra = tkeys - en_keys
        if missing:
            errors.append(f"[{lang}] {len(missing)} key(s) missing: "
                          f"{sorted(missing)[:10]}")
        if extra:
            errors.append(f"[{lang}] {len(extra)} stray key(s) not in template: "
                          f"{sorted(extra)[:10]}")

        # 2/3/4 per shared key
        for k in en_keys & tkeys:
            en_val, tv = en[k], tgt[k]
            if not isinstance(tv, str) or not tv.strip():
                errors.append(f"[{lang}] '{k}' is empty")
                continue
            ep, tp = placeholders(en_val), placeholders(tv)
            if ep != tp:
                errors.append(
                    f"[{lang}] '{k}' placeholder mismatch: en={sorted(ep)} "
                    f"{lang}={sorted(tp)}")
            if tv == en_val and en_val not in SAME_AS_EN_OK and len(en_val) > 2:
                warnings.append(f"[{lang}] '{k}' identical to English: {en_val!r}")

    for w in warnings:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)

    print(f"\n{len(en_keys)} template keys | {len(errors)} error(s) | "
          f"{len(warnings)} warning(s)")
    if errors or (args.strict and warnings):
        print("VALIDATION FAILED")
        return 1
    print("VALIDATION PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
