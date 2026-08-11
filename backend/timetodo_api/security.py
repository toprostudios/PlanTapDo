"""Small security controls shared by the HTTP and WebSocket APIs."""

import time

from django.conf import settings
from django.core.cache import cache
from drf_spectacular.extensions import OpenApiAuthenticationExtension
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication


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
    return cache.get(_revocation_cache_key(str(jti))) is None


class RevocableJWTAuthentication(JWTAuthentication):
    """JWT authentication with a shared denylist for logged-out access tokens."""

    def get_validated_token(self, raw_token):
        validated_token = super().get_validated_token(raw_token)
        if not access_token_is_active(validated_token):
            raise AuthenticationFailed("Token has expired or been revoked.")
        return validated_token


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
