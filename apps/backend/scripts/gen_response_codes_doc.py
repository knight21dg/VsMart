"""Generate docs/API_RESPONSE_CODES.md from the response catalog (single source
of truth). Run after changing core/response_codes.py.

    python scripts/gen_response_codes_doc.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
import django  # noqa: E402

django.setup()

from core.response_codes import CATALOG  # noqa: E402

MODULE_TITLES = {
    "system": "System / Generic", "auth": "Auth / Registration", "security": "Security",
    "zone": "Zone / Serviceability", "kyc": "KYC / Verification", "credit": "Credit",
    "orders": "Ordering", "payments": "Payments", "finance": "Finance",
    "delivery": "Delivery", "collections": "Collections", "inventory": "Inventory",
    "procurement": "Procurement", "store": "Store Admin", "employee": "Employee",
    "support": "Support / CRM", "offers": "Offers / Coupons", "loyalty": "Loyalty",
    "referrals": "Referrals", "returns": "Returns",
    "reporting": "Reporting",
}


def _action(a):
    if not a:
        return "—"
    t = a.get("type")
    return f"`{t}`" + (f" → `{a['target']}`" if a.get("target") else "")


def main():
    by_module = {}
    for code, spec in CATALOG.items():
        by_module.setdefault(spec["module"], []).append((code, spec))

    out = [
        "# VS Mart — API Response Code Catalog\n",
        f"_{len(CATALOG)} machine-readable codes. Single source of truth: "
        "`core/response_codes.py`. Served live at `GET /api/v1/response-codes` "
        "(optionally `?module=credit`)._\n",
        "Every coded response carries: `success, code, title, message, action, "
        "retryable, severity, nextStep` (camelCase on the wire) plus a back-compat "
        "`error:{code,message,fields}`. Failures also write an `AuditLog` row.\n",
        "**Action types:** `navigate`(+target) · `retry` · `retry_verification` · "
        "`logout` · `reauth` · `contact_support` · `refresh`.\n",
    ]
    for module in MODULE_TITLES:
        rows = by_module.get(module)
        if not rows:
            continue
        out.append(f"\n## {MODULE_TITLES[module]}\n")
        out.append("| Code | HTTP | Severity | Title | Message | Action | Retry |")
        out.append("|------|------|----------|-------|---------|--------|-------|")
        for code, s in rows:
            kind = "✅" if s["success"] else ""
            out.append(
                f"| `{code}` {kind} | {s['http']} | {s['severity']} | {s['title']} | "
                f"{s['message']} | {_action(s['action'])} | "
                f"{'yes' if s['retryable'] else '—'} |"
            )
    docs_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
    os.makedirs(docs_dir, exist_ok=True)
    path = os.path.join(docs_dir, "API_RESPONSE_CODES.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"Wrote {path} ({len(CATALOG)} codes across {len(by_module)} modules)")


if __name__ == "__main__":
    main()
