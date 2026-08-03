"""Inspect + smoke-test the KYC verification provider.

    python manage.py kyc_check                 # what's configured + which provider resolves
    python manage.py kyc_check --pan ABCDE1234F # live PAN verify against the active provider
    python manage.py kyc_check --aadhaar 999988887777  # send a real Aadhaar OTP

Runs against whatever KYC_PROVIDER resolves to (mock when nothing is configured), so
it's safe to run anywhere. With real Signzy/Setu keys set it becomes a live
connectivity + credentials test — the fastest way to confirm a sandbox is wired
before touching the app. Calls the provider directly; it writes no DB rows.
"""
from django.core.management.base import BaseCommand

from core import runtime_settings as runtime
from kyc import providers


def _yn(v):
    return "set" if v else "NOT set"


class Command(BaseCommand):
    help = "Show the active KYC provider/credentials and optionally run a live check."

    def add_arguments(self, parser):
        parser.add_argument("--pan", help="Run a live PAN verification for this PAN.")
        parser.add_argument("--aadhaar", help="Send a live Aadhaar OTP to this Aadhaar number.")
        parser.add_argument("--name", default="", help="Claimed name to match (with --pan).")

    def handle(self, *args, **o):
        choice = (runtime.cfg("kyc_provider") or "").strip() or "(blank -> mock)"
        provider = providers.get_provider()

        self.stdout.write(self.style.MIGRATE_HEADING("KYC provider configuration"))
        self.stdout.write(f"  kyc_provider setting : {choice}")
        self.stdout.write(f"  resolves to          : {self.style.SUCCESS(provider.name)}")
        self.stdout.write("  Signzy:")
        self.stdout.write(f"    base_url   : {runtime.cfg('signzy_base_url') or '(default)'}")
        self.stdout.write(f"    api_key    : {_yn(runtime.cfg('signzy_api_key'))}")
        self.stdout.write(f"    username   : {_yn(runtime.cfg('signzy_username'))}")
        self.stdout.write(f"    password   : {_yn(runtime.cfg('signzy_password'))}")
        self.stdout.write("  Cashfree (Secure ID):")
        self.stdout.write(f"    base_url   : {runtime.cfg('cashfree_base_url') or '(default)'}")
        self.stdout.write(f"    app_id     : {_yn(runtime.cfg('cashfree_app_id'))}")
        self.stdout.write(f"    secret_key : {_yn(runtime.cfg('cashfree_secret_key'))}")
        self.stdout.write("  Setu:")
        self.stdout.write(f"    client_id  : {_yn(runtime.cfg('setu_client_id'))}")
        self.stdout.write(f"    client_sec : {_yn(runtime.cfg('setu_client_secret'))}")

        if provider.name == "mock" and (o["pan"] or o["aadhaar"]):
            self.stdout.write(self.style.WARNING(
                "\nProvider is MOCK - results below are simulated, not from a gov source. "
                "Set KYC_PROVIDER + credentials to test live."))

        if o["pan"]:
            self.stdout.write(self.style.MIGRATE_HEADING("\nPAN verification"))
            try:
                r = provider.verify_pan(pan=o["pan"], name=o["name"], consent=True,
                                        reason="kyc_check management command")
                self._print_result(r)
            except Exception as exc:  # noqa: BLE001 — surface any transport/auth error
                self.stderr.write(self.style.ERROR(f"  FAILED: {exc}"))

        if o["aadhaar"]:
            self.stdout.write(self.style.MIGRATE_HEADING("\nAadhaar OTP init"))
            try:
                r = provider.aadhaar_okyc_init(aadhaar=o["aadhaar"])
                self.stdout.write(f"  status       : {r.status}")
                self.stdout.write(f"  reference_id : {r.reference_id or '(none)'}")
                self.stdout.write(f"  message      : {r.message}")
            except Exception as exc:  # noqa: BLE001
                self.stderr.write(self.style.ERROR(f"  FAILED: {exc}"))

    def _print_result(self, r):
        ok = r.status == "verified"
        line = self.style.SUCCESS if ok else self.style.ERROR
        self.stdout.write(line(f"  status       : {r.status}"))
        self.stdout.write(f"  verified_name: {r.verified_name or '(none)'}")
        self.stdout.write(f"  verified_dob : {r.verified_dob or '(none)'}")
        self.stdout.write(f"  id_masked    : {r.id_masked or '(none)'}")
        self.stdout.write(f"  name_match   : {r.name_match}")
        if r.error_code:
            self.stdout.write(f"  error_code   : {r.error_code}")
        self.stdout.write(f"  message      : {r.message}")
