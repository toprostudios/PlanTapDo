import json

from channels.generic.websocket import AsyncWebsocketConsumer


class TodoConsumer(AsyncWebsocketConsumer):
    """Authenticated real-time updates scoped to the connected account."""

    async def connect(self):
        user = self.scope.get("user")
        if user is None or not user.is_authenticated:
            await self.close(code=4401)
            return

        self.group_name = f"user_{user.id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        group_name = getattr(self, "group_name", None)
        if group_name:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        if not text_data:
            return

        try:
            data = json.loads(text_data)
        except (TypeError, json.JSONDecodeError):
            await self.close(code=4400)
            return

        await self.channel_layer.group_send(
            self.group_name,
            {
                "type": "sync_event",
                "event_type": data.get("type", "custom_event"),
                "data": data.get("data", {}),
            },
        )

    async def sync_event(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "event_type": event.get("event_type"),
                    "data": event.get("data"),
                }
            )
        )
