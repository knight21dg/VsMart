#!/usr/bin/env bash
#
# VS Mart — release gate. Runs every automated check that protects the hardened
# commerce/money path. Run locally before tagging a release, or wire into CI
# (GitHub Actions / GitLab CI) to run on every merge. Exits non-zero if any HARD
# gate fails, so a broken checkout/payment/credit path can never reach a release.
#
# Usage:  bash scripts/release_gate.sh
#
# HARD gates (fail the build): django check, no missing migrations, backend tests,
#                              flutter analyze, flutter test.
# SOFT (informational):        reconcile_finance — audits DATA in the current DB,
#                              not code; review drift against prod/staging.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/apps/backend"
APP="$ROOT/apps/user_app"

# Locate the backend venv python (Windows or Linux), else fall back to PATH.
if [ -x "$BACKEND/.venv/Scripts/python.exe" ]; then PY="$BACKEND/.venv/Scripts/python.exe"
elif [ -x "$BACKEND/.venv/bin/python" ]; then PY="$BACKEND/.venv/bin/python"
else PY="python"; fi

FAIL=0
mark() {  # mark <exit_code> <name>
  if [ "$1" -eq 0 ]; then echo "[PASS] $2"; else echo "[FAIL] $2"; FAIL=1; fi
}

echo "=== 1/6 Django system check ==="
( cd "$BACKEND" && "$PY" manage.py check ); mark $? "django check"

echo "=== 2/6 No missing migrations ==="
( cd "$BACKEND" && "$PY" manage.py makemigrations --check --dry-run ); mark $? "migrations up to date"

echo "=== 3/6 Backend tests ==="
( cd "$BACKEND" && "$PY" manage.py test ); mark $? "backend tests"

echo "=== 4/6 Flutter analyze ==="
( cd "$APP" && flutter analyze ); mark $? "flutter analyze"

echo "=== 5/6 Flutter tests ==="
( cd "$APP" && flutter test ); mark $? "flutter test"

echo "=== 6/6 Finance reconciliation (informational) ==="
if ( cd "$BACKEND" && "$PY" manage.py reconcile_finance ); then
  echo "[OK]   reconcile clean"
else
  echo "[WARN] reconcile reported drift — DATA not code; review on prod/staging (--fix to repair)"
fi

echo ""
echo "========================================"
if [ "$FAIL" -eq 0 ]; then
  echo "RELEASE GATE: PASS"
  exit 0
fi
echo "RELEASE GATE: FAIL"
exit 1
