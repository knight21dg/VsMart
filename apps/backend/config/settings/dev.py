"""Local development settings."""
import sys

from .base import *  # noqa: F401,F403
from .base import REST_FRAMEWORK, env  # noqa: F401

DEBUG = True
ALLOWED_HOSTS = ["*"]

# The mock payment gateway may accept unsigned webhooks / checkout callbacks here,
# so the whole payment flow runs end-to-end without live keys. Declared on the
# SETTINGS MODULE rather than derived from DEBUG because Django's test runner
# forces DEBUG=False — the deployment's identity is what matters, not that flag.
# prod.py sets this False; see payments.gateway.MockGateway.
PAYMENTS_TRUST_MOCK_GATEWAY = True

# Never hit real FCM during the test suite (keeps push tests hermetic even when a
# service account is configured in .env for the dev server).
if "test" in sys.argv:
    FIREBASE_CREDENTIALS = ""

# In-memory cache is fine for dev OTP storage; prod uses Redis.
CACHES = {
    "default": {
        "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
    }
}

# Throttling stays wired in dev but with effectively-unlimited rates, so local
# smoke runs and manual testing never hit 429. Prod uses the strict base rates.
REST_FRAMEWORK = {
    **REST_FRAMEWORK,
    "DEFAULT_THROTTLE_RATES": {
        "otp": "100000/min", "anon": "100000/min", "user": "100000/min",
        "checkout": "100000/min", "pos": "100000/min",
    },
}

# OTP codes print to the console in dev (SMS_PROVIDER=console).
# Plus a master code so phone testers can log in with any number: enter 123456.
OTP_DEV_BYPASS_CODE = "123456"
