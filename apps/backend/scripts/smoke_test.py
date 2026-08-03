"""In-process smoke test of the live API: OTP -> JWT -> /users/me -> register,
plus public catalog. Run: python scripts/smoke_test.py
Proves the wiring end-to-end without a running server or log scraping.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import django  # noqa: E402

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
django.setup()

from rest_framework.test import APIClient  # noqa: E402
from accounts import otp as otp_module  # noqa: E402
from accounts.models import User  # noqa: E402

# Capture the OTP code instead of "sending" it.
_captured = {}
_orig = otp_module.send_sms
otp_module.send_sms = lambda phone, code, purpose: _captured.update(code=code)

c = APIClient()
PHONE = "9123456789"

# Idempotent: remove test users so re-runs behave like a first run.
User.objects.filter(phone__in=["+919123456789", "+919000000001"]).delete()


def show(label, resp):
    print(f"\n# {label}  [{resp.status_code}]")
    print(resp.json())
    assert resp.status_code < 400, f"FAILED: {label}"


# 1. send OTP
r = c.post("/api/v1/auth/otp/send", {"phone": PHONE}, format="json")
show("POST /auth/otp/send", r)
vid = r.json()["data"]["verification_id"]
code = _captured["code"]
print(f"  captured code = {code}")

# 2. verify OTP -> tokens
r = c.post(
    "/api/v1/auth/otp/verify",
    {"phone": PHONE, "otp": code, "verificationId": vid},
    format="json",
)
show("POST /auth/otp/verify", r)
data = r.json()["data"]
assert data["is_new_user"] is True
access = data["access_token"]

# 3. authenticated /users/me
c.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
r = c.get("/api/v1/users/me")
show("GET /users/me", r)

# 4. complete profile
r = c.post("/api/v1/auth/register", {"name": "Smoke Test", "email": "s@x.com"}, format="json")
show("POST /auth/register", r)
assert r.json()["data"]["name"] == "Smoke Test"

# 5. wrong OTP is rejected
c.credentials()
r = c.post("/api/v1/auth/otp/send", {"phone": "9000000001"}, format="json")
vid2 = r.json()["data"]["verification_id"]
r = c.post(
    "/api/v1/auth/otp/verify",
    {"phone": "9000000001", "otp": "000000", "verificationId": vid2},
    format="json",
)
print(f"\n# wrong OTP rejected  [{r.status_code}] -> {r.json()['error']['code']}")
assert r.status_code == 400

# 6. public catalog
r = c.get("/api/v1/categories")
show("GET /categories", r)
r = c.get("/api/v1/products?page_size=2")
print(f"\n# GET /products  [{r.status_code}] total={r.json()['meta']['total']}")
assert r.status_code == 200

otp_module.send_sms = _orig
print("\nALL SMOKE CHECKS PASSED")
