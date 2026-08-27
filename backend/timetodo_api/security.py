"""Small security controls shared by the HTTP and WebSocket APIs."""

import time
import hashlib
import hmac

from django.conf import settings
from django.core.cache import cache
from django.db import connection
from django.utils import timezone
from drf_spectacular.extensions import OpenApiAuthenticationExtension
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication

from .account_security import SESSION_ID_CLAIM, SESSION_VERSION_CLAIM
from .models import UserSession


REVOCATION_CACHE_PREFIX = "revoked-jti"


def _revocation_cache_key(jti: str) -> str:
    return f"{REVOCATION_CACHE_PREFIX}:{jti}"


def access_token_is_active(validated_token) -> bool:
    if validated_token is None:
        return False
    jti_claim = settings.SIMPLE_JWT.get("JTI_CLAIM", "jti")
    jti = validated_token.get(jti_claim)
    expires_at = validated_token.get("exp")
    if not jti or not isinstance(expires_at, int) or expires_at <= int(time.time()):
        return False
    session_id = validated_token.get(SESSION_ID_CLAIM)
    if session_id and cache.get(f"revoked-session:{session_id}") is not None:
        return False
    return cache.get(_revocation_cache_key(str(jti))) is None


def set_tenant_context(user_id) -> None:
    """Set a signed transaction-local identity for PostgreSQL RLS policies."""

    if connection.vendor != "postgresql":
        return
    tenant_id = str(user_id)
    signature = hmac.new(
        settings.DB_TENANT_CONTEXT_KEY_BYTES,
        tenant_id.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT set_config('plantapdo.tenant_id', %s, true), "
            "set_config('plantapdo.tenant_signature', %s, true)",
            [tenant_id, signature],
        )


class RevocableJWTAuthentication(JWTAuthentication):
    """JWT authentication with a shared denylist for logged-out access tokens."""

    def get_validated_token(self, raw_token):
        validated_token = super().get_validated_token(raw_token)
        if not access_token_is_active(validated_token):
            raise AuthenticationFailed("Token has expired or been revoked.")
        return validated_token

    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        session_id = validated_token.get(SESSION_ID_CLAIM)
        session_version = validated_token.get(SESSION_VERSION_CLAIM)
        if not session_id or session_version != user.session_version:
            raise AuthenticationFailed("Session has been revoked.")
        if not UserSession.objects.filter(
            id=session_id,
            user=user,
            revoked_at__isnull=True,
            expires_at__gt=timezone.now(),
        ).exists():
            raise AuthenticationFailed("Session has been revoked.")
        set_tenant_context(user.id)
        return user


class RevocableJWTAuthenticationScheme(OpenApiAuthenticationExtension):
    """Describe the custom authenticator accurately in generated OpenAPI."""

    target_class = "timetodo_api.security.RevocableJWTAuthentication"
    name = "jwtAuth"

    def get_security_definition(self, auto_schema):
        return {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
        }


def revoke_access_token(validated_token) -> None:
    """Deny an access token until its natural expiry.

    Production uses the shared TLS Redis cache, so revocation works across all
    ECS tasks and WebSocket handshakes. Cache failures intentionally fail the
    logout request rather than report a revocation that was not persisted.
    """

    if validated_token is None:
        raise AuthenticationFailed("An authenticated access token is required.")

    jti_claim = settings.SIMPLE_JWT.get("JTI_CLAIM", "jti")
    jti = validated_token.get(jti_claim)
    expires_at = validated_token.get("exp")
    if not jti or not isinstance(expires_at, int):
        raise AuthenticationFailed("Token cannot be revoked.")

    remaining_lifetime = max(1, expires_at - int(time.time()))
    cache.set(_revocation_cache_key(str(jti)), True, timeout=remaining_lifetime)


class APIResponseSecurityMiddleware:
    """Prevent authenticated API responses from being cached or embedded."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        if request.path.startswith("/api/"):
            response.headers.setdefault("Cache-Control", "no-store")
            response.headers.setdefault("Pragma", "no-cache")
            response.headers.setdefault(
                "Content-Security-Policy",
                "default-src 'none'; frame-ancestors 'none'; base-uri 'none'",
            )
            response.headers.setdefault("Cross-Origin-Resource-Policy", "same-site")
            response.headers.setdefault("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
            response.headers.setdefault("X-Permitted-Cross-Domain-Policies", "none")
        return response
