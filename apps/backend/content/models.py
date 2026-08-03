from django.db import models

from core.models import TimeStampedModel


class Page(TimeStampedModel):
    """A CMS page (About, Contact, Careers, Terms, Privacy, FAQ, generic)."""

    class Type(models.TextChoices):
        ABOUT = "about"
        CONTACT = "contact"
        CAREERS = "careers"
        TERMS = "terms"
        PRIVACY = "privacy"
        FAQ = "faq"
        GENERIC = "generic"

    slug = models.SlugField(unique=True)
    title = models.CharField(max_length=200)
    body = models.TextField()
    type = models.CharField(
        max_length=20, choices=Type.choices, default=Type.GENERIC
    )
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["sort_order"]

    def __str__(self):
        return f"Page({self.slug})"
