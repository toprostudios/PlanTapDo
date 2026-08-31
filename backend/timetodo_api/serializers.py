from datetime import date, datetime
import re

from django.contrib.auth import password_validation
from django.contrib.auth.models import BaseUserManager
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db import IntegrityError, transaction
from django.utils import timezone
from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.serializers import (
    TokenObtainPairSerializer,
    TokenRefreshSerializer,
)

from .account_security import (
    SESSION_ID_CLAIM,
    SESSION_VERSION_CLAIM,
    issue_session_tokens,
    verify_mfa_code,
)
from .models import (
    Category,
    LocationTravelTime,
    RepeatRule,
    TimeSession,
    TodoEntry,
    User,
    UserSession,
)


MAX_CATEGORY_NOTES_LENGTH = 10_000
MAX_DESCRIPTION_LENGTH = 50_000
MAX_LABELS = 50
MAX_LABEL_LENGTH = 64
MAX_SUBTASKS = 200
MAX_SUBTASK_TITLE_LENGTH = 300
MAX_PLANNED_DURATION_MINUTES = 525_600
MAX_TRAVEL_DURATION_MINUTES = 10_080
MAX_NOTIFICATION_LEAD_MINUTES = 10_080


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


def _validate_notification_preference(value: str) -> str:
    """Accept only the notification values understood by the native client."""

    if value in {"none", "atTime"}:
        return value
    match = re.fullmatch(r"(before|beforeAndAtTime):(\d+)", value)
    if match is None:
        raise serializers.ValidationError("Choose a supported notification preference.")
    minutes = int(match.group(2))
    if not 1 <= minutes <= MAX_NOTIFICATION_LEAD_MINUTES:
        raise serializers.ValidationError(
            f"Notification lead time must be between 1 and "
            f"{MAX_NOTIFICATION_LEAD_MINUTES} minutes."
        )
    return f"{match.group(1)}:{minutes}"


class UserSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(required=True, allow_blank=False)

    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name", "mfa_enabled"]
        read_only_fields = ["id", "mfa_enabled"]

    def validate_email(self, value):
        normalized = _normalize_email(value)
        if (
            self.instance is not None
            and normalized.casefold() != self.instance.email.casefold()
        ):
            raise serializers.ValidationError(
                "Email changes require a dedicated re-verification flow."
            )
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
    username = serializers.CharField(
        max_length=150,
        allow_blank=False,
        trim_whitespace=True,
        validators=[],
    )
    email = serializers.EmailField(required=True, allow_blank=False)
    password = serializers.CharField(
        write_only=True,
        required=True,
        min_length=15,
        max_length=128,
        trim_whitespace=False,
        style={"input_type": "password"},
    )

    class Meta:
        model = User
        fields = ["id", "username", "email", "password", "first_name", "last_name"]
        read_only_fields = ["id"]

    def validate_email(self, value):
        return _normalize_email(value)

    def validate_username(self, value):
        return value.strip()

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



class SessionTokenObtainPairSerializer(TokenObtainPairSerializer):
    mfa_code = serializers.CharField(
        required=False, allow_blank=True, write_only=True, max_length=32
    )
    client_label = serializers.CharField(
        required=False, allow_blank=True, write_only=True, max_length=100
    )

    def validate(self, attrs):
        mfa_code = attrs.pop("mfa_code", "")
        client_label = attrs.pop("client_label", "PlanTapDo")
        # Let SimpleJWT perform the normal constant-message credential check,
        # but replace its untracked token pair with a versioned device session.
        super(TokenObtainPairSerializer, self).validate(attrs)
        if self.user.email_verified_at is None:
            raise AuthenticationFailed("Email verification is required.")
        with transaction.atomic():
            locked_user = User.objects.select_for_update().get(pk=self.user.pk)
            if locked_user.mfa_enabled and not verify_mfa_code(
                locked_user, mfa_code, consume_recovery=True
            ):
                raise AuthenticationFailed("A valid MFA or recovery code is required.")
            self.user = locked_user
            return issue_session_tokens(locked_user, client_label)


class SessionTokenRefreshSerializer(TokenRefreshSerializer):
    def validate(self, attrs):
        refresh = self.token_class(attrs["refresh"])
        user_id = refresh.get("user_id")
        session_id = refresh.get(SESSION_ID_CLAIM)
        session_version = refresh.get(SESSION_VERSION_CLAIM)
        session = (
            UserSession.objects.select_related("user")
            .filter(
                id=session_id,
                user_id=user_id,
                revoked_at__isnull=True,
                expires_at__gt=timezone.now(),
            )
            .first()
        )
        if session is None or session_version != session.user.session_version:
            raise AuthenticationFailed("Session has been revoked.")
        data = super().validate(attrs)
        session.save(update_fields=["last_seen_at"])
        return data


class EmailCodeSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)
    code = serializers.RegexField(regex=r"^\d{8}$")
    client_label = serializers.CharField(
        required=False, allow_blank=True, write_only=True, max_length=100
    )


class EmailRequestSerializer(serializers.Serializer):
    email = serializers.EmailField(max_length=254)


class PasswordResetConfirmSerializer(EmailCodeSerializer):
    new_password = serializers.CharField(
        write_only=True,
        min_length=15,
        max_length=128,
        trim_whitespace=False,
        style={"input_type": "password"},
    )

    def validate(self, attrs):
        candidate = User(email=attrs.get("email", ""))
        try:
            password_validation.validate_password(attrs["new_password"], user=candidate)
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"new_password": list(exc.messages)}) from exc
        return attrs


class MFASetupSerializer(serializers.Serializer):
    password = serializers.CharField(write_only=True, max_length=128)


class MFACodeSerializer(serializers.Serializer):
    code = serializers.CharField(write_only=True, max_length=32)


class MFADisableSerializer(MFACodeSerializer):
    password = serializers.CharField(write_only=True, max_length=128)


class AccountDeletionSerializer(serializers.Serializer):
    password = serializers.CharField(
        write_only=True,
        max_length=128,
        trim_whitespace=False,
        style={"input_type": "password"},
    )
    mfa_code = serializers.CharField(
        write_only=True,
        required=False,
        allow_blank=True,
        max_length=32,
    )


class UserSessionSerializer(serializers.ModelSerializer):
    current = serializers.SerializerMethodField()

    class Meta:
        model = UserSession
        fields = ["id", "client_label", "created_at", "last_seen_at", "expires_at", "current"]

    def get_current(self, obj) -> bool:
        request = self.context.get("request")
        return str(getattr(request, "auth", {}).get(SESSION_ID_CLAIM, "")) == str(obj.id)


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField(write_only=True, max_length=4096)


class EmptySerializer(serializers.Serializer):
    pass


class CategorySerializer(serializers.ModelSerializer):
    # The native client creates objects optimistically and refers to them before
    # the network round trip completes. Preserve its UUID so an immediate edit
    # cannot race a server-assigned replacement identifier.
    id = serializers.UUIDField(required=False)
    color = serializers.CharField(source="color_hex", read_only=True)
    name = serializers.CharField(max_length=100, allow_blank=False, trim_whitespace=True)
    color_hex = serializers.CharField(required=False, max_length=7)
    notes = serializers.CharField(
        required=False,
        allow_blank=True,
        allow_null=True,
        max_length=MAX_CATEGORY_NOTES_LENGTH,
    )
    notificationPreference = serializers.CharField(
        source="notification_preference", required=False, allow_blank=False, max_length=40
    )

    class Meta:
        model = Category
        fields = ["id", "name", "color_hex", "color", "icon", "notes", "notificationPreference", "owner"]
        read_only_fields = ["owner"]

    def validate_id(self, value):
        if self.instance is None and Category.objects.filter(pk=value).exists():
            raise serializers.ValidationError("This identifier is unavailable.")
        return value

    def update(self, instance, validated_data):
        # A resource identifier is create-only even though clients include it in
        # full PUT payloads.
        validated_data.pop("id", None)
        return super().update(instance, validated_data)

    def validate_color_hex(self, value):
        candidate = value.strip()
        if not re.fullmatch(r"#?[0-9A-Fa-f]{6}", candidate):
            raise serializers.ValidationError(
                "Use a six-digit hex color such as #7c6ff7."
            )
        return "#" + candidate.lstrip("#").lower()

    def validate_notificationPreference(self, value):
        return _validate_notification_preference(value)


class TodoEntrySerializer(serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
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
    scheduled_not_before = serializers.DateTimeField(required=False, allow_null=True)
    planned_duration = serializers.IntegerField(
        min_value=0,
        max_value=MAX_PLANNED_DURATION_MINUTES,
        required=False,
    )
    notificationPreference = serializers.CharField(
        source="notification_preference", required=False, allow_null=True,
        allow_blank=False, max_length=40
    )
    labels = serializers.ListField(required=False, allow_empty=True, max_length=MAX_LABELS)
    subtasks = serializers.ListField(required=False, allow_empty=True, max_length=MAX_SUBTASKS)
    recurrence_weekdays = serializers.ListField(
        child=serializers.IntegerField(min_value=1, max_value=7),
        required=False,
        allow_empty=True,
        max_length=7,
    )
    sort_order = serializers.IntegerField(min_value=-1_000_000, max_value=1_000_000, required=False)
    split_original_duration = serializers.IntegerField(
        min_value=0,
        max_value=MAX_PLANNED_DURATION_MINUTES,
        required=False,
        allow_null=True,
    )

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
            "scheduled_not_before",
            "planned_duration",
            "descriptive_deadline",
            "category",
            "category_id",
            "status",
            "priority",
            "location",
            "reminder",
            "notificationPreference",
            "labels",
            "subtasks",
            "assignee_id",
            "sort_order",
            "completed_at",
            "recurrence_frequency",
            "recurrence_weekdays",
            "recurrence_series_id",
            "split_parent_id",
            "split_original_duration",
            "owner",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["owner", "created_at", "updated_at"]

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
        seen_ids = set()
        for subtask in value:
            if not isinstance(subtask, dict):
                raise serializers.ValidationError("Every subtask must be an object.")
            subtask_id = subtask.get("id")
            title = subtask.get("title")
            completed = subtask.get("completed", subtask.get("is_completed", False))
            if not isinstance(subtask_id, str) or not 1 <= len(subtask_id) <= 100:
                raise serializers.ValidationError("Every subtask requires a valid id.")
            if subtask_id in seen_ids:
                raise serializers.ValidationError("Subtask ids must be unique within a task.")
            if not isinstance(title, str) or not 1 <= len(title.strip()) <= MAX_SUBTASK_TITLE_LENGTH:
                raise serializers.ValidationError(
                    f"Subtask titles must contain 1 to {MAX_SUBTASK_TITLE_LENGTH} characters."
                )
            if not isinstance(completed, bool):
                raise serializers.ValidationError("Subtask completion must be true or false.")
            normalized.append(
                {"id": subtask_id, "title": title.strip(), "completed": completed}
            )
            seen_ids.add(subtask_id)
        return normalized

    def validate_notificationPreference(self, value):
        return _validate_notification_preference(value)

    def validate_recurrence_weekdays(self, value):
        if len(set(value)) != len(value):
            raise serializers.ValidationError("Repeat weekdays must be unique.")
        return sorted(value)

    def validate(self, attrs):
        attrs = super().validate(attrs)
        frequency = attrs.get(
            "recurrence_frequency",
            getattr(self.instance, "recurrence_frequency", TodoEntry.Recurrence.NONE),
        )
        weekdays = attrs.get(
            "recurrence_weekdays",
            getattr(self.instance, "recurrence_weekdays", []),
        )
        if frequency == TodoEntry.Recurrence.CUSTOM and not weekdays:
            raise serializers.ValidationError(
                {"recurrence_weekdays": "Choose at least one weekday for a custom repeat."}
            )
        if frequency != TodoEntry.Recurrence.CUSTOM:
            attrs["recurrence_weekdays"] = []
        return attrs

    def validate_id(self, value):
        if self.instance is None and TodoEntry.objects.filter(pk=value).exists():
            raise serializers.ValidationError("This identifier is unavailable.")
        return value

    def update(self, instance, validated_data):
        validated_data.pop("id", None)
        return super().update(instance, validated_data)


class OwnedTodoFieldMixin:
    def get_fields(self):
        fields = super().get_fields()
        request = self.context.get("request")
        if request is not None and request.user.is_authenticated:
            fields["todo"].queryset = TodoEntry.objects.filter(owner=request.user)
        return fields


class TimeSessionSerializer(OwnedTodoFieldMixin, serializers.ModelSerializer):
    id = serializers.UUIDField(required=False)
    todo = serializers.PrimaryKeyRelatedField(queryset=TodoEntry.objects.none())
    duration = serializers.ReadOnlyField()

    class Meta:
        model = TimeSession
        fields = ["id", "todo", "start", "end", "duration"]
        read_only_fields = ["duration"]

    def validate_id(self, value):
        if self.instance is None and TimeSession.objects.filter(pk=value).exists():
            raise serializers.ValidationError("This identifier is unavailable.")
        return value

    def validate(self, attrs):
        start = attrs.get("start", getattr(self.instance, "start", None))
        end = attrs.get("end", getattr(self.instance, "end", None))
        if end is not None and start is not None and end < start:
            raise serializers.ValidationError({"end": "End time cannot be before start time."})
        return attrs

    def update(self, instance, validated_data):
        validated_data.pop("id", None)
        return super().update(instance, validated_data)


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

    def validate_location_key(self, value):
        request = self.context.get("request")
        if request is None or not request.user.is_authenticated:
            return value

        duplicate = LocationTravelTime.objects.filter(
            owner=request.user,
            location_key=value,
        )
        if self.instance is not None:
            duplicate = duplicate.exclude(pk=self.instance.pk)
        if duplicate.exists():
            raise serializers.ValidationError(
                "Travel time for this location pair already exists."
            )
        return value


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
    sessions = TimeSessionSerializer(many=True, required=False)
    travel_times = LocationTravelTimeSerializer(many=True, read_only=True)
    location_travel_times = serializers.DictField(
        child=serializers.IntegerField(min_value=0, max_value=MAX_TRAVEL_DURATION_MINUTES),
        write_only=True,
        required=False,
    )
    deleted_todo_ids = serializers.ListField(
        child=serializers.UUIDField(), write_only=True, required=False
    )
    deleted_category_ids = serializers.ListField(
        child=serializers.UUIDField(), write_only=True, required=False
    )
    deleted_session_ids = serializers.ListField(
        child=serializers.UUIDField(), write_only=True, required=False
    )
