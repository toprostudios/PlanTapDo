from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("timetodo_api", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="todoentry",
            name="original_planned_start_time",
            field=models.CharField(blank=True, max_length=10, null=True),
        ),
        migrations.AddField(
            model_name="todoentry",
            name="recurrence_frequency",
            field=models.CharField(
                choices=[
                    ("none", "Does not repeat"),
                    ("daily", "Daily"),
                    ("weekly", "Weekly"),
                ],
                default="none",
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name="todoentry",
            name="recurrence_series_id",
            field=models.UUIDField(blank=True, null=True),
        ),
    ]
