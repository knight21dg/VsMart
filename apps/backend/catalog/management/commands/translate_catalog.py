"""Fill Telugu names and search keywords for catalog content.

Catalog text is DB data, not app strings, so switching the app to Telugu changed
nothing while `name_te` was empty everywhere. This populates it.

Safe to re-run: only blank fields are filled unless --force is given, so hand
-corrected translations are never overwritten by the dictionary.

    python manage.py translate_catalog            # fill what's missing
    python manage.py translate_catalog --dry-run  # show what would change
    python manage.py translate_catalog --force    # also overwrite existing
"""
from django.core.management.base import BaseCommand

from catalog.models import Category, Product
from catalog.telugu import search_aliases, telugu_name


class Command(BaseCommand):
    help = "Populate Telugu names + search keywords for categories and products."

    def add_arguments(self, parser):
        parser.add_argument("--force", action="store_true",
                            help="Overwrite existing translations too.")
        parser.add_argument("--dry-run", action="store_true",
                            help="Report changes without saving.")

    def handle(self, *args, **opts):
        force, dry = opts["force"], opts["dry_run"]
        stats = {"cat_named": 0, "prod_named": 0, "kw": 0, "cat_miss": 0,
                 "prod_miss": 0}

        for cat in Category.objects.all():
            te = telugu_name(cat.name)
            if te and (force or not cat.name_te):
                self.stdout.write(f"  category  {cat.name}  →  {te}")
                stats["cat_named"] += 1
                if not dry:
                    cat.name_te = te
                    cat.save(update_fields=["name_te"])
            elif not te and not cat.name_te:
                stats["cat_miss"] += 1
                self.stdout.write(self.style.WARNING(
                    f"  category  {cat.name}  →  (no Telugu term known)"))

        for prod in Product.objects.all():
            fields = []
            te = telugu_name(prod.name)
            if te and (force or not prod.name_te):
                prod.name_te = te
                fields.append("name_te")
                stats["prod_named"] += 1
                self.stdout.write(f"  product   {prod.name}  →  {te}")
            elif not te and not prod.name_te:
                stats["prod_miss"] += 1

            # Keywords: the Telugu name plus romanised spellings, so the product
            # is findable however the shopper types it.
            aliases = search_aliases(prod.name)
            if te:
                aliases = [te, *aliases]
            if aliases and (force or not prod.search_keywords):
                prod.search_keywords = ", ".join(dict.fromkeys(aliases))
                fields.append("search_keywords")
                stats["kw"] += 1

            if fields and not dry:
                prod.save(update_fields=fields)

        verb = "would set" if dry else "set"
        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS(
            f"{verb}: {stats['cat_named']} category names, "
            f"{stats['prod_named']} product names, "
            f"{stats['kw']} keyword sets."
        ))
        if stats["cat_miss"] or stats["prod_miss"]:
            self.stdout.write(self.style.WARNING(
                f"No dictionary entry for {stats['cat_miss']} categories and "
                f"{stats['prod_miss']} products — they stay English. Add terms to "
                f"catalog/telugu.py, or set name_te by hand in the admin."
            ))
