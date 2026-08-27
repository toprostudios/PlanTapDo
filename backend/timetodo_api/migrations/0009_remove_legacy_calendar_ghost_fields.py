from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ("timetodo_api", "0008_enable_tenant_rls"),
    ]

    operations = [
        migrations.RemoveField(
            model_name="todoentry",
            name="original_planned_start_time",
        ),
        migrations.RemoveField(
            model_name="todoentry",
            name="overdue_from_date",
        ),
    ]
