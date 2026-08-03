"""Delete expired throwaway uploads.

Anything in the ``temp`` category older than ``--hours`` (default 24) is removed
along with its stored files — covers abandoned multi-step uploads where the user
never committed the asset to a real record. Run nightly from cron.

    python manage.py media_cleanup            # delete temp assets > 24h old
    python manage.py media_cleanup --hours 48 --dry-run
"""
from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from mediastore.models import MediaAsset
from mediastore.services import delete_asset


class Command(BaseCommand):
    help = "Delete expired temp media assets and their files."

    def add_arguments(self, parser):
        parser.add_argument("--hours", type=int, default=24,
                            help="Age threshold in hours (default 24).")
        parser.add_argument("--category", default="temp",
                            help="Category to sweep (default 'temp').")
        parser.add_argument("--dry-run", action="store_true",
                            help="Report what would be deleted without deleting.")

    def handle(self, *args, **opts):
        cutoff = timezone.now() - timedelta(hours=opts["hours"])
        qs = MediaAsset.objects.filter(
            category=opts["category"], created_at__lt=cutoff
        )
        count = qs.count()
        if opts["dry_run"]:
            self.stdout.write(
                f"[dry-run] would delete {count} '{opts['category']}' asset(s) "
                f"older than {opts['hours']}h"
            )
            return
        for asset in qs:
            delete_asset(asset)
        self.stdout.write(
            self.style.SUCCESS(
                f"Deleted {count} expired '{opts['category']}' asset(s)."
            )
        )
