"""Close complete credit billing cycles + age the book. Idempotent; cron-safe.

    python manage.py generate_statements
"""
from django.core.management.base import BaseCommand

from credit.statement_services import close_billing_cycles


class Command(BaseCommand):
    help = "Generate statements for complete billing cycles and mark overdue ones."

    def handle(self, *args, **opts):
        result = close_billing_cycles()
        self.stdout.write(self.style.SUCCESS(
            f"statements={result['statements']} "
            f"marked_overdue={result['marked_overdue']}"))
