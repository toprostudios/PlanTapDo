"""Django settings for PlanTapDo.

Production is intentionally fail-closed. Local development must opt in with
``DJANGO_ENVIRONMENT=development``; a process with no environment configured
will refuse to start instead of falling back to insecure defaults.
"""

from datetime import timedelta
import os
from pathlib import Path
import secrets
from urllib.parse import urlparse

from django.core.exceptions import ImproperlyConfigured


BASE_DIR = Path(__file__).resolve().parent.parent


def env_bool(name: str, default: bool = False) -> bool:
    raw_value = os.getenv(name)
    if raw_value is None:
        return default
    normalized = raw_value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ImproperlyConfigured(f"{name} must be a boolean value.")


def env_int(name: str, default: int, minimum: int = 0) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError as exc:
        raise ImproperlyConfigured(f"{name} must be an integer.") from exc
    if value < minimum:
        raise ImproperlyConfigured(f"{name} must be at least {minimum}.")
    return value


def env_list(name: str, default: str = "") -> list[str]:
    return [item.strip() for item in os.getenv(name, default).split(",") if item.strip()]


def validate_production_secret(name: str, value: str, *, minimum_length: int = 64) -> None:
    """Reject common placeholder or structurally weak production secrets.

    This cannot prove entropy, so operators must still generate values with a
    cryptographically secure generator and store them in a secret manager.
    """

    normalized = value.casefold()
    placeholder_fragments = ("replace-with", "changeme", "example", "password")
    if (
        len(value) < minimum_length
        or any(fragment in normalized for fragment in placeholder_fragments)
        or len(set(value)) < 12
    ):
        raise ImproperlyConfigured(
            f"{name} must be a non-placeholder random value of at least "
            f"{minimum_length} characters."
        )


ENVIRONMENT = os.getenv("DJANGO_ENVIRONMENT", "production").strip().lower()
if ENVIRONMENT not in {"development", "test", "staging", "production"}:
    raise ImproperlyConfigured(
        "DJANGO_ENVIRONMENT must be development, test, staging, or production."
    )

IS_PRODUCTION = ENVIRONMENT in {"staging", "production"}
DEBUG = env_bool("DJANGO_DEBUG", default=ENVIRONMENT == "development")
if IS_PRODUCTION and DEBUG:
    raise ImproperlyConfigured("DJANGO_DEBUG cannot be enabled in staging or production.")

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "").strip()
if not SECRET_KEY:
    if IS_PRODUCTION:
        raise ImproperlyConfigured("DJANGO_SECRET_KEY is required outside development/test.")
    SECRET_KEY = secrets.token_urlsafe(64)
elif IS_PRODUCTION:
    validate_production_secret("DJANGO_SECRET_KEY", SECRET_KEY)
    if SECRET_KEY.startswith("django-insecure-"):
        raise ImproperlyConfigured("DJANGO_SECRET_KEY cannot use Django's insecure prefix.")

SECRET_KEY_FALLBACKS = env_list("DJANGO_SECRET_KEY_FALLBACKS")
if IS_PRODUCTION:
    if SECRET_KEY in SECRET_KEY_FALLBACKS or len(set(SECRET_KEY_FALLBACKS)) != len(
        SECRET_KEY_FALLBACKS
    ):
        raise ImproperlyConfigured(
            "DJANGO_SECRET_KEY_FALLBACKS must be unique and exclude the active key."
        )
    for fallback_index, fallback_key in enumerate(SECRET_KEY_FALLBACKS, start=1):
        validate_production_secret(
            f"DJANGO_SECRET_KEY_FALLBACKS item {fallback_index}", fallback_key
        )

ALLOWED_HOSTS = env_list(
    "DJANGO_ALLOWED_HOSTS",
    "localhost,127.0.0.1,testserver" if not IS_PRODUCTION else "",
)
if IS_PRODUCTION and (not ALLOWED_HOSTS or "*" in ALLOWED_HOSTS):
    raise ImproperlyConfigured(
        "DJANGO_ALLOWED_HOSTS must contain explicit hostnames in production."
    )
if IS_PRODUCTION:
    invalid_hosts = [
        host
        for host in ALLOWED_HOSTS
        if host.startswith(".") or "://" in host or "/" in host or ":" in host
    ]
    if invalid_hosts:
        raise ImproperlyConfigured(
            "Production hosts must be exact hostnames without schemes, paths, ports, "
            "or subdomain wildcards: "
            + ", ".join(invalid_hosts)
        )


INSTALLED_APPS = [
    "daphne",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt.token_blacklist",
    "corsheaders",
    "drf_spectacular",
    "channels",
    "timetodo_api",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "timetodo_api.security.APIResponseSecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "timetodo_api.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {"context_processors": []},
    },
]

WSGI_APPLICATION = "timetodo_api.wsgi.application"
ASGI_APPLICATION = "timetodo_api.asgi.application"
AUTH_USER_MODEL = "timetodo_api.User"


if IS_PRODUCTION:
    required_database_settings = {
        name: os.getenv(name, "").strip()
        for name in (
            "POSTGRES_DB",
            "POSTGRES_USER",
            "POSTGRES_PASSWORD",
            "POSTGRES_HOST",
        )
    }
    missing_database_settings = [
        name for name, value in required_database_settings.items() if not value
    ]
    if missing_database_settings:
        raise ImproperlyConfigured(
            "Production PostgreSQL configuration is incomplete: "
            + ", ".join(missing_database_settings)
        )

    postgres_sslmode = os.getenv("POSTGRES_SSLMODE", "verify-full").strip().lower()
    if postgres_sslmode != "verify-full":
        raise ImproperlyConfigured(
            "POSTGRES_SSLMODE must be verify-full in production so the database "
            "certificate and hostname are verified."
        )
    postgres_sslrootcert = os.getenv("POSTGRES_SSLROOTCERT", "").strip()
    if not postgres_sslrootcert or not Path(postgres_sslrootcert).is_absolute():
        raise ImproperlyConfigured(
            "POSTGRES_SSLROOTCERT must be an absolute CA bundle path in production."
        )
    if not Path(postgres_sslrootcert).is_file():
        raise ImproperlyConfigured(
            "POSTGRES_SSLROOTCERT must point to a readable CA bundle file."
        )

    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "NAME": required_database_settings["POSTGRES_DB"],
            "USER": required_database_settings["POSTGRES_USER"],
            "PASSWORD": required_database_settings["POSTGRES_PASSWORD"],
            "HOST": required_database_settings["POSTGRES_HOST"],
            "PORT": os.getenv("POSTGRES_PORT", "5432"),
            "CONN_MAX_AGE": env_int("POSTGRES_CONN_MAX_AGE", 60),
            "CONN_HEALTH_CHECKS": True,
            "OPTIONS": {
                "sslmode": postgres_sslmode,
                "sslrootcert": postgres_sslrootcert,
                "connect_timeout": env_int("POSTGRES_CONNECT_TIMEOUT", 5, minimum=1),
            },
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }


AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {"min_length": 15},
    },
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

PASSWORD_HASHERS = [
    "timetodo_api.hashers.OWASPArgon2PasswordHasher",
    "django.contrib.auth.hashers.ScryptPasswordHasher",
    "django.contrib.auth.hashers.PBKDF2PasswordHasher",
]


LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "/static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"


REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "timetodo_api.security.RevocableJWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_PARSER_CLASSES": (
        "rest_framework.parsers.JSONParser",
    ),
    "DEFAULT_RENDERER_CLASSES": (
        "rest_framework.renderers.JSONRenderer",
    )
    if IS_PRODUCTION
    else (
        "rest_framework.renderers.JSONRenderer",
        "rest_framework.renderers.BrowsableAPIRenderer",
    ),
    "DEFAULT_THROTTLE_CLASSES": (
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ),
    "DEFAULT_THROTTLE_RATES": {
        "anon": os.getenv("THROTTLE_ANON_RATE", "60/minute"),
        "user": os.getenv("THROTTLE_USER_RATE", "300/minute"),
        "login": os.getenv("THROTTLE_LOGIN_RATE", "10/minute"),
        "register": os.getenv("THROTTLE_REGISTER_RATE", "5/hour"),
        "token_refresh": os.getenv("THROTTLE_TOKEN_REFRESH_RATE", "30/minute"),
        "token_verify": os.getenv("THROTTLE_TOKEN_VERIFY_RATE", "30/minute"),
        "sync": os.getenv("THROTTLE_SYNC_RATE", "30/minute"),
    },
    "DEFAULT_SCHEMA_CLASS": "drf_spectacular.openapi.AutoSchema",
    "NUM_PROXIES": env_int("DJANGO_NUM_PROXIES", 0),
}

JWT_SIGNING_KEY = os.getenv("JWT_SIGNING_KEY", "").strip()
if not JWT_SIGNING_KEY:
    if IS_PRODUCTION:
        raise ImproperlyConfigured("JWT_SIGNING_KEY is required in staging/production.")
    JWT_SIGNING_KEY = SECRET_KEY
elif IS_PRODUCTION:
    validate_production_secret("JWT_SIGNING_KEY", JWT_SIGNING_KEY)
if IS_PRODUCTION and JWT_SIGNING_KEY == SECRET_KEY:
    raise ImproperlyConfigured(
        "JWT_SIGNING_KEY must be different from DJANGO_SECRET_KEY."
    )

AUTH_REVOCATION_ENABLED = True
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(
        minutes=env_int("JWT_ACCESS_TOKEN_MINUTES", 15, minimum=1)
    ),
    "REFRESH_TOKEN_LIFETIME": timedelta(
        days=env_int("JWT_REFRESH_TOKEN_DAYS", 7, minimum=1)
    ),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "UPDATE_LAST_LOGIN": False,
    "ALGORITHM": "HS256",
    "SIGNING_KEY": JWT_SIGNING_KEY,
    "AUDIENCE": os.getenv("JWT_AUDIENCE", "plantapdo-api"),
    "ISSUER": os.getenv("JWT_ISSUER", "plantapdo"),
    "AUTH_HEADER_TYPES": ("Bearer",),
    "CHECK_REVOKE_TOKEN": AUTH_REVOCATION_ENABLED,
}


CORS_ALLOW_ALL_ORIGINS = False
CORS_ALLOWED_ORIGINS = env_list(
    "DJANGO_CORS_ALLOWED_ORIGINS",
    "http://localhost:3000,http://127.0.0.1:3000" if not IS_PRODUCTION else "",
)
CORS_ALLOW_CREDENTIALS = False
CORS_URLS_REGEX = r"^/api/.*$"
CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")

if IS_PRODUCTION:
    invalid_cors_origins = [
        origin
        for origin in CORS_ALLOWED_ORIGINS
        if urlparse(origin).scheme != "https"
    ]
    if invalid_cors_origins:
        raise ImproperlyConfigured(
            "Production CORS origins must use HTTPS: " + ", ".join(invalid_cors_origins)
        )
    invalid_csrf_origins = [
        origin
        for origin in CSRF_TRUSTED_ORIGINS
        if urlparse(origin).scheme != "https"
    ]
    if invalid_csrf_origins:
        raise ImproperlyConfigured(
            "Production CSRF trusted origins must use HTTPS: "
            + ", ".join(invalid_csrf_origins)
        )


SECURE_SSL_REDIRECT = IS_PRODUCTION and env_bool("DJANGO_SECURE_SSL_REDIRECT", True)
SESSION_COOKIE_SECURE = IS_PRODUCTION
SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SECURE = IS_PRODUCTION
CSRF_COOKIE_HTTPONLY = True
CSRF_COOKIE_SAMESITE = "Strict"
SECURE_HSTS_SECONDS = (
    env_int("DJANGO_SECURE_HSTS_SECONDS", 31536000) if IS_PRODUCTION else 0
)
SECURE_HSTS_INCLUDE_SUBDOMAINS = IS_PRODUCTION and env_bool(
    "DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS", True
)
SECURE_HSTS_PRELOAD = IS_PRODUCTION and env_bool("DJANGO_SECURE_HSTS_PRELOAD", True)
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "same-origin"
SECURE_CROSS_ORIGIN_OPENER_POLICY = "same-origin"
X_FRAME_OPTIONS = "DENY"

if env_bool("DJANGO_TRUST_PROXY_SSL_HEADER", False):
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# ALB and container health probes travel over the private task network. Public
# plaintext traffic is still redirected by the ALB listener.
SECURE_REDIRECT_EXEMPT = [r"^health/(?:live|ready)/$"] if IS_PRODUCTION else []

DATA_UPLOAD_MAX_MEMORY_SIZE = env_int("DJANGO_MAX_REQUEST_BYTES", 2 * 1024 * 1024, 1024)
DATA_UPLOAD_MAX_NUMBER_FIELDS = env_int("DJANGO_MAX_FORM_FIELDS", 1000, 1)
DATA_UPLOAD_MAX_NUMBER_FILES = 0


REDIS_URL = os.getenv("REDIS_URL", "").strip()
if IS_PRODUCTION and not REDIS_URL:
    raise ImproperlyConfigured(
        "REDIS_URL is required in production for shared throttling and WebSockets."
    )
if IS_PRODUCTION and urlparse(REDIS_URL).scheme != "rediss":
    raise ImproperlyConfigured("Production REDIS_URL must use TLS (rediss://).")
if IS_PRODUCTION:
    parsed_redis_url = urlparse(REDIS_URL)
    if not parsed_redis_url.hostname or not parsed_redis_url.password:
        raise ImproperlyConfigured(
            "Production REDIS_URL must include a hostname and authentication token."
        )
    if parsed_redis_url.fragment:
        raise ImproperlyConfigured("Production REDIS_URL cannot contain a fragment.")

if REDIS_URL:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": REDIS_URL,
            "KEY_PREFIX": os.getenv("REDIS_KEY_PREFIX", "plantapdo"),
            "TIMEOUT": 300,
        }
    }
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {
                "hosts": [REDIS_URL],
                "capacity": env_int("CHANNEL_CAPACITY", 500, minimum=1),
                "expiry": env_int("CHANNEL_MESSAGE_EXPIRY", 60, minimum=1),
                "group_expiry": env_int("CHANNEL_GROUP_EXPIRY", 86400, minimum=60),
            },
        }
    }
else:
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "plantapdo-development",
        }
    }
    CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}
    }


SPECTACULAR_SETTINGS = {
    "TITLE": "PlanTapDo API",
    "DESCRIPTION": "Authenticated API for PlanTapDo",
    "VERSION": "1.0.0",
    "SERVE_INCLUDE_SCHEMA": False,
}


LOG_LEVEL = os.getenv("DJANGO_LOG_LEVEL", "INFO" if IS_PRODUCTION else "DEBUG").upper()
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {
            "format": "{asctime} {levelname} {name} {message}",
            "style": "{",
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
        }
    },
    "root": {"handlers": ["console"], "level": LOG_LEVEL},
    "loggers": {
        "django.security": {
            "handlers": ["console"],
            "level": "WARNING",
            "propagate": False,
        },
    },
}
