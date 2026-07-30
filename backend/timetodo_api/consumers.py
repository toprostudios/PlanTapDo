import json
from channels.generic.websocket import AsyncWebsocketConsumer
from channels.db import database_sync_to_async
from .models import TodoEntry

class TodoConsumer(AsyncWebsocketConsumer):
    """WebSocket consumer for real‑time Todo updates.
    Clients should connect to ``ws://<host>/ws/todos/``.
    The consumer joins a group named ``todo_updates`` and forwards any
    messages received from the client to that group. Backend signal handlers
    can broadcast to the same group to push updates to all connected clients.
    """

    async def connect(self):
        self.group_name = "todo_updates"
        # Accept the connection
        await self.accept()
        # Add this socket to the group
        await self.channel_layer.group_add(self.group_name, self.channel_name)

    async def disconnect(self, close_code):
        # Remove from group on disconnect
        await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def receive(self, text_data=None, bytes_data=None):
        # Echo received message to the group (could be extended for commands)
        if text_data:
            await self.channel_layer.group_send(
                self.group_name,
                {
                    "type": "todo.message",
                    "message": text_data,
                },
            )

    async def todo_message(self, event):
        # Send message to WebSocket client
        await self.send(text_data=event["message"])

    @database_sync_to_async
    def get_todo(self, todo_id: str):
        return TodoEntry.objects.get(id=todo_id)
