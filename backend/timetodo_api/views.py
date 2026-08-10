from rest_framework import viewsets, permissions, status, generics
from rest_framework.response import Response
from django.core.exceptions import ValidationError as DjangoValidationError
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .models import Category, TodoEntry, TimeSession, RepeatRule, LocationTravelTime, User
from .serializers import (
    UserSerializer,
    RegisterSerializer,
    CategorySerializer,
    TodoEntrySerializer,
    TimeSessionSerializer,
    RepeatRuleSerializer,
    LocationTravelTimeSerializer,
    SyncStateSerializer,
)


def broadcast_user_update(user_id, event_type, data):
    """Helper to broadcast real-time sync updates to a specific user's channel group."""
    try:
        channel_layer = get_channel_layer()
        if channel_layer:
            async_to_sync(channel_layer.group_send)(
                f"user_{user_id}",
                {
                    "type": "sync_event",
                    "event_type": event_type,
                    "data": data,
                },
            )
    except Exception:
        pass


class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    permission_classes = [permissions.AllowAny]
    serializer_class = RegisterSerializer


class UserProfileView(generics.RetrieveUpdateAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserSerializer

    def get_object(self):
        return self.request.user


class BaseAuthenticatedViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(owner=self.request.user)

    def perform_create(self, serializer):
        instance = serializer.save(owner=self.request.user)
        broadcast_user_update(
            self.request.user.id,
            f"{instance.__class__.__name__.lower()}_created",
            serializer.data,
        )

    def perform_update(self, serializer):
        instance = serializer.save()
        broadcast_user_update(
            self.request.user.id,
            f"{instance.__class__.__name__.lower()}_updated",
            serializer.data,
        )

    def perform_destroy(self, instance):
        instance_id = str(instance.id)
        class_name = instance.__class__.__name__.lower()
        user_id = self.request.user.id
        instance.delete()
        broadcast_user_update(
            user_id,
            f"{class_name}_deleted",
            {"id": instance_id},
        )


class CategoryViewSet(BaseAuthenticatedViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer


class TodoEntryViewSet(BaseAuthenticatedViewSet):
    queryset = TodoEntry.objects.all()
    serializer_class = TodoEntrySerializer


class TimeSessionViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    queryset = TimeSession.objects.all()
    serializer_class = TimeSessionSerializer

    def get_queryset(self):
        return self.queryset.filter(todo__owner=self.request.user)


class LocationTravelTimeViewSet(BaseAuthenticatedViewSet):
    queryset = LocationTravelTime.objects.all()
    serializer_class = LocationTravelTimeSerializer


class RepeatRuleViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    queryset = RepeatRule.objects.all()
    serializer_class = RepeatRuleSerializer

    def get_queryset(self):
        return self.queryset.filter(todo__owner=self.request.user)


STATUS_MAPPING = {
    "todo": "pending",
    "pending": "pending",
    "in-progress": "in_progress",
    "in_progress": "in_progress",
    "done": "completed",
    "completed": "completed",
    "skipped": "skipped",
    "archived": "archived",
}


class SyncView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = SyncStateSerializer

    def get(self, request):
        user = request.user
        categories = Category.objects.filter(owner=user)
        todos = TodoEntry.objects.filter(owner=user)
        sessions = TimeSession.objects.filter(todo__owner=user)
        travel_times = LocationTravelTime.objects.filter(owner=user)

        return Response(
            {
                "user": UserSerializer(user).data,
                "categories": CategorySerializer(categories, many=True).data,
                "todos": TodoEntrySerializer(todos, many=True).data,
                "sessions": TimeSessionSerializer(sessions, many=True).data,
                "travel_times": LocationTravelTimeSerializer(travel_times, many=True).data,
            },
            status=status.HTTP_200_OK,
        )

    def post(self, request):
        user = request.user
        data = request.data

        validation_error = self._validate_sync_payload(data, user)
        if validation_error:
            return Response(validation_error, status=status.HTTP_400_BAD_REQUEST)

        # Sync categories
        for cat_data in data.get("categories", []):
            cat_id = cat_data.get("id")
            Category.objects.update_or_create(
                id=cat_id,
                owner=user,
                defaults={
                    "name": cat_data.get("name", "New Category"),
                    "color_hex": cat_data.get("color_hex") or cat_data.get("color", "#7c6ff7"),
                    "icon": cat_data.get("icon", "📁"),
                    "notes": cat_data.get("notes", ""),
                },
            )

        # Sync todos
        for todo_data in data.get("todos", []):
            todo_id = todo_data.get("id")
            cat_id = todo_data.get("category_id") or todo_data.get("category")
            category_obj = None
            if cat_id:
                category_obj = Category.objects.filter(id=cat_id, owner=user).first()

            raw_status = todo_data.get("status", "pending")
            normalized_status = STATUS_MAPPING.get(raw_status, "pending")

            TodoEntry.objects.update_or_create(
                id=todo_id,
                owner=user,
                defaults={
                    "title": todo_data.get("title", "Untitled Task"),
                    "description": todo_data.get("description", ""),
                    "due_date": todo_data.get("due_date") or todo_data.get("dueDate"),
                    "due_time": todo_data.get("due_time") or todo_data.get("dueTime"),
                    "do_date": todo_data.get("do_date") or todo_data.get("doDate"),
                    "planned_start_time": todo_data.get("planned_start_time") or todo_data.get("plannedStartTime"),
                    "planned_duration": todo_data.get("planned_duration") or todo_data.get("plannedDuration", 30),
                    "descriptive_deadline": todo_data.get("descriptive_deadline") or todo_data.get("descriptiveDeadline"),
                    "category": category_obj,
                    "status": normalized_status,
                    "priority": todo_data.get("priority", "medium"),
                    "location": todo_data.get("location"),
                    "reminder": todo_data.get("reminder"),
                    "labels": todo_data.get("labels", []),
                    "subtasks": todo_data.get("subtasks", []),
                    "assignee_id": todo_data.get("assignee_id") or todo_data.get("assigneeId"),
                    "sort_order": todo_data.get("sort_order") or todo_data.get("sortOrder", 0),
                },
            )

        # Sync travel times
        for key, mins in data.get("location_travel_times", {}).items():
            LocationTravelTime.objects.update_or_create(
                owner=user,
                location_key=key,
                defaults={"duration_minutes": mins},
            )

        broadcast_user_update(user.id, "full_state_synced", {"synced": True})
        return self.get(request)

    @staticmethod
    def _validate_sync_payload(data, user):
        if not isinstance(data, dict):
            return {"detail": "Sync payload must be an object."}

        categories = data.get("categories", [])
        todos = data.get("todos", [])
        travel_times = data.get("location_travel_times", {})

        if not isinstance(categories, list) or not isinstance(todos, list):
            return {"detail": "categories and todos must be arrays."}
        if not isinstance(travel_times, dict):
            return {"detail": "location_travel_times must be an object."}

        payload_category_ids = {
            str(category.get("id"))
            for category in categories
            if isinstance(category, dict) and category.get("id")
        }

        try:
            for category in categories:
                if not isinstance(category, dict):
                    return {"detail": "Each category must be an object."}
                category_id = category.get("id")
                if category_id and Category.objects.filter(id=category_id).exclude(owner=user).exists():
                    return {"detail": "A category ID belongs to another account."}

            for todo in todos:
                if not isinstance(todo, dict):
                    return {"detail": "Each todo must be an object."}
                todo_id = todo.get("id")
                if todo_id and TodoEntry.objects.filter(id=todo_id).exclude(owner=user).exists():
                    return {"detail": "A todo ID belongs to another account."}

                category_id = todo.get("category_id") or todo.get("category")
                if category_id:
                    owns_category = Category.objects.filter(id=category_id, owner=user).exists()
                    if not owns_category and str(category_id) not in payload_category_ids:
                        return {"detail": "A todo references an unknown category."}

                raw_status = todo.get("status", TodoEntry.Status.PENDING)
                normalized_status = STATUS_MAPPING.get(raw_status, raw_status)
                if normalized_status not in TodoEntry.Status.values:
                    return {"detail": f"Invalid todo status: {raw_status}."}

                priority = todo.get("priority", TodoEntry.Priority.MEDIUM)
                if priority not in TodoEntry.Priority.values:
                    return {"detail": f"Invalid todo priority: {priority}."}

                planned_duration = todo.get("planned_duration", todo.get("plannedDuration", 30))
                if not isinstance(planned_duration, int) or planned_duration < 0:
                    return {"detail": "planned_duration must be a non-negative integer."}
        except (DjangoValidationError, TypeError, ValueError):
            return {"detail": "Sync payload contains an invalid ID."}

        if any(not isinstance(minutes, int) or minutes < 0 for minutes in travel_times.values()):
            return {"detail": "Travel times must be non-negative integers."}

        return None
