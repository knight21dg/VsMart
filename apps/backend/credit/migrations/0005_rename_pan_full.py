from django.db import migrations, models


class Migration(migrations.Migration):
    """Store the full PAN from the bureau, not a masked form."""

    dependencies = [
        ("credit", "0004_creditbureaureport"),
    ]

    operations = [
        migrations.RenameField(
            model_name="creditbureaureport",
            old_name="pan_masked",
            new_name="pan",
        ),
        migrations.AlterField(
            model_name="creditbureaureport",
            name="pan",
            field=models.CharField(blank=True, max_length=10),
        ),
    ]
