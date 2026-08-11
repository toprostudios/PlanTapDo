from channels.db import database_sync_to_async
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
