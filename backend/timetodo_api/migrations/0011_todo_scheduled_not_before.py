from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("timetodo_api", "0010_notification_preferences"),
    ]

    operations = [
        migrations.AddField(
            model_name="todoentry",
            name="scheduled_not_before",
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
