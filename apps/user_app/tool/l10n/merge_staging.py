#!/usr/bin/env python3
"""Merge tool/l10n/_staging/*.json (new EN keys produced by the migration agents)
into lib/l10n/app_en.arb — the single, conflict-free writer of the template.

Detects and reports collisions (same key staged twice with different values, or a
staged key that already exists in the template with a different value) instead of
silently clobbering. Run after the migration agents finish, then:
    python tool/l10n/translate_arb.py && flutter gen-l10n && \
    python tool/l10n/validate_arb.py && flutter analyze
"""
from __future__ import annotations

import json
import sys
from collections import OrderedDict
from pathlib import Path

L10N = Path(__file__).resolve().parents[2] / "lib" / "l10n"
TEMPLATE = L10N / "app_en.arb"
STAGING = Path(__file__).resolve().parent / "_staging"


def load(p: Path):
    with p.open(encoding="utf-8") as fh:
        return json.load(fh, object_pairs_hook=OrderedDict)


def main() -> int:
    en = load(TEMPLATE)
    staging_files = sorted(STAGING.glob("*.json")) if STAGING.exists() else []
    if not staging_files:
        print("No staging files found in", STAGING)
        return 1

    added, reused_conflict, cross_conflict = 0, [], []
    seen: dict[str, str] = {}

    for sf in staging_files:
        data = load(sf)
        for k, v in data.items():
            if k.startswith("@"):
                continue  # metadata handled alongside its key below
            # cross-file duplicate key with a different value?
            if k in seen and seen[k] != v:
                cross_conflict.append(f"{k}: {seen[k]!r} vs {v!r} ({sf.name})")
            seen[k] = v
            if k in en:
                if isinstance(en[k], str) and en[k] != v:
                    reused_conflict.append(
                        f"{k}: template={en[k]!r} staged={v!r} ({sf.name})")
                continue  # already in template — leave template's value authoritative
            en[k] = v
            meta = data.get("@" + k)
            if meta is not None:
                en["@" + k] = meta
            added += 1

    if cross_conflict:
        print("CROSS-FILE KEY CONFLICTS (same key, different value):")
        for c in cross_conflict:
            print("  ", c)
    if reused_conflict:
        print("STAGED KEY ALREADY IN TEMPLATE (kept template value):")
        for c in reused_conflict[:30]:
            print("  ", c)

    # @@locale must stay first; otherwise keep insertion order (existing then new).
    with TEMPLATE.open("w", encoding="utf-8", newline="\n") as fh:
        json.dump(en, fh, ensure_ascii=False, indent=2)
        fh.write("\n")

    total = len([k for k in en if not k.startswith("@")])
    print(f"\nMerged {added} new key(s) from {len(staging_files)} staging file(s).")
    print(f"app_en.arb now has {total} message keys.")
    if cross_conflict:
        print("Resolve cross-file conflicts before translating.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
