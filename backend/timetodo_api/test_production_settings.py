import base64
import importlib.util
import os
from pathlib import Path
import string
import tempfile
from unittest import mock

from django.core.exceptions import ImproperlyConfigured
from django.test import SimpleTestCase


class ProductionSettingsTests(SimpleTestCase):
    def production_environment(self, ca_path: str) -> dict[str, str]:
        secure_characters = string.ascii_letters + string.digits + "-_"
        return {
            "DJANGO_ENVIRONMENT": "production",
            "DJANGO_DEBUG": "False",
            "DJANGO_ALLOWED_HOSTS": "api.example.com",
            "DJANGO_SECRET_KEY": secure_characters + secure_characters[::-1],
            "JWT_SIGNING_KEY": secure_characters[::-1] + secure_characters,
            "DB_TENANT_CONTEXT_KEY": "a1" * 64,
            "MFA_ENCRYPTION_KEY": "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=",
            "DATABASE_ROLE": "runtime",
            "POSTGRES_DB": "postgres",
            "POSTGRES_SCHEMA": "plantapdo",
            "POSTGRES_USER": "plantapdo_runtime",
            "POSTGRES_PASSWORD": secure_characters[7:] + secure_characters[:7],
            "POSTGRES_HOST": "db.example.supabase.co",
            "POSTGRES_PORT": "5432",
            "POSTGRES_SSLMODE": "verify-full",
            "POSTGRES_SSLROOTCERT": ca_path,
            "REDIS_URL": (
                "rediss://default:redis-secret@redis.example.com:6379/0"
                "?ssl_cert_reqs=required&ssl_check_hostname=true"
            ),
            "SENTRY_DSN": "",
            "EMAIL_BACKEND": "django.core.mail.backends.smtp.EmailBackend",
            "EMAIL_HOST": "smtp.example.com",
            "EMAIL_PORT": "587",
            "EMAIL_HOST_USER": "smtp-user",
            "EMAIL_HOST_PASSWORD": "smtp-password",
            "EMAIL_USE_TLS": "true",
            "DEFAULT_FROM_EMAIL": "PlanTapDo <no-reply@example.com>",
        }

    def import_settings(self, environment: dict[str, str]):
        settings_path = Path(__file__).with_name("settings.py")
        spec = importlib.util.spec_from_file_location("production_settings_probe", settings_path)
        module = importlib.util.module_from_spec(spec)
        with mock.patch.dict(os.environ, environment, clear=True):
            spec.loader.exec_module(module)
        return module

    def test_accepts_private_supabase_runtime_configuration(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            configured_settings = self.import_settings(
                self.production_environment(ca_file.name)
            )

        self.assertEqual(configured_settings.POSTGRES_SCHEMA, "plantapdo")
        self.assertEqual(configured_settings.DATABASE_ROLE, "runtime")

    def test_rejects_public_schema(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            environment["POSTGRES_SCHEMA"] = "public"
            with self.assertRaisesRegex(ImproperlyConfigured, "private application schema"):
                self.import_settings(environment)

    def test_rejects_owner_or_migration_role_for_runtime(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            environment["POSTGRES_USER"] = "postgres"
            with self.assertRaisesRegex(ImproperlyConfigured, "plantapdo_runtime"):
                self.import_settings(environment)

    def test_rejects_invalid_tenant_context_key(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            environment["DB_TENANT_CONTEXT_KEY"] = "too-short"
            with self.assertRaisesRegex(ImproperlyConfigured, "128 lowercase hexadecimal"):
                self.import_settings(environment)

    def test_accepts_mfa_encryption_key_fallback(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            fallback_key = base64.urlsafe_b64encode(bytes(range(32, 64))).decode("ascii")
            environment["MFA_ENCRYPTION_KEY_FALLBACKS"] = fallback_key
            configured_settings = self.import_settings(environment)

        self.assertEqual(configured_settings.MFA_ENCRYPTION_KEYS[-1], fallback_key)

    def test_rejects_invalid_mfa_encryption_key(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            environment["MFA_ENCRYPTION_KEY"] = "invalid-fernet-key"
            with self.assertRaisesRegex(ImproperlyConfigured, "Fernet keys"):
                self.import_settings(environment)

    def test_rejects_non_smtp_production_email(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            environment["EMAIL_BACKEND"] = "django.core.mail.backends.console.EmailBackend"
            with self.assertRaisesRegex(ImproperlyConfigured, "SMTP backend"):
                self.import_settings(environment)

    def test_rejects_redis_without_hostname_verification(self):
        with tempfile.NamedTemporaryFile() as ca_file:
            environment = self.production_environment(ca_file.name)
            environment["REDIS_URL"] = (
                "rediss://default:redis-secret@redis.example.com:6379/0"
                "?ssl_cert_reqs=required"
            )
            with self.assertRaisesRegex(ImproperlyConfigured, "ssl_check_hostname=true"):
                self.import_settings(environment)
