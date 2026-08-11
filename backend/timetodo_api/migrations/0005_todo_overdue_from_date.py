from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [("timetodo_api", "0004_case_insensitive_account_identifiers")]

    operations = [
        migrations.AddField(
            model_name="todoentry",
            name="overdue_from_date",
            field=models.CharField(blank=True, max_length=50, null=True),
        ),
    ]
