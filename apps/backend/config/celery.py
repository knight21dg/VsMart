"""Celery app — used from the jobs phase onward (statements, reminders)."""
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")

app = Celery("vsmart")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
