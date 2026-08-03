"""Release stock held by abandoned (unpaid) orders past the reservation TTL.

    python manage.py release_expired_reservations [--ttl MINUTES]

Wire to cron or Celery beat (e.g. every 5 minutes) in production.
"""
from django.core.management.base import BaseCommand

from orders.services import release_expired_reservations


class Command(BaseCommand):
    help = "Cancel unpaid orders whose stock reservation has expired, freeing stock."

    def add_arguments(self, parser):
        parser.add_argument(
            "--ttl", type=int, default=None,
            help="Override RESERVATION_TTL_MINUTES for this run.",
        )

    def handle(self, *args, **options):
        cancelled = release_expired_reservations(ttl_minutes=options.get("ttl"))
        self.stdout.write(
            self.style.SUCCESS(
                f"Released {len(cancelled)} expired reservation(s): {cancelled}"
            )
        )
