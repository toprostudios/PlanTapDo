from django.core.validators import MaxValueValidator
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("timetodo_api", "0011_todo_scheduled_not_before"),
    ]

    operations = [
        migrations.AddField(
            model_name="todoentry",
            name="split_parent_id",
            field=models.UUIDField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="todoentry",
            name="split_original_duration",
            field=models.PositiveIntegerField(
                blank=True,
                null=True,
                help_text="Minutes; full estimate while an automatic Off Time split is active.",
                validators=[MaxValueValidator(525_600)],
            ),
        ),
    ]
