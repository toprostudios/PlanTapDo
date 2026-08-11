import os

import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

dsn = os.getenv("SENTRY_DSN")
if dsn:
    sentry_sdk.init(
        dsn=dsn,
        integrations=[DjangoIntegration()],
        environment=os.getenv("DJANGO_ENVIRONMENT", "production"),
        release=os.getenv("APP_RELEASE") or None,
        traces_sample_rate=float(os.getenv("SENTRY_TRACES_SAMPLE_RATE", "0.05")),
        profiles_sample_rate=float(os.getenv("SENTRY_PROFILES_SAMPLE_RATE", "0")),
        send_default_pii=False,
        max_request_body_size="never",
    )
