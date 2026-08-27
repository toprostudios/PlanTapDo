from django.db import migrations, models
import django.db.models.deletion
import django.utils.timezone
import uuid


def mark_existing_email_addresses_verified(apps, _schema_editor):
    User = apps.get_model("timetodo_api", "User")
    # Preserve access for every pre-feature account, including legacy operator
    # accounts without email. All newly registered accounts start unverified.
    User.objects.filter(email_verified_at__isnull=True).update(
        email_verified_at=django.utils.timezone.now()
    )


class Migration(migrations.Migration):

    dependencies = [
        ("timetodo_api", "0006_todo_recurrence_weekdays"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="email_verified_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="user",
            name="mfa_enabled",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="user",
            name="mfa_pending_secret_encrypted",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="user",
            name="mfa_recovery_code_hashes",
            field=models.JSONField(blank=True, default=list),
        ),
        migrations.AddField(
            model_name="user",
            name="mfa_secret_encrypted",
            field=models.TextField(blank=True, default=""),
        ),
        migrations.AddField(
            model_name="user",
            name="session_version",
            field=models.PositiveIntegerField(default=1),
        ),
        migrations.CreateModel(
            name="AuthChallenge",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("kind", models.CharField(choices=[("verify_email", "Verify email"), ("reset_password", "Reset password")], max_length=20)),
                ("code_digest", models.CharField(max_length=128)),
                ("attempts", models.PositiveSmallIntegerField(default=0)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("expires_at", models.DateTimeField()),
                ("consumed_at", models.DateTimeField(blank=True, null=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="auth_challenges", to="timetodo_api.user")),
            ],
        ),
        migrations.CreateModel(
            name="UserSession",
            fields=[
                ("id", models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ("client_label", models.CharField(blank=True, default="PlanTapDo", max_length=100)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("last_seen_at", models.DateTimeField(auto_now=True)),
                ("expires_at", models.DateTimeField()),
                ("revoked_at", models.DateTimeField(blank=True, null=True)),
                ("user", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="sessions", to="timetodo_api.user")),
            ],
        ),
        migrations.AddIndex(
            model_name="authchallenge",
            index=models.Index(fields=["user", "kind", "created_at"], name="challenge_user_kind_idx"),
        ),
        migrations.AddIndex(
            model_name="usersession",
            index=models.Index(fields=["user", "revoked_at", "expires_at"], name="session_user_active_idx"),
        ),
        migrations.RunPython(
            mark_existing_email_addresses_verified,
            migrations.RunPython.noop,
        ),
    ]
