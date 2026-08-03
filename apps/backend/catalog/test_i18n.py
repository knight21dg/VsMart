"""Catalog content localization.

The app's ARB files translate UI chrome only — product and category names are
database rows, so they need their own columns and server-side resolution.
"""
from decimal import Decimal

from django.test import TestCase
from rest_framework.test import APIClient

from core.i18n import DEFAULT_LANG, pick, resolve_lang

from .models import Category, Product


class ResolveLangTests(TestCase):
    class _Req:
        def __init__(self, header="", params=None):
            self.META = {"HTTP_ACCEPT_LANGUAGE": header} if header else {}
            self.query_params = params or {}

    def test_query_param_wins(self):
        self.assertEqual(
            resolve_lang(self._Req("en-US", {"lang": "te"})), "te"
        )

    def test_accept_language_is_used(self):
        self.assertEqual(resolve_lang(self._Req("te-IN,te;q=0.9,en;q=0.8")), "te")
        self.assertEqual(resolve_lang(self._Req("hi-IN,hi;q=0.9")), "hi")

    def test_unsupported_falls_back_to_english(self):
        self.assertEqual(resolve_lang(self._Req("fr-FR,fr;q=0.9")), DEFAULT_LANG)
        self.assertEqual(resolve_lang(self._Req()), DEFAULT_LANG)
        self.assertEqual(resolve_lang(None), DEFAULT_LANG)

    def test_first_supported_tag_in_preference_order_wins(self):
        self.assertEqual(resolve_lang(self._Req("fr,te;q=0.8,en;q=0.7")), "te")


class PickTests(TestCase):
    def test_blank_translation_falls_back(self):
        cat = Category(name="Snacks", name_te="", name_hi="नाश्ता")
        self.assertEqual(pick(cat, "name", "te"), "Snacks")
        self.assertEqual(pick(cat, "name", "hi"), "नाश्ता")
        self.assertEqual(pick(cat, "name", "en"), "Snacks")

    def test_whitespace_only_translation_falls_back(self):
        cat = Category(name="Snacks", name_te="   ")
        self.assertEqual(pick(cat, "name", "te"), "Snacks")


class CatalogApiLocalizationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.cat = Category.objects.create(
            name="Snacks", slug="snacks",
            name_te="స్నాక్స్", name_hi="नाश्ता",
        )
        self.product = Product.objects.create(
            name="Potato Chips", category=self.cat,
            price=Decimal("20"), mrp=Decimal("25"),
            description="Crispy and salted.",
            name_te="బంగాళాదుంప చిప్స్", description_te="మంచిగా ఉంటుంది.",
            name_hi="आलू चिप्स",
        )

    def _products(self, **headers):
        r = self.client.get("/api/v1/products", **headers)
        body = r.json()["data"]
        return body["results"] if isinstance(body, dict) and "results" in body else body

    def _categories(self, **headers):
        r = self.client.get("/api/v1/categories", **headers)
        body = r.json()["data"]
        return body["results"] if isinstance(body, dict) and "results" in body else body

    def test_english_is_the_default(self):
        self.assertEqual(self._products()[0]["name"], "Potato Chips")
        self.assertEqual(self._categories()[0]["name"], "Snacks")

    def test_telugu_via_accept_language(self):
        rows = self._products(HTTP_ACCEPT_LANGUAGE="te-IN,te;q=0.9")
        self.assertEqual(rows[0]["name"], "బంగాళాదుంప చిప్స్")
        cats = self._categories(HTTP_ACCEPT_LANGUAGE="te-IN,te;q=0.9")
        self.assertEqual(cats[0]["name"], "స్నాక్స్")

    def test_hindi_via_query_param(self):
        r = self.client.get("/api/v1/products", {"lang": "hi"})
        body = r.json()["data"]
        rows = body["results"] if isinstance(body, dict) and "results" in body else body
        self.assertEqual(rows[0]["name"], "आलू चिप्स")

    def test_missing_translation_falls_back_not_blank(self):
        """Hindi description was never entered — it must not render empty."""
        r = self.client.get(f"/api/v1/products/{self.product.id}", {"lang": "hi"})
        data = r.json()["data"]
        self.assertEqual(data["name"], "आलू चिप्स")
        self.assertEqual(data["description"], "Crispy and salted.")

    def test_detail_endpoint_is_localized(self):
        r = self.client.get(f"/api/v1/products/{self.product.id}", {"lang": "te"})
        data = r.json()["data"]
        self.assertEqual(data["name"], "బంగాళాదుంప చిప్స్")
        self.assertEqual(data["description"], "మంచిగా ఉంటుంది.")

    def test_search_results_are_localized_too(self):
        """Server-side resolution means every consumer gets it, not just the grid."""
        r = self.client.get("/api/v1/products", {"q": "Potato", "lang": "te"})
        body = r.json()["data"]
        rows = body["results"] if isinstance(body, dict) and "results" in body else body
        self.assertEqual(rows[0]["name"], "బంగాళాదుంప చిప్స్")
