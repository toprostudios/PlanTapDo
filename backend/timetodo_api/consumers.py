import asyncio
import json
import time

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer

from .security import access_token_is_active


@database_sync_to_async
def socket_token_is_active(validated_token):
    return access_token_is_active(validated_token)


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
        self.auth_monitor_task = asyncio.create_task(self._monitor_authentication())

    async def disconnect(self, close_code):
        monitor_task = getattr(self, "auth_monitor_task", None)
        if monitor_task and monitor_task is not asyncio.current_task():
            monitor_task.cancel()
        group_name = getattr(self, "group_name", None)
        if group_name:
            await self.channel_layer.group_discard(group_name, self.channel_name)

    async def _monitor_authentication(self):
        """Close sockets promptly when their access token expires or is revoked."""

        validated_token = self.scope.get("access_token")
        while True:
            try:
                expires_at = validated_token.get("exp", 0) if validated_token else 0
                until_expiry = expires_at - int(time.time())
                sleep_duration = max(1, min(30, until_expiry)) if until_expiry > 0 else 1
                await asyncio.sleep(sleep_duration)
                if not await socket_token_is_active(validated_token):
                    await self.close(code=4401)
                    return
            except asyncio.CancelledError:
                break

    async def receive(self, text_data=None, bytes_data=None):
        # This channel is server-to-client only. Mutations must pass through the
        # authenticated, validated HTTP API before they are broadcast.
        await self.close(code=4405)

    async def sync_event(self, event):
        await self.send(
            text_data=json.dumps(
                {
                    "event_type": event.get("event_type"),
                    "data": event.get("data"),
                }
            )
        )
