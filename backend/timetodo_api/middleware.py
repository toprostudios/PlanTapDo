from channels.db import database_sync_to_async
from channels.security.websocket import AllowedHostsOriginValidator
from django.contrib.auth.models import AnonymousUser
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError

from .security import RevocableJWTAuthentication


@database_sync_to_async
def user_for_access_token(raw_token):
    if not raw_token:
        return AnonymousUser(), None

    authentication = RevocableJWTAuthentication()
    try:
        validated_token = authentication.get_validated_token(raw_token)
        return authentication.get_user(validated_token), validated_token
    except (AuthenticationFailed, InvalidToken, TokenError):
        return AnonymousUser(), None


class JWTAuthMiddleware:
    """Authenticate WebSockets with an Authorization: Bearer header.

    Tokens are deliberately not accepted in query strings because URLs are
    routinely retained by access logs, monitoring systems, and proxies.
    """

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        existing_user = scope.get("user")
        if existing_user is None or not existing_user.is_authenticated:
            raw_token = None
            for name, value in scope.get("headers", []):
                if name.lower() != b"authorization":
                    continue
                try:
                    scheme, candidate = value.decode("ascii").split(" ", 1)
                except (UnicodeDecodeError, ValueError):
                    break
                if scheme.lower() == "bearer" and len(candidate) <= 4096:
                    raw_token = candidate.strip()
                break
            scope["user"], scope["access_token"] = await user_for_access_token(raw_token)

        return await self.inner(scope, receive, send)


class BrowserOriginOrNativeClientValidator:
    """Validate browser origins while allowing native clients without one.

    Web browsers always send an Origin header for WebSocket handshakes, so a
    present header remains restricted to Django's explicit allowed hosts.
    Native URLSession clients commonly omit Origin and authenticate solely with
    the bearer token, which is safe from browser cross-site WebSocket attacks.
    """

    def __init__(self, application):
        self.application = application
        self.browser_origin_validator = AllowedHostsOriginValidator(application)

    async def __call__(self, scope, receive, send):
        has_origin = any(
            name.lower() == b"origin" for name, _value in scope.get("headers", [])
        )
        if has_origin:
            return await self.browser_origin_validator(scope, receive, send)
        return await self.application(scope, receive, send)
