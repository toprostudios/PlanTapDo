from django.db import migrations


TENANT_TABLES = (
    "timetodo_api_category",
    "timetodo_api_todoentry",
    "timetodo_api_locationtraveltime",
    "timetodo_api_timesession",
    "timetodo_api_repeatrule",
)


def enable_tenant_rls(_apps, schema_editor):
    if schema_editor.connection.vendor != "postgresql":
        return

    for table in TENANT_TABLES:
        schema_editor.execute(f"ALTER TABLE plantapdo.{table} ENABLE ROW LEVEL SECURITY")

    policies = {
        "timetodo_api_category": (
            "category_tenant_isolation",
            "owner_id = plantapdo_security.current_tenant_id()",
        ),
        "timetodo_api_todoentry": (
            "todo_tenant_isolation",
            "owner_id = plantapdo_security.current_tenant_id()",
        ),
        "timetodo_api_locationtraveltime": (
            "travel_time_tenant_isolation",
            "owner_id = plantapdo_security.current_tenant_id()",
        ),
        "timetodo_api_timesession": (
            "time_session_tenant_isolation",
            "EXISTS (SELECT 1 FROM plantapdo.timetodo_api_todoentry todo "
            "WHERE todo.id = todo_id AND "
            "todo.owner_id = plantapdo_security.current_tenant_id())",
        ),
        "timetodo_api_repeatrule": (
            "repeat_rule_tenant_isolation",
            "EXISTS (SELECT 1 FROM plantapdo.timetodo_api_todoentry todo "
            "WHERE todo.id = todo_id AND "
            "todo.owner_id = plantapdo_security.current_tenant_id())",
        ),
    }
    for table, (policy_name, predicate) in policies.items():
        schema_editor.execute(
            f"DROP POLICY IF EXISTS {policy_name} ON plantapdo.{table}"
        )
        schema_editor.execute(
            f"CREATE POLICY {policy_name} ON plantapdo.{table} "
            f"FOR ALL TO plantapdo_runtime USING ({predicate}) WITH CHECK ({predicate})"
        )


def disable_tenant_rls(_apps, schema_editor):
    if schema_editor.connection.vendor != "postgresql":
        return
    policy_names = (
        ("timetodo_api_category", "category_tenant_isolation"),
        ("timetodo_api_todoentry", "todo_tenant_isolation"),
        ("timetodo_api_locationtraveltime", "travel_time_tenant_isolation"),
        ("timetodo_api_timesession", "time_session_tenant_isolation"),
        ("timetodo_api_repeatrule", "repeat_rule_tenant_isolation"),
    )
    for table, policy_name in policy_names:
        schema_editor.execute(
            f"DROP POLICY IF EXISTS {policy_name} ON plantapdo.{table}"
        )
        schema_editor.execute(f"ALTER TABLE plantapdo.{table} DISABLE ROW LEVEL SECURITY")


class Migration(migrations.Migration):

    dependencies = [
        ("timetodo_api", "0007_account_security_state"),
    ]

    operations = [
        migrations.RunPython(enable_tenant_rls, disable_tenant_rls),
    ]
