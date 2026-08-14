"""CI gate: a new duplicate business-metric implementation must fail the build.

Three audits found the same root cause — the dashboard, accounting, the store panel,
CRM, the agent app and the report builders had each grown their own arithmetic for a
metric `FINANCIAL_DEFINITIONS.md` defines. Behavioural tests catch a *wrong* number;
they cannot catch a *second* number that agrees today and drifts next quarter.

This runs `scripts/check_financial_duplication.py` as a test, so introducing an
unclassified financial aggregate outside an authoritative module fails review rather
than waiting for someone to compare two screens months later.
"""
import importlib.util
from pathlib import Path

from django.test import SimpleTestCase

BACKEND = Path(__file__).resolve().parent.parent
CHECKER = BACKEND / "scripts" / "check_financial_duplication.py"


def _load():
    spec = importlib.util.spec_from_file_location("_fin_dup_checker", CHECKER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class FinancialDuplicationTests(SimpleTestCase):
    def setUp(self):
        self.checker = _load()

    def test_no_unclassified_financial_aggregates(self):
        hits = self.checker.scan()
        unclassified = sorted(f for f in hits if f not in self.checker.CLASSIFIED)
        self.assertEqual(
            unclassified, [],
            "\n\nThese files aggregate money outside an authoritative module and are "
            "not classified.\n\nEither call the canonical implementation (see "
            "FINANCIAL_DEFINITIONS.md / FINANCIAL_CONSISTENCY_MATRIX.md), or add the "
            "file to CLASSIFIED in scripts/check_financial_duplication.py WITH A "
            "REASON:\n  " + "\n  ".join(unclassified),
        )

    def test_every_classification_carries_a_reason(self):
        """A bare entry would let anything through — the reason IS the review."""
        thin = [
            f for f, why in self.checker.CLASSIFIED.items()
            if len(why.strip()) < 25 or why.strip()[:1] not in {"A", "B", "C"}
        ]
        self.assertEqual(thin, [], f"Classifications missing a real reason: {thin}")

    def test_classifications_refer_to_files_that_exist(self):
        """Stops the allowlist rotting into a place duplicates can hide."""
        missing = [f for f in self.checker.CLASSIFIED if not (BACKEND / f).exists()]
        self.assertEqual(missing, [], f"CLASSIFIED refers to missing files: {missing}")

    def test_no_classification_shadows_an_authoritative_module(self):
        overlap = sorted(set(self.checker.CLASSIFIED) & self.checker.AUTHORITATIVE)
        self.assertEqual(overlap, [], f"Authoritative modules must not be classified: {overlap}")

    def test_the_authoritative_modules_all_exist(self):
        missing = [f for f in self.checker.AUTHORITATIVE if not (BACKEND / f).exists()]
        self.assertEqual(missing, [], f"Authoritative module missing: {missing}")

    def test_the_checker_actually_detects_a_duplicate(self):
        """Guards the guard: a checker that never fires is worse than none."""
        hits = self.checker.scan()
        self.assertTrue(hits, "scan() found nothing at all — the pattern is broken")
        # And it must classify the known-consolidated surfaces rather than ignore them.
        for surface in ("reports/executive.py", "storeops/services.py", "crm/services.py"):
            self.assertIn(surface, hits, f"{surface} should still be scanned")
