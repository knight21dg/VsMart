"""Base settings shared by all environments."""
from datetime import timedelta
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env(
    DEBUG=(bool, False),
    ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
    GST_RATE=(float, 0.18),
    FREE_DELIVERY_THRESHOLD=(int, 499),
    DELIVERY_FEE=(int, 45),
    JWT_ACCESS_MINUTES=(int, 30),
    JWT_REFRESH_DAYS=(int, 30),
    SMS_PROVIDER=(str, "console"),
)
# Load .env if present (won't override real env vars in prod).
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env("SECRET_KEY", default="dev-insecure-key")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = env("ALLOWED_HOSTS")

INSTALLED_APPS = [
    # daphne must precede staticfiles so its ASGI runserver replaces the WSGI one.
    "daphne",
    "channels",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    # third-party
    "rest_framework",
    "rest_framework_simplejwt",
    "rest_framework_simplejwt.token_blacklist",
    "corsheaders",
    "django_filters",
    "drf_spectacular",
    # local
    "core",
    "accounts",
    "catalog",
    "addresses",
    "cart",
    "orders",
    "credit",
    "payments",
    "kyc",
    "mediastore",
    "offers",
    "notifications",
    "support",
    "referrals",
    "siteconfig",
    "stores",
    "zones",
    "geography",
    "inventory",
    "delivery",
    "verification",
    "billing",
    "cashcollections",
    "agents",
    "system",
    "reports",
    "ops",
    "pos",
    "accounting",
    # Phase 3 — customer engagement modules
    "content",
    "reviews",
    "returns",
    "loyalty",
    # Retained ONLY so 0002_delete_subscription runs and drops the table. The
    # feature was never finished (write-only: nothing ever generated an order)
    # and its code is gone. Delete this line and the app folder once the
    # migration has been applied everywhere.
    # Enterprise ops
    "crm",
    # Store-Admin panel (store-scoped staff RBAC + /store/* APIs)
    "storeops",
]

MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

# Channel layer for real-time WebSocket fan-out. Dev/test use the in-process
# in-memory layer (no Redis needed); prod overrides this with channels_redis.
CHANNEL_LAYERS = {
    "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"},
}

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ]
        },
    }
]

# Database — dev uses SQLite, prod overrides with DATABASE_URL (Postgres).
DATABASES = {"default": env.db("DATABASE_URL", default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}")}

AUTH_USER_MODEL = "accounts.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
     "OPTIONS": {"min_length": 8}},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Kolkata"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
# User-uploaded files (KYC documents, etc.). Served by Django in dev (config/urls);
# behind a CDN/object store in prod.
MEDIA_URL = "/media/"
MEDIA_ROOT = BASE_DIR / "media"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Self-hosted media pipeline (mediastore app). Limits + variant sizes for the
# WebP ingest; storage stays backend-agnostic via Django's STORAGES (filesystem
# on the VPS today, MinIO/S3 by swapping the default backend).
MEDIA_MAX_UPLOAD_BYTES = env.int("MEDIA_MAX_UPLOAD_BYTES", default=5 * 1024 * 1024)
MEDIA_ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"]
MEDIA_VARIANT_SIZES = {"thumb": 256, "medium": 1024, "original": 2048}
# When set (prod, behind Caddy/nginx) private media is streamed by the web server
# via X-Accel-Redirect after Django authorises — e.g. "/internal-media". Unset in
# dev, where Django streams the bytes itself.
MEDIA_INTERNAL_REDIRECT_PREFIX = env("MEDIA_INTERNAL_REDIRECT_PREFIX", default="")

# Default currency exposed to payment clients (Razorpay expects an ISO code).
PAYMENT_CURRENCY = "INR"

# ── Django REST Framework ────────────────────────────────
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": ("rest_framework.permissions.IsAuthenticated",),
    "DEFAULT_RENDERER_CLASSES": ("core.renderers.EnvelopeJSONRenderer",),
    "DEFAULT_PARSER_CLASSES": (
        "djangorestframework_camel_case.parser.CamelCaseJSONParser",
        "djangorestframework_camel_case.parser.CamelCaseMultiPartParser",
        "rest_framework.parsers.FormParser",
    ),
    "DEFAULT_PAGINATION_CLASS": "core.pagination.EnvelopePagination",
    "PAGE_SIZE": 20,
    "DEFAULT_FILTER_BACKENDS": (
        "django_filters.rest_framework.DjangoFilterBackend",
        "rest_framework.filters.SearchFilter",
        "rest_framework.filters.OrderingFilter",
    ),
    "EXCEPTION_HANDLER": "core.exceptions.api_exception_handler",
    # Throttling is enforced platform-wide (dev overrides the rates to be permissive
    # so local smoke runs never trip them). OTP stays strict everywhere.
    "DEFAULT_THROTTLE_CLASSES": (
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
        "rest_framework.throttling.ScopedRateThrottle",
    ),
    "DEFAULT_THROTTLE_RATES": {
        "otp": "5/min",
        "anon": "60/min",
        "user": "1000/min",
        "checkout": "30/min",
        "pos": "240/min",
    },
    # Render Decimals as JSON numbers (the app casts price/mrp as `num`).
    "COERCE_DECIMAL_TO_STRING": False,
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
}

SPECTACULAR_SETTINGS = {
    "TITLE": "VS Mart API",
    "DESCRIPTION": (
        "VS Mart — grocery commerce + BNPL credit platform. Modular-monolith Django/DRF "
        "backend serving the Customer app, Agent app, Admin and Super-Admin consoles, and "
        "(upcoming) POS.\n\n"
        "**Base URL:** `/api/v1`  ·  **Auth:** `Authorization: Bearer <access_token>` (JWT).\n\n"
        "**Response envelope** (all endpoints):\n"
        "```json\n{ \"success\": true, \"message\": \"\", \"data\": {}, \"meta\": {} }\n```\n"
        "Errors: `{ \"success\": false, \"message\": \"...\", \"error\": "
        "{ \"code\": \"...\", \"message\": \"...\", \"fields\": {} } }`.\n\n"
        "**Casing:** the auth/user endpoints use snake_case keys (access_token, kyc_status, …) "
        "to match the Flutter models; everything else is camelCase."
    ),
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
    "SCHEMA_PATH_PREFIX": "/api/v1",
    "POSTPROCESSING_HOOKS": [
        "drf_spectacular.hooks.postprocess_schema_enums",
        "core.openapi.envelope_responses",
    ],
    "SECURITY": [{"BearerAuth": []}],
    "APPEND_COMPONENTS": {
        "securitySchemes": {
            "BearerAuth": {"type": "http", "scheme": "bearer", "bearerFormat": "JWT"}
        }
    },
}

# Keep trailing numbers attached (so `line1` stays `line1`, not `line_1`).
# djangorestframework_camel_case namespaces its options under JSON_CAMEL_CASE
# (see its settings.py: USER_SETTINGS = getattr(settings, "JSON_CAMEL_CASE", {})).
JSON_CAMEL_CASE = {"JSON_UNDERSCOREIZE": {"no_underscore_before_number": True}}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=env("JWT_ACCESS_MINUTES")),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=env("JWT_REFRESH_DAYS")),
    # Rotation OFF for mobile robustness. With rotate+blacklist, every 30-min
    # refresh swapped the refresh token and KILLED the old one — if the app was
    # killed before persisting the new token (or secure storage hiccupped), the
    # session was unrecoverable: refresh 401 → forced sign-out mid-shopping.
    # Live symptom: refresh 200 at 22:51, token-less requests by 22:56. The
    # refresh token now stays valid for its full lifetime; logout still
    # blacklists it explicitly (accounts.views logout path).
    "ROTATE_REFRESH_TOKENS": False,
    "BLACKLIST_AFTER_ROTATION": False,
    "USER_ID_FIELD": "id",
    "USER_ID_CLAIM": "user_id",
}

# ── App / business config ────────────────────────────────
GST_RATE = env("GST_RATE")
FREE_DELIVERY_THRESHOLD = env("FREE_DELIVERY_THRESHOLD")
DELIVERY_FEE = env("DELIVERY_FEE")

# OTP
OTP_LENGTH = 6
OTP_TTL_SECONDS = 300
OTP_MAX_ATTEMPTS = 5
SMS_PROVIDER = env("SMS_PROVIDER")
# Dev-only master OTP (set in dev settings). Blank in prod → real OTP only.
OTP_DEV_BYPASS_CODE = env("OTP_DEV_BYPASS_CODE", default="")

# Minutes an unpaid order may hold its stock reservation before the sweep
# (orders/services.release_expired_reservations) auto-cancels it and frees the stock.
RESERVATION_TTL_MINUTES = env.int("RESERVATION_TTL_MINUTES", default=30)

# ── Tier-3 integrations (code-ready; activate by setting these in prod) ──
# Payment gateway (Razorpay). Blank → the mock gateway runs everything in dev/CI.
RAZORPAY_KEY_ID = env("RAZORPAY_KEY_ID", default="")
RAZORPAY_KEY_SECRET = env("RAZORPAY_KEY_SECRET", default="")
RAZORPAY_WEBHOOK_SECRET = env("RAZORPAY_WEBHOOK_SECRET", default="")
# SMS (MSG91). Used when SMS_PROVIDER=msg91; otherwise OTP prints to the console.
MSG91_AUTH_KEY = env("MSG91_AUTH_KEY", default="")
MSG91_OTP_TEMPLATE_ID = env("MSG91_OTP_TEMPLATE_ID", default="")
# SMS (smslogin.co). Used when SMS_PROVIDER=smslogin.
#
# This gateway takes the FULL message body plus a DLT template id — it does not
# render a template for us the way MSG91's OTP API does. Under Indian TRAI/DLT
# rules the body must match the registered template EXACTLY (only the variable
# parts may differ), otherwise the operator drops the message. So
# SMSLOGIN_OTP_MESSAGE is config, and `{code}` is substituted at send time.
SMSLOGIN_BASE_URL = env("SMSLOGIN_BASE_URL", default="https://smslogin.co/v3/api.php")
SMSLOGIN_USERNAME = env("SMSLOGIN_USERNAME", default="Vsmart")
SMSLOGIN_API_KEY = env("SMSLOGIN_API_KEY", default="a2fc04f1c219998a2ff1")
SMSLOGIN_SENDER_ID = env("SMSLOGIN_SENDER_ID", default="VSMRTS")
# Per-purpose DLT template ids + bodies live in `accounts/otp.py::DLT_TEMPLATES`
# — id and text are a matched pair that must not drift, so they are kept
# together there rather than as separate admin-editable fields. These two are
# only the fallback for a purpose with no registered template yet.
SMSLOGIN_TEMPLATE_ID = env("SMSLOGIN_TEMPLATE_ID", default="")
SMSLOGIN_OTP_MESSAGE = env("SMSLOGIN_OTP_MESSAGE", default="")
# Push (FCM). Used by notifications.services when a server key is configured.
FCM_SERVER_KEY = env("FCM_SERVER_KEY", default="")
# Google Maps server key (directions/geocoding/static) — admin-managed via the panel.
GOOGLE_MAPS_API_KEY = env("GOOGLE_MAPS_API_KEY", default="")
# KYC / identity verification (Setu). Blank/`mock` → the bundled mock verifier runs
# the whole flow in dev/CI without live keys. Set KYC_PROVIDER=setu plus the client
# credentials + per-product instance ids (from the Setu dashboard) to go live.
KYC_PROVIDER = env("KYC_PROVIDER", default="")           # ""|mock|setu (blank → mock)
SETU_BASE_URL = env("SETU_BASE_URL", default="https://prod.setu.co")
SETU_DG_BASE_URL = env("SETU_DG_BASE_URL", default="https://dg.setu.co")
SETU_CLIENT_ID = env("SETU_CLIENT_ID", default="")
SETU_CLIENT_SECRET = env("SETU_CLIENT_SECRET", default="")
SETU_PAN_PRODUCT_ID = env("SETU_PAN_PRODUCT_ID", default="")
SETU_DIGILOCKER_PRODUCT_ID = env("SETU_DIGILOCKER_PRODUCT_ID", default="")
SETU_AADHAAR_PRODUCT_ID = env("SETU_AADHAAR_PRODUCT_ID", default="")
SETU_BANK_PRODUCT_ID = env("SETU_BANK_PRODUCT_ID", default="")
# KYC — Signzy (recommended production provider). Set KYC_PROVIDER=signzy + either
# SIGNZY_API_KEY or SIGNZY_USERNAME/SIGNZY_PASSWORD to go live.
SIGNZY_BASE_URL = env("SIGNZY_BASE_URL", default="https://api.signzy.app")
SIGNZY_API_KEY = env("SIGNZY_API_KEY", default="")
SIGNZY_USERNAME = env("SIGNZY_USERNAME", default="")
SIGNZY_PASSWORD = env("SIGNZY_PASSWORD", default="")
# KYC — Cashfree Secure ID (Verification Suite must be enabled on the account).
CASHFREE_BASE_URL = env("CASHFREE_BASE_URL", default="https://api.cashfree.com/verification")
CASHFREE_APP_ID = env("CASHFREE_APP_ID", default="")
CASHFREE_SECRET_KEY = env("CASHFREE_SECRET_KEY", default="")
CASHFREE_API_VERSION = env("CASHFREE_API_VERSION", default="2022-10-26")

# Credit bureau (CIBIL score pull, by mobile number) — Payon.
# NOTE the `reseller.` host: the bare apipayon.in host rejects reseller keys with
# "Invalid API key", which is what made every CIBIL surface look broken.
# Override via env / the super-admin panel for production — a value saved in the
# panel is stored in the DB and WINS over both env and these defaults.
CREDIT_BUREAU_PROVIDER = env("CREDIT_BUREAU_PROVIDER", default="payon")
CREDIT_BUREAU_BASE_URL = env(
    "CREDIT_BUREAU_BASE_URL",
    default="https://reseller.apipayon.in/api/v1/serv2/check_credit_score.php")
CREDIT_BUREAU_API_KEY = env(
    "CREDIT_BUREAU_API_KEY", default="G6kXYi8HJHOmCxvPDUScsI83xe3OgxNZ")

# Email (password reset, transactional). With no EMAIL_HOST set, the console
# backend prints mail to the server log; set EMAIL_HOST etc. to send real SMTP.
EMAIL_HOST = env("EMAIL_HOST", default="")
EMAIL_BACKEND = env("EMAIL_BACKEND", default=(
    "django.core.mail.backends.smtp.EmailBackend" if EMAIL_HOST
    else "django.core.mail.backends.console.EmailBackend"))
EMAIL_PORT = env.int("EMAIL_PORT", default=587)
EMAIL_HOST_USER = env("EMAIL_HOST_USER", default="")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD", default="")
EMAIL_USE_TLS = env.bool("EMAIL_USE_TLS", default=True)
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", default="VS Mart <no-reply@thevsmart.com>")

# Push (FCM HTTP v1): a path to the service-account JSON, or the JSON itself.
# Empty (dev default) → push is a clean no-op. See notifications/push.py.
FIREBASE_CREDENTIALS = env("FIREBASE_CREDENTIALS", default="")

# Public HTTPS URL of the VS Mart logo, attached to every push as the notification
# image so the bubble carries the brand (Android's small status-bar icon is forced
# monochrome, so the logo rides in the big-picture/large-icon `image` field). A
# per-campaign hero image overrides it. See notifications/push.py.
NOTIFICATION_LOGO_URL = env(
    "NOTIFICATION_LOGO_URL", default="https://thevsmart.com/assets/vsmart-logo.png"
)

# Where a web-push notification's click should land (store-admin panel). Used
# only to build the `data.route` deep link into an absolute URL for browser
# notifications — mobile pushes route via the app's own deep-link handling.
STORE_ADMIN_URL = env("STORE_ADMIN_URL", default="https://store.thevsmart.com")

CORS_ALLOW_ALL_ORIGINS = DEBUG  # tighten in prod via CORS_ALLOWED_ORIGINS
# The POS sends a custom `Idempotency-Key` header on checkout/sync; it must be in the
# CORS allow-list or the browser blocks the preflighted request (net::ERR_FAILED).
from corsheaders.defaults import default_headers as _cors_default_headers  # noqa: E402

CORS_ALLOW_HEADERS = (*_cors_default_headers, "idempotency-key")
