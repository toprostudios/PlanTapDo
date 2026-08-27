from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("timetodo_api", "0009_remove_legacy_calendar_ghost_fields"),
    ]

    operations = [
        migrations.AddField(
            model_name="category",
            name="notification_preference",
            field=models.CharField(default="none", max_length=40),
        ),
        migrations.AddField(
            model_name="todoentry",
            name="notification_preference",
            field=models.CharField(blank=True, max_length=40, null=True),
        ),
    ]
