"""Introspect the live URLconf + DRF permissions to emit:
  - docs/api/postman_collection.json  (all endpoints, grouped by module, Bearer auth)
  - docs/api/api-coverage-report.md    (counts by access tier + module)
Run: python scripts/gen_api_docs.py
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from django.urls import get_resolver  # noqa: E402
from django.urls.resolvers import URLPattern, URLResolver  # noqa: E402
from rest_framework.views import APIView  # noqa: E402

HTTP = ("get", "post", "put", "patch", "delete")


def _methods(cb):
    if hasattr(cb, "actions"):  # router viewset
        return [m.upper() for m in cb.actions]
    cls = getattr(cb, "cls", None)
    if cls is None:
        return []
    return [m.upper() for m in HTTP if m in cls.http_method_names and hasattr(cls, m)]


def _category(cls):
    if cls is None:
        return "unknown"
    auth = getattr(cls, "authentication_classes", None)
    perms = [p.__name__ for p in getattr(cls, "permission_classes", []) or []]
    if "AllowAny" in perms or (auth is not None and len(auth) == 0 and not perms):
        return "public"
    if cls.get_permissions is not APIView.get_permissions:
        return "admin (dynamic)"  # get_permissions branches by role (config/zones)
    if "IsSuperAdmin" in perms:
        return "superadmin"
    if "IsAdmin" in perms:
        return "admin"
    if "IsAgent" in perms:
        return "agent"
    if "IsCustomer" in perms:
        return "customer"
    return "authenticated"


def _clean(path):
    """Normalise router regex (^addresses/(?P<pk>[^/.]+)$) to a path template."""
    path = path.replace("^", "").replace("$", "")
    path = re.sub(r"\(\?P<(\w+)>[^)]+\)", r"<\1>", path)
    return path


def walk(resolver, prefix=""):
    out = []
    for p in resolver.url_patterns:
        if isinstance(p, URLResolver):
            out += walk(p, prefix + str(p.pattern))
        elif isinstance(p, URLPattern):
            path = _clean(prefix + str(p.pattern))
            if not path.startswith("api/v1/"):
                continue
            cls = getattr(p.callback, "cls", None)
            for m in _methods(p.callback):
                out.append((m, "/" + path, cls))
    return out


routes = walk(get_resolver())
routes.sort(key=lambda r: (r[1], r[0]))

# ---- Postman collection ----
def pm_path(path):
    # /api/v1/products/<int:pk> -> [api, v1, products, :pk]
    segs = []
    for s in path.strip("/").split("/"):
        if s.startswith("<") and s.endswith(">"):
            segs.append(":" + s.strip("<>").split(":")[-1])
        else:
            segs.append(s)
    return segs


folders = {}
for method, path, cls in routes:
    segs = path.strip("/").split("/")
    module = segs[2] if len(segs) > 2 else "root"
    folders.setdefault(module, []).append({
        "name": f"{method} {path}",
        "request": {
            "method": method,
            "header": [{"key": "Authorization", "value": "Bearer {{access_token}}"},
                       {"key": "Content-Type", "value": "application/json"}],
            "url": {"raw": "{{base_url}}" + path,
                    "host": ["{{base_url}}"], "path": pm_path(path)},
        },
    })

collection = {
    "info": {"name": "VS Mart API", "schema":
             "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
             "description": "VS Mart API — base {{base_url}}, JWT {{access_token}}."},
    "variable": [{"key": "base_url", "value": "http://localhost:8000/api/v1"},
                 {"key": "access_token", "value": ""}],
    "item": [{"name": mod, "item": items} for mod, items in sorted(folders.items())],
}
os.makedirs("docs/api", exist_ok=True)
with open("docs/api/postman_collection.json", "w", encoding="utf-8") as f:
    json.dump(collection, f, indent=2)

# ---- Coverage report ----
from collections import Counter

by_cat = Counter(_category(cls) for _, _, cls in routes)
by_mod = Counter(p.strip("/").split("/")[2] for _, p, _ in routes if len(p.strip("/").split("/")) > 2)
total = len(routes)
public = by_cat.get("public", 0)


def table(counter, header):
    rows = "\n".join(f"| {k} | {v} |" for k, v in sorted(counter.items(), key=lambda x: -x[1]))
    return f"| {header} | Count |\n|---|---|\n{rows}\n"


report = f"""# API Coverage Report

Generated from the live URL resolver + DRF permission classes (the source of truth).

- **Total operations:** {total}  (path × method)
- **Public (no auth):** {public}
- **Authenticated:** {total - public}

## By access tier
{table(by_cat, "Access tier")}
> `admin (dynamic)` = views that branch permissions per-method via `get_permissions`
> (read = admin, write = superadmin), e.g. platform config and zones.

## By module
{table(by_mod, "Module")}

## Artifacts
- `docs/api/openapi.yaml` — OpenAPI 3.0 spec (all operations, envelope-wrapped).
- `docs/api/swagger.json` — same, JSON.
- `docs/api/postman_collection.json` — this run.
- Live docs: `/api/docs/` (Swagger UI), `/api/redoc/` (ReDoc), `/api/schema/` (raw).
"""
with open("docs/api/api-coverage-report.md", "w", encoding="utf-8") as f:
    f.write(report)

print(f"Postman: {sum(len(v) for v in folders.values())} requests in {len(folders)} folders")
print(f"Coverage: {total} operations | public={public} | tiers={dict(by_cat)}")
