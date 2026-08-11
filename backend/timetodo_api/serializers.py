from datetime import date, datetime
import re

from django.contrib.auth import password_validation
from django.contrib.auth.models import BaseUserManager
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken

from .models import Category, LocationTravelTime, RepeatRule, TimeSession, TodoEntry, User


MAX_CATEGORY_NOTES_LENGTH = 10_000
MAX_DESCRIPTION_LENGTH = 50_000
MAX_LABELS = 50
MAX_LABEL_LENGTH = 64
MAX_SUBTASKS = 200
MAX_SUBTASK_TITLE_LENGTH = 300
MAX_PLANNED_DURATION_MINUTES = 525_600
MAX_TRAVEL_DURATION_MINUTES = 10_080


def _validate_iso_date_or_datetime(value: str | None, field_name: str) -> str | None:
    if value in (None, ""):
        return value
    if not isinstance(value, str):
        raise serializers.ValidationError("Must be an ISO-8601 string.")

    candidate = value.strip()
    try:
        if "T" in candidate or " " in candidate:
            datetime.fromisoformat(candidate.replace("Z", "+00:00"))
        else:
            date.fromisoformat(candidate)
    except ValueError as exc:
        raise serializers.ValidationError(
            f"{field_name} must be a valid ISO-8601 date or datetime."
        ) from exc
    return candidate


def _normalize_email(value: str) -> str:
    return BaseUserManager.normalize_email(value.strip())


class UserSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(required=True, allow_blank=False)

    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name"]
        read_only_fields = ["id"]

    def validate_email(self, value):
        normalized = _normalize_email(value)
        duplicate = User.objects.filter(email__iexact=normalized)
        if self.instance is not None:
            duplicate = duplicate.exclude(pk=self.instance.pk)
        if duplicate.exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return normalized

    def validate_username(self, value):
        normalized = value.strip()
        duplicate = User.objects.filter(username__iexact=normalized)
        if self.instance is not None:
            duplicate = duplicate.exclude(pk=self.instance.pk)
        if duplicate.exists():
            raise serializers.ValidationError("An account with this username already exists.")
        return normalized


class RegisterSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(required=True, allow_blank=False)
    password = serializers.CharField(
        write_only=True,
        required=True,
        min_length=15,
        max_length=128,
        trim_whitespace=False,
        style={"input_type": "password"},
    )
    tokens = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "email", "password", "first_name", "last_name", "tokens"]
        read_only_fields = ["id", "tokens"]

    def validate_email(self, value):
        normalized = _normalize_email(value)
        if User.objects.filter(email__iexact=normalized).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return normalized

    def validate_username(self, value):
        normalized = value.strip()
        if User.objects.filter(username__iexact=normalized).exists():
            raise serializers.ValidationError("An account with this username already exists.")
        return normalized

    def validate(self, attrs):
        candidate = User(
            username=attrs.get("username", ""),
            email=attrs.get("email", ""),
            first_name=attrs.get("first_name", ""),
            last_name=attrs.get("last_name", ""),
        )
        try:
            password_validation.validate_password(attrs["password"], user=candidate)
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"password": list(exc.messages)}) from exc
        return attrs

    def create(self, validated_data):
        try:
            with transaction.atomic():
                return User.objects.create_user(**validated_data)
        except IntegrityError as exc:
            raise serializers.ValidationError(
                {"detail": "That username or email is already in use."}
            ) from exc

    def get_tokens(self, obj) -> dict[str, str]:
        refresh = RefreshToken.for_user(obj)
        return {"refresh": str(refresh), "access": str(refresh.access_token)}


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField(write_only=True, max_length=4096)


class CategorySerializer(serializers.ModelSerializer):
    color = serializers.CharField(source="color_hex", read_only=True)
    name = serializers.CharField(max_length=100, allow_blank=False, trim_whitespace=True)
    color_hex = serializers.CharField(required=False, max_length=7)
    notes = serializers.CharField(
        required=False,
        allow_blank=True,
        allow_null=True,
        max_length=MAX_CATEGORY_NOTES_LENGTH,
    )

    class Meta:
        model = Category
        fields = ["id", "name", "color_hex", "color", "icon", "notes", "owner"]
        read_only_fields = ["id", "owner"]

    def validate_color_hex(self, value):
        candidate = value.strip()
        if not re.fullmatch(r"#?[0-9A-Fa-f]{6}", candidate):
            raise serializers.ValidationError(
                "Use a six-digit hex color such as #7c6ff7."
            )
        return "#" + candidate.lstrip("#").lower()


class TodoEntrySerializer(serializers.ModelSerializer):
    category = serializers.PrimaryKeyRelatedField(read_only=True)
    category_id = serializers.PrimaryKeyRelatedField(
        queryset=Category.objects.none(),
        source="category",
        required=False,
        allow_null=True,
    )
    title = serializers.CharField(max_length=200, allow_blank=False, trim_whitespace=True)
    description = serializers.CharField(
        required=False,
        allow_blank=True,
        allow_null=True,
        max_length=MAX_DESCRIPTION_LENGTH,
    )
    due_date = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=50)
    do_date = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=50)
    due_time = serializers.RegexField(
        regex=r"^(?:[01]\d|2[0-3]):[0-5]\d$",
        required=False,
        allow_blank=True,
        allow_null=True,
    )
    planned_start_time = serializers.RegexField(
        regex=r"^(?:[01]\d|2[0-3]):[0-5]\d$",
        required=False,
        allow_blank=True,
        allow_null=True,
    )
    original_planned_start_time = serializers.RegexField(
        regex=r"^(?:[01]\d|2[0-3]):[0-5]\d$",
        required=False,
        allow_blank=True,
        allow_null=True,
    )
    overdue_from_date = serializers.CharField(required=False, allow_blank=True, allow_null=True, max_length=50)
    planned_duration = serializers.IntegerField(
        min_value=0,
        max_value=MAX_PLANNED_DURATION_MINUTES,
        required=False,
    )
    labels = serializers.ListField(required=False, allow_empty=True, max_length=MAX_LABELS)
    subtasks = serializers.ListField(required=False, allow_empty=True, max_length=MAX_SUBTASKS)
    sort_order = serializers.IntegerField(min_value=-1_000_000, max_value=1_000_000, required=False)

    class Meta:
        model = TodoEntry
        fields = [
            "id",
            "title",
            "description",
            "due_date",
            "due_time",
            "do_date",
            "planned_start_time",
            "original_planned_start_time",
            "overdue_from_date",
            "planned_duration",
            "descriptive_deadline",
            "category",
            "category_id",
            "status",
            "priority",
            "location",
            "reminder",
            "labels",
            "subtasks",
            "assignee_id",
            "sort_order",
            "completed_at",
            "recurrence_frequency",
            "recurrence_series_id",
            "owner",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "owner", "created_at", "updated_at"]

    def get_fields(self):
        fields = super().get_fields()
        request = self.context.get("request")
        if request is not None and request.user.is_authenticated:
            fields["category_id"].queryset = Category.objects.filter(owner=request.user)
        return fields

    def validate_due_date(self, value):
        return _validate_iso_date_or_datetime(value, "due_date")

    def validate_do_date(self, value):
        return _validate_iso_date_or_datetime(value, "do_date")

    def validate_labels(self, value):
        normalized = []
        for label in value:
            if not isinstance(label, str):
                raise serializers.ValidationError("Every label must be text.")
            label = label.strip()
            if not label or len(label) > MAX_LABEL_LENGTH:
                raise serializers.ValidationError(
                    f"Labels must contain 1 to {MAX_LABEL_LENGTH} characters."
                )
            normalized.append(label)
        return normalized

    def validate_subtasks(self, value):
        normalized = []
        for subtask in value:
            if not isinstance(subtask, dict):
                raise serializers.ValidationError("Every subtask must be an object.")
            subtask_id = subtask.get("id")
            title = subtask.get("title")
            completed = subtask.get("completed", subtask.get("is_completed", False))
            if not isinstance(subtask_id, str) or not 1 <= len(subtask_id) <= 100:
                raise serializers.ValidationError("Every subtask requires a valid id.")
            if not isinstance(title, str) or not 1 <= len(title.strip()) <= MAX_SUBTASK_TITLE_LENGTH:
                raise serializers.ValidationError(
                    f"Subtask titles must contain 1 to {MAX_SUBTASK_TITLE_LENGTH} characters."
                )
            if not isinstance(completed, bool):
                raise serializers.ValidationError("Subtask completion must be true or false.")
            normalized.append(
                {"id": subtask_id, "title": title.strip(), "completed": completed}
            )
        return normalized


class OwnedTodoFieldMixin:
    def get_fields(self):
        fields = super().get_fields()
        request = self.context.get("request")
        if request is not None and request.user.is_authenticated:
            fields["todo"].queryset = TodoEntry.objects.filter(owner=request.user)
        return fields


class TimeSessionSerializer(OwnedTodoFieldMixin, serializers.ModelSerializer):
    todo = serializers.PrimaryKeyRelatedField(queryset=TodoEntry.objects.none())
    duration = serializers.ReadOnlyField()

    class Meta:
        model = TimeSession
        fields = ["id", "todo", "start", "end", "duration"]
        read_only_fields = ["id", "duration"]

    def validate(self, attrs):
        start = attrs.get("start", getattr(self.instance, "start", None))
        end = attrs.get("end", getattr(self.instance, "end", None))
        if end is not None and start is not None and end < start:
            raise serializers.ValidationError({"end": "End time cannot be before start time."})
        return attrs


class LocationTravelTimeSerializer(serializers.ModelSerializer):
    location_key = serializers.CharField(max_length=200, allow_blank=False, trim_whitespace=True)
    duration_minutes = serializers.IntegerField(
        min_value=0,
        max_value=MAX_TRAVEL_DURATION_MINUTES,
        required=False,
    )

    class Meta:
        model = LocationTravelTime
        fields = ["id", "location_key", "duration_minutes"]
        read_only_fields = ["id"]


class RepeatRuleSerializer(OwnedTodoFieldMixin, serializers.ModelSerializer):
    todo = serializers.PrimaryKeyRelatedField(queryset=TodoEntry.objects.none())
    interval = serializers.IntegerField(min_value=1, max_value=365, required=False)

    class Meta:
        model = RepeatRule
        fields = ["id", "todo", "frequency", "interval", "until_date"]
        read_only_fields = ["id"]


class SyncStateSerializer(serializers.Serializer):
    user = UserSerializer(read_only=True)
    categories = CategorySerializer(many=True, required=False)
    todos = TodoEntrySerializer(many=True, required=False)
    sessions = TimeSessionSerializer(many=True, read_only=True)
    travel_times = LocationTravelTimeSerializer(many=True, read_only=True)
    location_travel_times = serializers.DictField(
        child=serializers.IntegerField(min_value=0, max_value=MAX_TRAVEL_DURATION_MINUTES),
        write_only=True,
        required=False,
    )
