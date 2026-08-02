# Initialize Sentry for Django
import os
import sentry_sdk
from sentry_sdk.integrations.django import DjangoIntegration

dsn = os.getenv('SENTRY_DSN')
if dsn:
    sentry_sdk.init(
        dsn=dsn,
        integrations=[DjangoIntegration()],
        traces_sample_rate=1.0,
        send_default_pii=True
    )

