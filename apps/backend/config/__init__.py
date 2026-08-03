"""Expose the Celery app so tasks autoload when Django starts."""
try:
    from .celery import app as celery_app  # noqa: F401

    __all__ = ("celery_app",)
except Exception:  # pragma: no cover - Celery optional until jobs phase
    __all__ = ()
