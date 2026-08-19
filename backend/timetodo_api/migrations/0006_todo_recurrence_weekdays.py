from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("timetodo_api", "0005_todo_overdue_from_date"),
    ]

    operations = [
        migrations.AlterField(
            model_name="todoentry",
            name="recurrence_frequency",
            field=models.CharField(
                choices=[
                    ("none", "Does not repeat"),
                    ("daily", "Daily"),
                    ("weekly", "Weekly"),
                    ("monthly", "Monthly"),
                    ("custom", "Custom weekdays"),
                ],
                default="none",
                max_length=10,
            ),
        ),
        migrations.AddField(
            model_name="todoentry",
            name="recurrence_weekdays",
            field=models.JSONField(blank=True, default=list),
        ),
    ]
