"""Catalog content must translate, and be findable in either language.

Two gaps this covers:

1. **Nothing translated.** The per-language columns existed and the resolver
   worked, but every `name_te` in production was blank — so switching the app to
   Telugu changed nothing visible.
2. **Search was English-only.** It matched `name`/`brand`/`description`, so a
   shopper typing "బియ్యం" or "biyyam" found nothing at all.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from accounts.models import User

from .models import Category, Product
from .telugu import search_aliases, telugu_name


class TeluguDictionaryTests(TestCase):
    def test_common_staples_translate(self):
        self.assertEqual(telugu_name("Rice"), "బియ్యం")
        self.assertEqual(telugu_name("Sugar"), "పంచదార")
        self.assertEqual(telugu_name("Milk"), "పాలు")
        self.assertEqual(telugu_name("Ghee"), "నెయ్యి")

    def test_lookup_is_case_insensitive(self):
        self.assertEqual(telugu_name("RICE"), telugu_name("rice"))

    def test_a_longer_product_name_resolves_via_its_head_noun(self):
        """'Sona Masoori Rice 5kg' should still show a Telugu word."""
        self.assertIsNotNone(telugu_name("Sona Masoori Rice 5kg"))

    def test_an_unknown_term_returns_none_rather_than_a_guess(self):
        """A wrong translation is worse than an untranslated one."""
        self.assertIsNone(telugu_name("Zorblax Ultra 9000"))

    def test_aliases_include_romanised_spellings(self):
        aliases = search_aliases("Rice")
        self.assertIn("biyyam", aliases)
        self.assertIn("బియ్యం", aliases)


class TranslateCommandTests(TestCase):
    def setUp(self):
        self.cat = Category.objects.create(name="Vegetables")
        self.rice = Product.objects.create(
            name="Rice", category=self.cat,
            price=Decimal("50"), mrp=Decimal("60"),
        )

    def _run(self, **kw):
        from django.core.management import call_command
        from io import StringIO

        out = StringIO()
        call_command("translate_catalog", stdout=out, **kw)
        return out.getvalue()

    def test_it_fills_names_and_keywords(self):
        self._run()
        self.cat.refresh_from_db()
        self.rice.refresh_from_db()
        self.assertEqual(self.cat.name_te, "కూరగాయలు")
        self.assertEqual(self.rice.name_te, "బియ్యం")
        self.assertIn("biyyam", self.rice.search_keywords)

    def test_dry_run_changes_nothing(self):
        self._run(dry_run=True)
        self.rice.refresh_from_db()
        self.assertEqual(self.rice.name_te, "")

    def test_it_is_idempotent(self):
        self._run()
        first = Product.objects.get(pk=self.rice.pk).name_te
        self._run()
        self.assertEqual(Product.objects.get(pk=self.rice.pk).name_te, first)

    def test_a_hand_corrected_translation_is_not_clobbered(self):
        self.rice.name_te = "నా అనువాదం"
        self.rice.save(update_fields=["name_te"])
        self._run()
        self.rice.refresh_from_db()
        self.assertEqual(self.rice.name_te, "నా అనువాదం")

    def test_force_overwrites(self):
        self.rice.name_te = "పాతది"
        self.rice.save(update_fields=["name_te"])
        self._run(force=True)
        self.rice.refresh_from_db()
        self.assertEqual(self.rice.name_te, "బియ్యం")


class MultilingualSearchTests(TestCase):
    def setUp(self):
        self.user = User.objects.create(phone="+919000009001", name="C",
                                        role="customer")
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        cat = Category.objects.create(name="Staples")
        self.rice = Product.objects.create(
            name="Sona Masoori Rice", category=cat,
            price=Decimal("50"), mrp=Decimal("60"), in_stock=True,
            name_te="బియ్యం", search_keywords="biyyam, బియ్యం, chawal",
        )

    def _search(self, q):
        r = self.client.get("/api/v1/products/search", {"q": q})
        self.assertEqual(r.status_code, 200, r.content[:200])
        body = r.json()["data"]
        rows = body["results"] if isinstance(body, dict) and "results" in body else body
        return [p["name"] for p in rows]

    def test_english_still_works(self):
        self.assertIn("Sona Masoori Rice", self._search("rice"))

    def test_telugu_script_finds_the_product(self):
        """The headline gap: a Telugu shopper found nothing."""
        self.assertTrue(self._search("బియ్యం"))

    def test_romanised_telugu_finds_the_product(self):
        """Typed on an English keyboard — the common real-world case."""
        self.assertTrue(self._search("biyyam"))

    def test_a_keyword_synonym_finds_the_product(self):
        self.assertTrue(self._search("chawal"))

    def test_an_unrelated_term_still_finds_nothing(self):
        self.assertEqual(self._search("bicycle"), [])


class CompoundNameSafetyTests(TestCase):
    """A partial match must never silently change a name's meaning.

    Caught by a dry run against the real catalogue: "Green Bell Pepper" matched
    the bare word "pepper" and became the Telugu for *black pepper* — a
    different product — and "Oils & Ghee" collapsed to just "ghee".
    """

    def test_bell_pepper_is_not_black_pepper(self):
        self.assertEqual(telugu_name("Green Bell Pepper"), "పచ్చి క్యాప్సికం")
        self.assertNotEqual(telugu_name("Green Bell Pepper"), telugu_name("pepper"))

    def test_compound_names_translate_in_full_or_not_at_all(self):
        for name, expected in [
            ("Oils & Ghee", "నూనెలు & నెయ్యి"),
            ("Rice & Grains", "బియ్యం & ధాన్యాలు"),
            ("Tea & Coffee", "టీ & కాఫీ"),
            ("Milk & Cream", "పాలు & క్రీమ్"),
        ]:
            self.assertEqual(telugu_name(name), expected, name)

    def test_an_unknown_compound_is_left_untranslated(self):
        """Never half-translate: better English than a name that lost meaning."""
        self.assertIsNone(telugu_name("Widgets & Sprockets"))

    def test_a_trailing_pack_size_is_still_ignored(self):
        """The pack size is dropped, and the MOST specific entry wins —
        "సోనా మసూరి బియ్యం", not the generic word for rice."""
        self.assertEqual(telugu_name("Sona Masoori Rice 5kg"),
                         telugu_name("sona masoori rice"))
        self.assertNotEqual(telugu_name("Sona Masoori Rice 5kg"),
                            telugu_name("rice"))

    def test_orange_juice_is_not_just_orange(self):
        self.assertEqual(telugu_name("Orange Juice"), "నారింజ జ్యూస్")
