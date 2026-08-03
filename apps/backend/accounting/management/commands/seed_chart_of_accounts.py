from django.core.management.base import BaseCommand

from accounting.chart import seed


class Command(BaseCommand):
    help = "Create the default chart of accounts. Safe to re-run."

    def handle(self, *args, **options):
        created = seed(stdout=self.stdout)
        if created:
            self.stdout.write(self.style.SUCCESS(
                f"Chart of accounts ready ({created} added)."
            ))
        else:
            self.stdout.write("Chart of accounts already complete; nothing added.")
