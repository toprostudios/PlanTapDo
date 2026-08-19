import logging
import uuid

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.core.cache import cache
from django.db import IntegrityError, connection, transaction
from django.http import JsonResponse
from django.views.decorators.http import require_GET
from rest_framework import generics, permissions, serializers, status, viewsets
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import (
    TokenObtainPairView,
    TokenRefreshView,
    TokenVerifyView,
)

from .models import Category, LocationTravelTime, RepeatRule, TimeSession, TodoEntry, User
from .serializers import (
    CategorySerializer,
    LocationTravelTimeSerializer,
    LogoutSerializer,
    RegisterSerializer,
    RepeatRuleSerializer,
    SyncStateSerializer,
    TimeSessionSerializer,
    TodoEntrySerializer,
    UserSerializer,
)
from .security import revoke_access_token


logger = logging.getLogger(__name__)

MAX_SYNC_CATEGORIES = 500
MAX_SYNC_TODOS = 5_000
MAX_SYNC_TRAVEL_TIMES = 1_000

STATUS_MAPPING = {
    "todo": TodoEntry.Status.PENDING,
    "pending": TodoEntry.Status.PENDING,
    "in-progress": TodoEntry.Status.IN_PROGRESS,
    "in_progress": TodoEntry.Status.IN_PROGRESS,
    "done": TodoEntry.Status.COMPLETED,
    "completed": TodoEntry.Status.COMPLETED,
    "skipped": TodoEntry.Status.SKIPPED,
    "archived": TodoEntry.Status.ARCHIVED,
}


def broadcast_user_update(user_id, event_type, data):
    """Broadcast an update without making the database mutation depend on Redis."""
    try:
        channel_layer = get_channel_layer()
        if channel_layer:
            async_to_sync(channel_layer.group_send)(
                f"user_{user_id}",
                {"type": "sync_event", "event_type": event_type, "data": data},
            )
    except Exception:
        logger.warning("Unable to broadcast account update", exc_info=True)


@require_GET
def health_live(_request):
    return JsonResponse({"status": "ok"})


@require_GET
def health_ready(_request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
        cache_key = "health-ready"
        cache.set(cache_key, "ok", timeout=5)
        if cache.get(cache_key) != "ok":
            raise RuntimeError("Cache health check failed")
    except Exception:
        logger.warning("Readiness check failed", exc_info=True)
        return JsonResponse({"status": "unavailable"}, status=503)
    return JsonResponse({"status": "ok"})


class RegisterView(generics.CreateAPIView):
    queryset = User.objects.none()
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "register"
    serializer_class = RegisterSerializer


class ThrottledTokenObtainPairView(TokenObtainPairView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"


class ThrottledTokenRefreshView(TokenRefreshView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "token_refresh"


class ThrottledTokenVerifyView(TokenVerifyView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "token_verify"


class LogoutView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = LogoutSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            token = RefreshToken(serializer.validated_data["refresh"])
            if str(token.get("user_id")) != str(request.user.id):
                raise TokenError("Token does not belong to the authenticated account")
            token.blacklist()
        except TokenError as exc:
            raise serializers.ValidationError(
                {"refresh": "The refresh token is invalid."}
            ) from exc
        revoke_access_token(request.auth)
        return Response(status=status.HTTP_204_NO_CONTENT)


class UserProfileView(generics.RetrieveUpdateAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserSerializer
    http_method_names = ["get", "patch", "head", "options"]

    def get_object(self):
        return self.request.user

    def perform_update(self, serializer):
        try:
            with transaction.atomic():
                serializer.save()
        except IntegrityError as exc:
            raise serializers.ValidationError(
                {"detail": "That username or email is already in use."}
            ) from exc


class BaseAuthenticatedViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return self.queryset.filter(owner=self.request.user)

    def perform_create(self, serializer):
        instance = serializer.save(owner=self.request.user)
        payload = serializer.data
        user_id = self.request.user.id
        event_type = f"{instance.__class__.__name__.lower()}_created"
        transaction.on_commit(
            lambda uid=user_id, evt=event_type, p=payload: broadcast_user_update(
                uid, evt, p
            )
        )

    def perform_update(self, serializer):
        instance = serializer.save()
        payload = serializer.data
        user_id = self.request.user.id
        event_type = f"{instance.__class__.__name__.lower()}_updated"
        transaction.on_commit(
            lambda uid=user_id, evt=event_type, p=payload: broadcast_user_update(
                uid, evt, p
            )
        )

    def perform_destroy(self, instance):
        instance_id = str(instance.id)
        class_name = instance.__class__.__name__.lower()
        user_id = self.request.user.id
        instance.delete()
        transaction.on_commit(
            lambda uid=user_id, evt=f"{class_name}_deleted", p={"id": instance_id}: broadcast_user_update(
                uid, evt, p
            )
        )


class CategoryViewSet(BaseAuthenticatedViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer


class TodoEntryViewSet(BaseAuthenticatedViewSet):
    queryset = TodoEntry.objects.select_related("category").all()
    serializer_class = TodoEntrySerializer


class TimeSessionViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    queryset = TimeSession.objects.select_related("todo").all()
    serializer_class = TimeSessionSerializer

    def get_queryset(self):
        return self.queryset.filter(todo__owner=self.request.user)


class LocationTravelTimeViewSet(BaseAuthenticatedViewSet):
    queryset = LocationTravelTime.objects.all()
    serializer_class = LocationTravelTimeSerializer


class RepeatRuleViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    queryset = RepeatRule.objects.select_related("todo").all()
    serializer_class = RepeatRuleSerializer

    def get_queryset(self):
        return self.queryset.filter(todo__owner=self.request.user)


def _value(data: dict, *names: str):
    for name in names:
        if name in data:
            return data[name]
    return serializers.empty


def _copy_aliases(data: dict, aliases: dict[str, tuple[str, ...]]) -> dict:
    normalized = {}
    for output_name, input_names in aliases.items():
        value = _value(data, *input_names)
        if value is not serializers.empty:
            normalized[output_name] = value
    return normalized


def _parse_client_uuid(raw_value, item_name: str) -> uuid.UUID:
    if not raw_value:
        raise serializers.ValidationError(
            {"detail": f"Every synced {item_name} requires an id."}
        )
    try:
        return uuid.UUID(str(raw_value))
    except (TypeError, ValueError, AttributeError) as exc:
        raise serializers.ValidationError(
            {"detail": f"A synced {item_name} contains an invalid id."}
        ) from exc


class SyncView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "sync"
    serializer_class = SyncStateSerializer

    def get(self, request):
        user = request.user
        categories = Category.objects.filter(owner=user).order_by("name", "id")
        todos = (
            TodoEntry.objects.filter(owner=user)
            .select_related("category")
            .order_by("do_date", "planned_start_time", "sort_order", "id")
        )
        sessions = TimeSession.objects.filter(todo__owner=user).order_by("start", "id")
        travel_times = LocationTravelTime.objects.filter(owner=user).order_by("location_key")

        context = {"request": request}
        return Response(
            {
                "user": UserSerializer(user, context=context).data,
                "categories": CategorySerializer(categories, many=True, context=context).data,
                "todos": TodoEntrySerializer(todos, many=True, context=context).data,
                "sessions": TimeSessionSerializer(sessions, many=True, context=context).data,
                "travel_times": LocationTravelTimeSerializer(
                    travel_times, many=True, context=context
                ).data,
            },
            status=status.HTTP_200_OK,
        )

    def post(self, request):
        data = request.data
        if not isinstance(data, dict):
            raise serializers.ValidationError({"detail": "Sync payload must be an object."})

        categories = data.get("categories", [])
        todos = data.get("todos", [])
        travel_times = data.get("location_travel_times", {})
        if not isinstance(categories, list) or not isinstance(todos, list):
            raise serializers.ValidationError(
                {"detail": "categories and todos must be arrays."}
            )
        if not isinstance(travel_times, dict):
            raise serializers.ValidationError(
                {"detail": "location_travel_times must be an object."}
            )
        if len(categories) > MAX_SYNC_CATEGORIES:
            raise serializers.ValidationError(
                {"detail": f"At most {MAX_SYNC_CATEGORIES} categories can be synced at once."}
            )
        if len(todos) > MAX_SYNC_TODOS:
            raise serializers.ValidationError(
                {"detail": f"At most {MAX_SYNC_TODOS} todos can be synced at once."}
            )
        if len(travel_times) > MAX_SYNC_TRAVEL_TIMES:
            raise serializers.ValidationError(
                {"detail": f"At most {MAX_SYNC_TRAVEL_TIMES} travel times can be synced at once."}
            )

        context = {"request": request}
        with transaction.atomic():
            User.objects.select_for_update().get(pk=request.user.pk)
            self._sync_categories(request.user, categories, context)
            self._sync_todos(request.user, todos, context)
            self._sync_travel_times(request.user, travel_times, context)

        transaction.on_commit(
            lambda: broadcast_user_update(
                request.user.id, "full_state_synced", {"synced": True}
            )
        )
        return self.get(request)

    @staticmethod
    def _sync_categories(user, categories, context):
        aliases = {
            "name": ("name",),
            "color_hex": ("color_hex", "color"),
            "icon": ("icon",),
            "notes": ("notes",),
        }
        for category_data in categories:
            if not isinstance(category_data, dict):
                raise serializers.ValidationError(
                    {"detail": "Each category must be an object."}
                )
            category_id = _parse_client_uuid(category_data.get("id"), "category")
            existing = Category.objects.filter(pk=category_id).first()
            if existing is not None and existing.owner_id != user.id:
                raise serializers.ValidationError(
                    {"detail": "A synced object has an unavailable identifier."}
                )

            payload = _copy_aliases(category_data, aliases)
            if existing is None:
                payload.setdefault("name", "New Category")
            serializer = CategorySerializer(
                existing,
                data=payload,
                partial=existing is not None,
                context=context,
            )
            serializer.is_valid(raise_exception=True)
            if existing is None:
                serializer.save(id=category_id, owner=user)
            else:
                serializer.save(owner=user)

    @staticmethod
    def _sync_todos(user, todos, context):
        aliases = {
            "title": ("title",),
            "description": ("description",),
            "due_date": ("due_date", "dueDate"),
            "due_time": ("due_time", "dueTime"),
            "do_date": ("do_date", "doDate"),
            "planned_start_time": ("planned_start_time", "plannedStartTime"),
            "original_planned_start_time": (
                "original_planned_start_time",
                "originalPlannedStartTime",
            ),
            "overdue_from_date": ("overdue_from_date", "overdueFromDate"),
            "planned_duration": ("planned_duration", "plannedDuration"),
            "descriptive_deadline": ("descriptive_deadline", "descriptiveDeadline"),
            "category_id": ("category_id", "category"),
            "status": ("status",),
            "priority": ("priority",),
            "location": ("location",),
            "reminder": ("reminder",),
            "labels": ("labels",),
            "subtasks": ("subtasks",),
            "assignee_id": ("assignee_id", "assigneeId"),
            "sort_order": ("sort_order", "sortOrder"),
            "recurrence_frequency": (
                "recurrence_frequency",
                "recurrenceFrequency",
            ),
            "recurrence_weekdays": (
                "recurrence_weekdays",
                "recurrenceWeekdays",
            ),
            "recurrence_series_id": (
                "recurrence_series_id",
                "recurrenceSeriesId",
            ),
            "completed_at": ("completed_at", "completedAt"),
        }
        for todo_data in todos:
            if not isinstance(todo_data, dict):
                raise serializers.ValidationError(
                    {"detail": "Each todo must be an object."}
                )
            todo_id = _parse_client_uuid(todo_data.get("id"), "todo")
            existing = TodoEntry.objects.filter(pk=todo_id).first()
            if existing is not None and existing.owner_id != user.id:
                raise serializers.ValidationError(
                    {"detail": "A synced object has an unavailable identifier."}
                )

            payload = _copy_aliases(todo_data, aliases)
            if "status" in payload:
                payload["status"] = STATUS_MAPPING.get(payload["status"], payload["status"])
            if existing is None:
                payload.setdefault("title", "Untitled Task")

            serializer = TodoEntrySerializer(
                existing,
                data=payload,
                partial=existing is not None,
                context=context,
            )
            serializer.is_valid(raise_exception=True)
            if existing is None:
                serializer.save(id=todo_id, owner=user)
            else:
                serializer.save(owner=user)

    @staticmethod
    def _sync_travel_times(user, travel_times, context):
        for key, duration_minutes in travel_times.items():
            existing = LocationTravelTime.objects.filter(
                owner=user, location_key=key
            ).first()
            serializer = LocationTravelTimeSerializer(
                existing,
                data={"location_key": key, "duration_minutes": duration_minutes},
                context=context,
            )
            serializer.is_valid(raise_exception=True)
            serializer.save(owner=user)
