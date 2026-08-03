"""Housekeeping sweep for banner schedules.

The public feed already honours the schedule window directly (so auto-publish /
auto-expire are correct without this command). This just keeps the stored `state`
tidy for the admin grid: SCHEDULED→ACTIVE once start passes, ACTIVE→EXPIRED once
end passes. Safe to run on a cron (e.g. every 5 min).
"""
from django.core.management.base import BaseCommand
from django.db.models import Q
from django.utils import timezone

from offers.models import Offer


class Command(BaseCommand):
    help = "Reconcile banner state with the schedule window (publish/expire)."

    def handle(self, *args, **options):
        now = timezone.now()

        published = (
            Offer.objects.filter(state=Offer.State.SCHEDULED, deleted_at__isnull=True)
            .filter(Q(valid_from__isnull=True) | Q(valid_from__lte=now))
            .filter(Q(valid_to__isnull=True) | Q(valid_to__gte=now))
            .update(state=Offer.State.ACTIVE, is_active=True)
        )
        expired = (
            Offer.objects.filter(
                state__in=[Offer.State.ACTIVE, Offer.State.SCHEDULED],
                valid_to__isnull=False, valid_to__lt=now,
            ).update(state=Offer.State.EXPIRED, is_active=False)
        )
        self.stdout.write(self.style.SUCCESS(f"published={published} expired={expired}"))
