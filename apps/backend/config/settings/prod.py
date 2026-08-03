"""Production settings (VPS / Docker)."""
from .base import *  # noqa: F401,F403
from .base import env

DEBUG = False

# The mock gateway must NEVER accept a webhook or checkout callback in production:
# the webhook endpoint is unauthenticated by design, so a trusting mock would let
# anyone mark any order paid. Real keys are required to take money here — and
# payments.gateway.get_gateway() additionally refuses to fall back to the mock
# when keys ARE configured but the SDK can't be constructed.
PAYMENTS_TRUST_MOCK_GATEWAY = False

# A real, long secret is mandatory in prod — fail fast if it's unset rather than
# silently running on the insecure dev default.
SECRET_KEY = env("SECRET_KEY")

# Error monitoring (optional). Set SENTRY_DSN to enable; needs `sentry-sdk` installed.
SENTRY_DSN = env("SENTRY_DSN", default="")
if SENTRY_DSN:
    try:
        import sentry_sdk
        from sentry_sdk.integrations.django import DjangoIntegration

        sentry_sdk.init(
            dsn=SENTRY_DSN,
            integrations=[DjangoIntegration()],
            traces_sample_rate=env.float("SENTRY_TRACES_SAMPLE_RATE", default=0.1),
            send_default_pii=False,
            environment=env("ENVIRONMENT", default="production"),
        )
    except ImportError:  # sentry-sdk not installed → run without monitoring
        pass

# Redis cache + OTP store.
CACHES = {
    "default": {
        "BACKEND": "django_redis.cache.RedisCache",
        "LOCATION": env("REDIS_URL", default="redis://redis:6379/0"),
    }
}

# Real-time channel layer over Redis (replaces the dev in-memory layer) so live
# delivery/order-tracking events fan out across all ASGI worker processes.
CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [env("REDIS_URL", default="redis://redis:6379/0")]},
    }
}

# Security headers (Caddy terminates TLS in front).
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SECURE_SSL_REDIRECT = False  # Caddy already forces HTTPS
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = 31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_CONTENT_TYPE_NOSNIFF = True

CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])

# Required for the Django admin (session+CSRF) and any cookie-auth POSTs over HTTPS
# behind the Caddy proxy — e.g. ["https://api.thevsmart.com"].
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

# Object storage (django-storages → MinIO/R2). Enabled once file uploads land.
# DEFAULT_FILE_STORAGE = "storages.backends.s3boto3.S3Boto3Storage"
