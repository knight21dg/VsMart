"""Ask the gateway what happened to payments we never heard back about.

An online payment normally settles via the app's confirm call or the webhook. When
neither arrives — the app was killed after the money was captured, or the webhook
was lost — the payment sits PENDING and the order looks unpaid. Run this on a
schedule so captured money is always reconciled against its order.

    python manage.py reconcile_payments [--minutes 10] [--limit 200]
"""
from django.core.management.base import BaseCommand

from payments.services import reconcile_pending_payments


class Command(BaseCommand):
    help = "Reconcile PENDING gateway payments against the payment gateway."

    def add_arguments(self, parser):
        parser.add_argument(
            "--minutes", type=int, default=10,
            help="Only consider payments older than this, so a checkout still in "
                 "progress is never touched (default: 10).",
        )
        parser.add_argument(
            "--limit", type=int, default=200,
            help="Maximum payments to check in one pass (default: 200).",
        )

    def handle(self, *args, **options):
        summary = reconcile_pending_payments(
            older_than_minutes=options["minutes"], limit=options["limit"],
        )
        self.stdout.write(
            "checked={checked} settled={settled} failed={failed} "
            "unresolved={unresolved} errors={errors} flagged={flagged}".format(**summary)
        )
        if summary["settled"]:
            self.stdout.write(self.style.SUCCESS(
                f"Recovered {summary['settled']} captured payment(s)."
            ))
        if summary["flagged"]:
            # An operator has to decide these; nothing is cancelled and no stock is
            # released on their behalf.
            self.stdout.write(self.style.WARNING(
                f"{summary['flagged']} payment(s) moved to RECONCILIATION_REQUIRED "
                f"- see /admin/payments/reconciliation."
            ))
        if summary["errors"]:
            self.stdout.write(self.style.WARNING(
                f"{summary['errors']} payment(s) errored while checking."
            ))
