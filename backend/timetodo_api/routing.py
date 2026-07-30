from django.urls import re_path
from . import consumers

websocket_urlpatterns = [
    re_path(r'^ws/todos/$', consumers.TodoConsumer.as_asgi()),
]
