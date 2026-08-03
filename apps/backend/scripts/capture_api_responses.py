"""Call every customer-facing API as the seeded demo customer and capture the
real response for each case — success AND key error cases. Writes a readable
reference to docs/API_SAMPLE_RESPONSES.md and prints a pass/fail summary.

    python scripts/capture_api_responses.py     (run `manage.py seed_app` first)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
import django  # noqa: E402

django.setup()

from rest_framework.test import APIClient  # noqa: E402

from accounts.models import User  # noqa: E402
from catalog.models import Category, Product  # noqa: E402
from orders.models import Order  # noqa: E402
from support.models import SupportTicket  # noqa: E402

PHONE = "+919000000007"
BASE = "/api/v1"


def main():
    user = User.objects.filter(phone=PHONE).first()
    if not user:
        print("Demo customer missing — run `python manage.py seed_app` first.")
        sys.exit(1)

    client = APIClient()
    client.force_authenticate(user=user)

    # Reference ids from the seeded data.
    cat = Category.objects.filter(parent__isnull=True).first()
    product = Product.objects.filter(is_active=True).first()
    order = Order.objects.filter(user=user).order_by("id").first()
    active_order = Order.objects.filter(user=user, status="out_for_delivery").first()
    ticket = SupportTicket.objects.filter(user=user).first()

    # (group, label, method, path, body)
    cases = [
        # ── System / bootstrap ──
        ("System", "Health", "GET", "/health", None),
        ("System", "App config", "GET", "/app-config", None),
        ("System", "Feature flags", "GET", "/feature-flags", None),
        # ── Auth / profile ──
        ("Auth", "Send OTP", "POST", "/auth/otp/send", {"phone": PHONE}),
        ("Auth", "Current user", "GET", "/users/me", None),
        # ── Catalog ──
        ("Catalog", "Departments", "GET", "/categories", None),
        ("Catalog", "Sub-categories", "GET", f"/categories/{cat.id}/sub-categories", None),
        ("Catalog", "Products (page 1)", "GET", "/products?page=1&page_size=5", None),
        ("Catalog", "Product detail", "GET", f"/products/{product.id}", None),
        ("Catalog", "Search", "GET", "/products/search?q=milk", None),
        ("Catalog", "Product not found (error)", "GET", "/products/99999999", None),
        # ── Cart ──
        ("Cart", "Cart", "GET", "/cart", None),
        ("Cart", "Cart quote", "POST", "/cart/quote",
         {"items": [{"productId": product.id, "quantity": 2}]}),
        ("Cart", "Wishlist", "GET", "/wishlist", None),
        # ── Orders ──
        ("Orders", "Order list", "GET", "/orders", None),
        ("Orders", "Active orders", "GET", "/orders?status=active", None),
        ("Orders", "Order detail", "GET", f"/orders/{order.code}", None),
        ("Orders", "Live tracking", "GET",
         f"/orders/{(active_order or order).code}/tracking", None),
        # ── Credit ──
        ("Credit", "Dashboard", "GET", "/credit/dashboard", None),
        ("Credit", "Ledger", "GET", "/credit/ledger", None),
        ("Credit", "Statements", "GET", "/credit/statements", None),
        ("Credit", "Outstanding", "GET", "/credit/outstanding", None),
        # ── Billing / payments ──
        ("Billing", "Invoices", "GET", "/billing/invoices", None),
        ("Billing", "Payment history", "GET", "/payments/history", None),
        # ── Offers / coupons ──
        ("Offers", "Offers", "GET", "/offers", None),
        ("Offers", "Coupon wallet", "GET", "/coupons/wallet", None),
        ("Offers", "Coupon validate (valid)", "POST", "/coupons/validate",
         {"code": "VS100", "cartTotal": 1200}),
        ("Offers", "Coupon validate (invalid, error)", "POST", "/coupons/validate",
         {"code": "NOPE000", "cartTotal": 1200}),
        # ── KYC ──
        ("KYC", "Status", "GET", "/kyc/status", None),
        # ── Addresses ──
        ("Addresses", "List", "GET", "/addresses", None),
        # ── Notifications ──
        ("Notifications", "Inbox", "GET", "/notifications", None),
        ("Notifications", "Preferences", "GET", "/notifications/preferences", None),
        # ── Support ──
        ("Support", "FAQs", "GET", "/support/faqs", None),
        ("Support", "Tickets", "GET", "/support/tickets", None),
        ("Support", "Ticket detail", "GET",
         f"/support/tickets/{ticket.code}" if ticket else "/support/tickets", None),
        # ── Loyalty / referrals ──
        ("Loyalty", "Status", "GET", "/loyalty", None),
        ("Loyalty", "Ledger", "GET", "/loyalty/ledger", None),
        ("Loyalty", "Redeem too many (actionable error)", "POST", "/loyalty/redeem",
         {"points": 9999999}),
        ("Referrals", "Referral", "GET", "/referrals", None),
        ("Referrals", "Invalid code (actionable error)", "POST", "/referrals/apply",
         {"code": "NOPE000"}),
        # ── Returns / reviews ──
        ("Returns", "List", "GET", "/returns", None),
        ("Reviews", "Product reviews", "GET", f"/products/{product.id}/reviews", None),
        ("Reviews", "My reviews", "GET", "/reviews/mine", None),
        # ── Serviceability ──
        ("Serviceability", "Serviceable", "GET",
         "/serviceability/check?lat=12.97&lng=77.6&pincode=560038", None),
        ("Serviceability", "Not serviceable", "GET",
         "/serviceability/check?lat=0&lng=0&pincode=000000", None),
        # ── Content ──
        ("Content", "Terms page", "GET", "/content/pages/terms", None),
    ]

    out = ["# VS Mart — Sample API Responses (every customer case)\n",
           f"_Captured as the seeded demo customer ({PHONE}). "
           f"Run `python manage.py seed_app` then this script to regenerate._\n"]
    ok = bad = 0
    group = None
    print(f"{'STATUS':<7} {'METHOD':<5} PATH")
    print("-" * 70)
    for grp, label, method, path, body in cases:
        url = f"{BASE}{path}"
        try:
            if method == "GET":
                resp = client.get(url)
            else:
                resp = client.post(url, body, format="json")
            code = resp.status_code
            try:
                payload = resp.json()
            except Exception:
                payload = {"_raw": resp.content.decode("utf-8", "replace")[:300]}
        except Exception as e:  # noqa: BLE001
            code, payload = "ERR", {"_exception": str(e)}

        # 2xx, plus 404/400 for the intentional error cases, count as expected.
        expected_error = "error" in label.lower() or "not found" in label.lower() \
            or "not serviceable" in label.lower()
        good = (isinstance(code, int) and 200 <= code < 300) or \
               (expected_error and isinstance(code, int) and 400 <= code < 500)
        ok += good
        bad += not good
        flag = "OK " if good else "!! "
        print(f"{flag}{str(code):<4} {method:<5} {path}")

        if grp != group:
            out.append(f"\n## {grp}\n")
            group = grp
        snippet = json.dumps(payload, indent=2, default=str)
        if len(snippet) > 1400:
            snippet = snippet[:1400] + "\n  … (truncated)"
        out.append(f"### {label}\n`{method} {BASE}{path}` → **{code}**\n\n"
                   f"```json\n{snippet}\n```\n")

    docs_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
    os.makedirs(docs_dir, exist_ok=True)
    md_path = os.path.join(docs_dir, "API_SAMPLE_RESPONSES.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))

    print("-" * 70)
    print(f"  {ok} OK, {bad} unexpected out of {len(cases)} cases.")
    print(f"  Wrote {md_path}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
