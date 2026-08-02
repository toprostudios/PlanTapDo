import json
from channels.generic.websocket import AsyncWebsocketConsumer

class TodoConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for real-time state sync updates per user.
    Clients connect to `ws://<host>/ws/todos/?user_id=<user_id>` or receive broadcasts.
    """

    async def connect(self):
        query_string = self.scope.get("query_string", b"").decode("utf-8")
        user_id = "default"
        if "user_id=" in query_string:
            user_id = query_string.split("user_id=")[-1].split("&")[0]

        self.group_name = f"user_{user_id}"
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, close_code):
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        if text_data:
            try:
                data = json.loads(text_data)
                await self.channel_layer.group_send(
                    self.group_name,
                    {
                        "type": "sync_event",
                        "event_type": data.get("type", "custom_event"),
                        "data": data.get("data", {}),
                    },
                )
            except Exception:
                pass

    async def sync_event(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "event_type": event.get("event_type"),
                    "data": event.get("data"),
                }
            )
        )

    async def todo_message(self, event):
        await self.send(text_data=event["message"])

