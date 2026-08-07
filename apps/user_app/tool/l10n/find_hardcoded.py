#!/usr/bin/env python3
"""VS Mart hardcoded-string linter — finds user-facing English literals in Dart
that should be localized via `context.l10n.<key>` instead.

Heuristic (best-effort, tuned for this codebase): flags string literals passed to
common UI sinks — Text(...), hintText:, labelText:, label:, title:, subtitle:,
showSnack(...), SnackBar(content: Text(...)) — that contain natural-language text
(a letter + a space or >=4 letters) and are NOT already `context.l10n....`.

It deliberately ignores: keys/ids, asset paths, single words that are likely codes,
route names, and anything inside test/ or generated/ files.

USAGE
  python tool/l10n/find_hardcoded.py                 # report, exit 1 if any found
  python tool/l10n/find_hardcoded.py --count         # just print the number
  python tool/l10n/find_hardcoded.py --baseline N    # exit 1 only if count > N

Use --baseline in CI to ratchet down: set it to today's number and lower it as the
migration proceeds so the count can never grow.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FEATURES = Path(__file__).resolve().parents[2] / "lib" / "features"

# UI sinks whose string argument is shown to the user.
SINK = re.compile(
    r"(?:Text\(|hintText:|labelText:|helperText:|label:\s|title:\s|subtitle:\s|"
    r"showSnack\(|content:\s*Text\(|tooltip:\s|semanticLabel:\s)\s*"
    r"(?:const\s+)?(['\"])(?P<txt>(?:\\.|(?!\1).)*)\1",
)
# Looks like real UI copy: has a space, or is a >=4-letter word starting uppercase/lowercase.
NATURAL = re.compile(r"[A-Za-z].*\s.*[A-Za-z]|^[A-Za-z]{4,}$")
# Skip obvious non-copy: urls, asset paths, format tokens, all-caps codes.
SKIP = re.compile(r"^(?:https?:|/|assets/|[A-Z0-9_]{2,}$|\d)")


def is_copy(txt: str) -> bool:
    t = txt.strip()
    if not t or "l10n." in t or "\\$" in t:
        return False
    if SKIP.match(t):
        return False
    return bool(NATURAL.search(t))


def scan() -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    for dart in FEATURES.rglob("*.dart"):
        if "/generated/" in dart.as_posix() or dart.name.endswith(".g.dart"):
            continue
        text = dart.read_text(encoding="utf-8", errors="replace")
        for m in SINK.finditer(text):
            txt = m.group("txt")
            if is_copy(txt):
                line = text.count("\n", 0, m.start()) + 1
                rel = dart.relative_to(FEATURES.parents[1]).as_posix()
                hits.append((rel, line, txt))
    return hits


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", action="store_true")
    ap.add_argument("--baseline", type=int, default=-1,
                    help="fail only if the number of hits exceeds this")
    args = ap.parse_args()

    hits = scan()
    if args.count:
        print(len(hits)); return 0

    by_module: dict[str, int] = {}
    for rel, line, txt in hits:
        parts = rel.split("/")
        mod = parts[2] if len(parts) > 2 else parts[-1]
        by_module[mod] = by_module.get(mod, 0) + 1
    for rel, line, txt in hits:
        print(f"{rel}:{line}: {txt!r}")
    print("\nBy module:")
    for mod, n in sorted(by_module.items(), key=lambda x: -x[1]):
        print(f"  {mod:16} {n}")
    print(f"\nTotal hardcoded UI strings: {len(hits)}")

    limit = args.baseline
    if limit >= 0:
        if len(hits) > limit:
            print(f"FAIL: {len(hits)} > baseline {limit}")
            return 1
        print(f"OK: {len(hits)} <= baseline {limit}")
        return 0
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
