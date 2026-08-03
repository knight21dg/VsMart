"""Link a field-verification task to the KYC application it backs, and record the
agent's recommendation (distinct from the reviewer's final decision) so the field
visit's findings reach the store/admin reviewer instead of dead-ending."""

from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("verification", "0001_initial"),
        ("kyc", "0004_kycverification_consent_kycverification_consent_at_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="verificationtask",
            name="kyc_application",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="field_verifications",
                to="kyc.kycapplication",
            ),
        ),
        migrations.AddField(
            model_name="verificationtask",
            name="recommendation",
            field=models.CharField(
                blank=True,
                choices=[
                    ("approve", "Approve"),
                    ("reject", "Reject"),
                    ("inconclusive", "Inconclusive"),
                ],
                max_length=12,
            ),
        ),
    ]
