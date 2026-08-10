import os

from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import AllowedHostsOriginValidator
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "timetodo_api.settings")

django_asgi_application = get_asgi_application()

from .routing import websocket_urlpatterns
from .middleware import JWTAuthMiddleware

application = ProtocolTypeRouter(
    {
        "http": django_asgi_application,
        "websocket": AllowedHostsOriginValidator(
            AuthMiddlewareStack(
                JWTAuthMiddleware(URLRouter(websocket_urlpatterns))
            )
        ),
    }
)
