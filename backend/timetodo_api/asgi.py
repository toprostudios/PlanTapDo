import os

from channels.routing import ProtocolTypeRouter, URLRouter
from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "timetodo_api.settings")

django_asgi_application = get_asgi_application()

from .routing import websocket_urlpatterns
from .middleware import BrowserOriginOrNativeClientValidator, JWTAuthMiddleware

application = ProtocolTypeRouter(
    {
        "http": django_asgi_application,
        "websocket": BrowserOriginOrNativeClientValidator(
            JWTAuthMiddleware(URLRouter(websocket_urlpatterns))
        ),
    }
)
