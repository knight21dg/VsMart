"""Resolve online cash hand-overs an agent never came back to confirm.

    python manage.py sweep_stale_handovers [--minutes 30] [--limit 200]
"""
from django.core.management.base import BaseCommand

from payments.cashbook_services import sweep_stale_handovers


class Command(BaseCommand):
    help = "Settle or cancel INITIATED cash hand-overs stuck awaiting payment."

    def add_arguments(self, parser):
        parser.add_argument(
            "--minutes", type=int, default=30,
            help="Only consider hand-overs older than this (default: 30).",
        )
        parser.add_argument(
            "--limit", type=int, default=200,
            help="Maximum hand-overs to check in one pass (default: 200).",
        )

    def handle(self, *args, **options):
        summary = sweep_stale_handovers(
            older_than_minutes=options["minutes"], limit=options["limit"],
        )
        self.stdout.write(
            "checked={checked} verified={verified} cancelled={cancelled} "
            "errors={errors}".format(**summary)
        )
        if summary["verified"]:
            self.stdout.write(self.style.SUCCESS(
                f"Recovered {summary['verified']} paid hand-over(s) nobody confirmed."
            ))
