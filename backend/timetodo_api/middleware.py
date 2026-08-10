from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError


@database_sync_to_async
def user_for_access_token(raw_token):
    if not raw_token:
        return AnonymousUser()

    authentication = JWTAuthentication()
    try:
        validated_token = authentication.get_validated_token(raw_token)
        return authentication.get_user(validated_token)
    except (AuthenticationFailed, InvalidToken, TokenError):
        return AnonymousUser()


class JWTAuthMiddleware:
    """Authenticate browser WebSockets with an access token query parameter."""

    def __init__(self, inner):
        self.inner = inner

    async def __call__(self, scope, receive, send):
        existing_user = scope.get("user")
        if existing_user is None or not existing_user.is_authenticated:
            query = parse_qs(scope.get("query_string", b"").decode("utf-8"))
            raw_token = query.get("token", [None])[0]
            scope["user"] = await user_for_access_token(raw_token)

        return await self.inner(scope, receive, send)
