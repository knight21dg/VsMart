"""Dump the REAL wire shape of every admin API endpoint.

Why this exists: the console reads fields by name, and the response passes
through ``EnvelopeJSONRenderer`` (camelCase). Nothing checked that the names the
console reads are the names the API actually emits — so a rail keyed by
``today_deals`` silently read an empty list for months, and no test noticed
because the key it asserted on (``popular``) happened to survive camelCasing.

This walks the URLconf for every ``admin/`` route, calls it as a superadmin
against a seeded database, and records the exact key paths that come back. Pair
it with ``extract_admin_api_usage.mjs`` (which records what the console reads)
and diff the two: anything the console reads that never appears here is a field
that will always be undefined at runtime.

    python scripts/admin_contract_dump.py            # writes admin_contract.json
    python scripts/admin_contract_dump.py --print    # …and prints a summary

Runs against a throwaway test database, so it never touches dev or prod data.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")

import django  # noqa: E402

django.setup()

from django.test.utils import get_runner  # noqa: E402
from django.conf import settings  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "admin_contract.json")

#: Endpoints that are deliberately skipped, with the reason. A skip is a hole in
#: the coverage, so it has to be justified here rather than silently dropped.
SKIP = {
    "admin/settings/integrations": "writes provider credentials",
}


def _key_paths(node, prefix=""):
    """Every key path in a decoded JSON body, as dotted strings.

    Lists contribute their FIRST element's shape (``items[].name``) — the rows in
    an admin list are homogeneous, and walking all of them just repeats keys.
    """
    out = set()
    if isinstance(node, dict):
        for key, value in node.items():
            path = f"{prefix}.{key}" if prefix else key
            out.add(path)
            out |= _key_paths(value, path)
    elif isinstance(node, list) and node:
        out |= _key_paths(node[0], f"{prefix}[]")
    return out


def _clean(route):
    """Normalise a route string. DRF's SimpleRouter contributes regex patterns,
    so a route can arrive as ``api/v1/^admin/zones/(?P<pk>[^/.]+)$``."""
    route = route.replace("^", "").replace("$", "").replace("\\", "")
    while "(?P<" in route:
        start = route.index("(?P<")
        name_end = route.index(">", start)
        name = route[start + 4:name_end]
        depth, i = 0, start
        for i in range(start, len(route)):
            if route[i] == "(":
                depth += 1
            elif route[i] == ")":
                depth -= 1
                if depth == 0:
                    break
        route = route[:start] + f"<{name}>" + route[i + 1:]
    return route


def collect_admin_routes():
    """Every GET-able ``admin/`` route in the URLconf, with its parameter names."""
    from django.urls import get_resolver
    from django.urls.resolvers import URLPattern, URLResolver

    routes = []

    def walk(resolver, prefix=""):
        for entry in resolver.url_patterns:
            if isinstance(entry, URLResolver):
                walk(entry, prefix + str(entry.pattern))
            elif isinstance(entry, URLPattern):
                route = _clean(prefix + str(entry.pattern))
                # Only the versioned API. Django's own /admin/ (the 491-route
                # model admin) is not what the console talks to.
                if not route.startswith("api/v1/") or "admin/" not in route:
                    continue
                callback = entry.callback
                methods = getattr(callback, "actions", None)
                if methods is not None and "get" not in methods:
                    continue
                cls = getattr(callback, "cls", getattr(callback, "view_class", None))
                if cls is not None and methods is None:
                    if not any(hasattr(cls, m) for m in ("get", "list", "retrieve")):
                        continue
                params = list(entry.pattern.converters) or re.findall(r"<(\w+)>", route)
                routes.append({
                    "route": route[len("api/v1/"):],
                    "params": params,
                    "view": getattr(cls, "__name__", str(callback)),
                })

    walk(get_resolver())
    return routes


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--print", action="store_true", dest="show")
    parser.add_argument(
        "--panel", choices=("admin", "store"), default="admin",
        help="Which console to sweep. `store` authenticates as a store manager "
             "instead of a superadmin, because /store/* is gated on an active "
             "StoreStaff membership, not on the platform role.",
    )
    args = parser.parse_args()

    usage = USAGE if args.panel == "admin" else USAGE.replace(
        "admin_api_usage.json", "store_api_usage.json"
    )
    out = OUT if args.panel == "admin" else OUT.replace(
        "admin_contract.json", "store_contract.json"
    )

    runner = get_runner(settings)(verbosity=0, interactive=False)
    old_config = runner.setup_databases()
    try:
        result = _run(show=args.show, usage_path=usage, panel=args.panel)
    finally:
        runner.teardown_databases(old_config)

    with open(out, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2, sort_keys=True)
    print(f"\nwrote {out}  ({len(result['endpoints'])} endpoints)")


#: The console's own call list, produced by `apps/admin/scripts/extract-api-usage.mjs`.
#: Driving the dump from it (rather than from the URLconf) guarantees the check
#: covers exactly what the console depends on — walking `admin/` routes alone
#: missed every `/inventory/*` and `/reports/*` call the console makes.
USAGE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "admin_api_usage.json")


#: Generic template names (`${code}`, `${id}`) mean different objects on
#: different routes, so the path decides which seeded row to use. Without this a
#: return code was sent to the support endpoint and both came back 404 —
#: a miss that reads exactly like a broken endpoint.
BY_PATH = (
    ("/returns/", "code", "returns_code"),
    ("/support/", "code", "support_code"),
    ("/crm/customers/", "id", "customer"),
)


def _substitute(path, ids):
    """Turn `/admin/zones/${zoneId}` into a callable path, or None if we have no
    id for it. Template names are the console's variable names, so match on the
    trailing noun (`zoneId` -> zone) rather than demanding an exact key."""
    out = path
    for token in re.findall(r"\$\{([^}]*)\}", path):
        value = None
        for fragment, name, key in BY_PATH:
            if fragment in path and token == name:
                value = ids.get(key)
                break
        if value is None:
            value = ids.get(token)
        if value is None:
            key = re.sub(r"(Id|_id)$", "", token).lower()
            value = ids.get(key) or ids.get(f"{key}_id")
        if value is None:
            return None
        out = out.replace("${" + token + "}", str(value))
    return out


def _run(*, show, usage_path=None, panel="admin"):
    from rest_framework.test import APIClient

    from accounts.models import User

    from scripts._contract_seed import seed_reference_data, seed_store_manager

    ids = seed_reference_data()

    client = APIClient()
    if panel == "store":
        # A manager implicitly holds every permission, so one login reaches every
        # page — anything that still 403s is a genuine wiring fault, not a
        # missing grant.
        client.force_authenticate(seed_store_manager(ids))
    else:
        client.force_authenticate(User.objects.create(
            phone="+919000009999", name="Contract Bot", role="superadmin"
        ))

    endpoints, failures, skipped = {}, [], []

    with open(usage_path or USAGE, encoding="utf-8") as fh:
        calls = json.load(fh)["calls"]

    seen = set()
    for call in sorted(calls, key=lambda c: c["path"]):
        template = call["path"]
        if template in seen:
            continue
        seen.add(template)
        if template.lstrip("/") in SKIP:
            skipped.append({"route": template, "reason": SKIP[template.lstrip("/")]})
            continue
        path = _substitute(template, ids)
        if path is None:
            skipped.append({"route": template, "reason": "no seeded id for its parameter"})
            continue

        response = client.get("/api/v1/" + path.lstrip("/"))
        record = {"status": response.status_code, "calledAs": path}
        if response.status_code >= 500:
            failures.append({"route": template, "status": response.status_code})
        try:
            body = response.json()
        except Exception:
            body = None
        if isinstance(body, dict):
            record["keys"] = sorted(_key_paths(body.get("data")))
            record["empty"] = not body.get("data")
        endpoints[template] = record
        if show:
            print(f"{response.status_code}  {path}")

    return {"endpoints": endpoints, "failures": failures, "skipped": skipped}


if __name__ == "__main__":
    main()
