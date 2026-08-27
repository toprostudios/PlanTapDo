import logging
import uuid

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from django.conf import settings
from django.core.cache import cache
from django.db import IntegrityError, connection, transaction
from django.utils import timezone
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

from .account_security import (
    SESSION_ID_CLAIM,
    consume_challenge,
    decrypt_mfa_secret,
    encrypt_mfa_secret,
    generate_recovery_codes,
    generate_totp_secret,
    issue_session_tokens,
    mfa_provisioning_uri,
    revoke_all_user_sessions,
    revoke_session,
    send_challenge,
    verify_mfa_code,
    verify_totp,
)
from .models import (
    AuthChallenge,
    Category,
    LocationTravelTime,
    RepeatRule,
    TimeSession,
    TodoEntry,
    User,
    UserSession,
)
from .serializers import (
    AccountDeletionSerializer,
    CategorySerializer,
    EmailCodeSerializer,
    EmailRequestSerializer,
    EmptySerializer,
    LocationTravelTimeSerializer,
    LogoutSerializer,
    MFACodeSerializer,
    MFADisableSerializer,
    MFASetupSerializer,
    PasswordResetConfirmSerializer,
    RegisterSerializer,
    RepeatRuleSerializer,
    SessionTokenObtainPairSerializer,
    SessionTokenRefreshSerializer,
    SyncStateSerializer,
    TimeSessionSerializer,
    TodoEntrySerializer,
    UserSerializer,
    UserSessionSerializer,
)
from .security import revoke_access_token, set_tenant_context


logger = logging.getLogger(__name__)

MAX_SYNC_CATEGORIES = settings.ACCOUNT_CATEGORY_QUOTA
MAX_SYNC_TODOS = settings.ACCOUNT_TODO_QUOTA
MAX_SYNC_SESSIONS = settings.ACCOUNT_TIME_SESSION_QUOTA
MAX_SYNC_TRAVEL_TIMES = settings.ACCOUNT_TRAVEL_TIME_QUOTA

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
        with transaction.atomic(), connection.cursor() as cursor:
            if settings.IS_PRODUCTION:
                cursor.execute("SELECT current_schema(), current_user")
                current_schema, current_user = cursor.fetchone()
                sentinel_tenant = uuid.UUID(int=0)
                set_tenant_context(sentinel_tenant)
                cursor.execute(
                    "SELECT plantapdo_security.current_tenant_id(), "
                    "(SELECT count(*) FROM pg_class c "
                    "JOIN pg_namespace n ON n.oid = c.relnamespace "
                    "WHERE n.nspname = %s AND c.relrowsecurity AND c.relname IN "
                    "('timetodo_api_category', 'timetodo_api_todoentry', "
                    "'timetodo_api_locationtraveltime', 'timetodo_api_timesession', "
                    "'timetodo_api_repeatrule'))",
                    [settings.POSTGRES_SCHEMA],
                )
                verified_tenant, rls_table_count = cursor.fetchone()
            else:
                cursor.execute("SELECT 1")
                cursor.fetchone()
        if settings.IS_PRODUCTION:
            if settings.DATABASE_ROLE != "runtime":
                raise RuntimeError("The API process is not using its runtime role")
            if current_schema != settings.POSTGRES_SCHEMA:
                raise RuntimeError("The configured private schema is unavailable")
            if current_user != "plantapdo_runtime":
                raise RuntimeError("The database session is not least-privileged")
            if verified_tenant != sentinel_tenant or rls_table_count != 5:
                raise RuntimeError("Database tenant isolation is unavailable")
        cache_key = "health-ready"
        cache.set(cache_key, "ok", timeout=5)
        if cache.get(cache_key) != "ok":
            raise RuntimeError("Cache health check failed")
    except Exception:
        logger.warning("Readiness check failed", exc_info=True)
        return JsonResponse({"status": "unavailable"}, status=503)
    return JsonResponse({"status": "ok"})


GENERIC_REGISTRATION_RESPONSE = {
    "detail": "If those details can be registered, a verification code has been sent.",
    "verification_required": True,
}


class RegisterView(generics.GenericAPIView):
    queryset = User.objects.none()
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "register"
    serializer_class = RegisterSerializer

    def post(self, request):
        raw_username = str(request.data.get("username", "")).strip()
        raw_email = str(request.data.get("email", "")).strip()
        existing_email_user = User.objects.filter(email__iexact=raw_email).first()
        username_exists = User.objects.filter(username__iexact=raw_username).exists()
        if username_exists or existing_email_user is not None:
            if (
                existing_email_user is not None
                and existing_email_user.email_verified_at is None
                and existing_email_user.username.casefold() == raw_username.casefold()
            ):
                send_challenge(existing_email_user, AuthChallenge.Kind.VERIFY_EMAIL)
            return Response(GENERIC_REGISTRATION_RESPONSE, status=status.HTTP_202_ACCEPTED)

        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            user = serializer.save()
        except serializers.ValidationError:
            # A concurrent registration may win after the pre-check. Keep the
            # externally visible result identical to every other conflict.
            return Response(GENERIC_REGISTRATION_RESPONSE, status=status.HTTP_202_ACCEPTED)
        send_challenge(user, AuthChallenge.Kind.VERIFY_EMAIL)
        return Response(GENERIC_REGISTRATION_RESPONSE, status=status.HTTP_202_ACCEPTED)


class EmailVerificationRequestView(generics.GenericAPIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_email"
    serializer_class = EmailRequestSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = User.objects.filter(
            email__iexact=serializer.validated_data["email"],
            email_verified_at__isnull=True,
        ).first()
        if user is not None:
            send_challenge(user, AuthChallenge.Kind.VERIFY_EMAIL)
        return Response(GENERIC_REGISTRATION_RESPONSE, status=status.HTTP_202_ACCEPTED)


class EmailVerificationConfirmView(generics.GenericAPIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_code"
    serializer_class = EmailCodeSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = consume_challenge(
            data["email"], AuthChallenge.Kind.VERIFY_EMAIL, data["code"]
        )
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=user.pk)
            if user.email_verified_at is None:
                user.email_verified_at = timezone.now()
                user.save(update_fields=["email_verified_at"])
            tokens = issue_session_tokens(user, data.get("client_label", "PlanTapDo"))
        return Response(
            {**UserSerializer(user).data, "tokens": tokens},
            status=status.HTTP_200_OK,
        )


class PasswordResetRequestView(EmailVerificationRequestView):
    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = User.objects.filter(
            email__iexact=serializer.validated_data["email"],
            email_verified_at__isnull=False,
            is_active=True,
        ).first()
        if user is not None:
            send_challenge(user, AuthChallenge.Kind.RESET_PASSWORD)
        return Response(
            {"detail": "If the account exists, a password-reset code has been sent."},
            status=status.HTTP_202_ACCEPTED,
        )


class PasswordResetConfirmView(generics.GenericAPIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_code"
    serializer_class = PasswordResetConfirmSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = consume_challenge(
            data["email"], AuthChallenge.Kind.RESET_PASSWORD, data["code"]
        )
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=user.pk)
            user.set_password(data["new_password"])
            user.save(update_fields=["password"])
            revoke_all_user_sessions(user)
        return Response(status=status.HTTP_204_NO_CONTENT)


class ThrottledTokenObtainPairView(TokenObtainPairView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "login"
    serializer_class = SessionTokenObtainPairSerializer


class ThrottledTokenRefreshView(TokenRefreshView):
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "token_refresh"
    serializer_class = SessionTokenRefreshSerializer


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
            session = UserSession.objects.get(
                id=token.get(SESSION_ID_CLAIM), user=request.user
            )
            token.blacklist()
            revoke_session(session)
        except (TokenError, UserSession.DoesNotExist, ValueError) as exc:
            raise serializers.ValidationError(
                {"refresh": "The refresh token is invalid."}
            ) from exc
        revoke_access_token(request.auth)
        return Response(status=status.HTTP_204_NO_CONTENT)


class LogoutRetryView(generics.GenericAPIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "logout"
    serializer_class = LogoutSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            token = RefreshToken(serializer.validated_data["refresh"])
            session = UserSession.objects.get(
                id=token.get(SESSION_ID_CLAIM),
                user_id=token.get("user_id"),
            )
            token.blacklist()
            revoke_session(session)
        except (TokenError, UserSession.DoesNotExist, ValueError):
            # Retry is idempotent and intentionally reveals nothing about the
            # token or account. Expired/already-revoked input is success.
            pass
        return Response(status=status.HTTP_204_NO_CONTENT)


class SessionListView(generics.ListAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserSessionSerializer

    def get_queryset(self):
        return UserSession.objects.filter(
            user=self.request.user,
            revoked_at__isnull=True,
            expires_at__gt=timezone.now(),
        ).order_by("-last_seen_at")


class SessionDetailView(generics.DestroyAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = UserSessionSerializer

    def get_queryset(self):
        return UserSession.objects.filter(user=self.request.user)

    def perform_destroy(self, instance):
        revoke_session(instance)


class RevokeAllSessionsView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    serializer_class = EmptySerializer

    def post(self, request):
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            revoke_all_user_sessions(user)
        revoke_access_token(request.auth)
        return Response(status=status.HTTP_204_NO_CONTENT)


class AccountDeletionView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_code"
    serializer_class = AccountDeletionSerializer

    def delete(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            if not user.check_password(data["password"]):
                raise serializers.ValidationError(
                    {"detail": "The password or MFA code is invalid."}
                )
            if user.mfa_enabled and not verify_mfa_code(
                user,
                data.get("mfa_code", ""),
                consume_recovery=True,
            ):
                raise serializers.ValidationError(
                    {"detail": "The password or MFA code is invalid."}
                )
            user.delete()

        revoke_access_token(request.auth)
        return Response(status=status.HTTP_204_NO_CONTENT)


class MFASetupView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_code"
    serializer_class = MFASetupSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if not request.user.check_password(serializer.validated_data["password"]):
            raise serializers.ValidationError({"detail": "The current credential is invalid."})
        if request.user.mfa_enabled:
            raise serializers.ValidationError({"detail": "MFA is already enabled."})
        secret = generate_totp_secret()
        request.user.mfa_pending_secret_encrypted = encrypt_mfa_secret(secret)
        request.user.save(update_fields=["mfa_pending_secret_encrypted"])
        return Response(
            {"secret": secret, "provisioning_uri": mfa_provisioning_uri(request.user, secret)}
        )


class MFAConfirmView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_code"
    serializer_class = MFACodeSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            if not user.mfa_pending_secret_encrypted:
                raise serializers.ValidationError({"detail": "Start MFA setup first."})
            secret = decrypt_mfa_secret(user.mfa_pending_secret_encrypted)
            if not verify_totp(secret, serializer.validated_data["code"]):
                raise serializers.ValidationError({"code": "The MFA code is invalid."})
            recovery_codes, recovery_hashes = generate_recovery_codes()
            cleared_secret = str()
            user.mfa_enabled = True
            user.mfa_secret_encrypted = user.mfa_pending_secret_encrypted
            user.mfa_pending_secret_encrypted = cleared_secret
            user.mfa_recovery_code_hashes = recovery_hashes
            user.save(
                update_fields=[
                    "mfa_enabled",
                    "mfa_secret_encrypted",
                    "mfa_pending_secret_encrypted",
                    "mfa_recovery_code_hashes",
                ]
            )
            revoke_all_user_sessions(user)
            tokens = issue_session_tokens(user, "PlanTapDo iOS")
        return Response({"recovery_codes": recovery_codes, "tokens": tokens})


class MFADisableView(generics.GenericAPIView):
    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [ScopedRateThrottle]
    throttle_scope = "account_code"
    serializer_class = MFADisableSerializer

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        with transaction.atomic():
            user = User.objects.select_for_update().get(pk=request.user.pk)
            if not user.check_password(serializer.validated_data["password"]):
                raise serializers.ValidationError({"detail": "The current credential is invalid."})
            if not user.mfa_enabled or not verify_mfa_code(
                user, serializer.validated_data["code"], consume_recovery=True
            ):
                raise serializers.ValidationError({"code": "The MFA code is invalid."})
            cleared_secret = str()
            user.mfa_enabled = False
            user.mfa_secret_encrypted = cleared_secret
            user.mfa_pending_secret_encrypted = cleared_secret
            user.mfa_recovery_code_hashes = []
            user.save(
                update_fields=[
                    "mfa_enabled",
                    "mfa_secret_encrypted",
                    "mfa_pending_secret_encrypted",
                    "mfa_recovery_code_hashes",
                ]
            )
            revoke_all_user_sessions(user)
            tokens = issue_session_tokens(user, "PlanTapDo iOS")
        return Response({"tokens": tokens})


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
    quota_setting = None

    def get_queryset(self):
        return self.queryset.filter(owner=self.request.user)

    def perform_create(self, serializer):
        try:
            with transaction.atomic():
                User.objects.select_for_update().get(pk=self.request.user.pk)
                if self.quota_setting is not None and self.get_queryset().count() >= getattr(
                    settings, self.quota_setting
                ):
                    raise serializers.ValidationError(
                        {"detail": "This account has reached the storage limit for this resource."}
                    )
                instance = serializer.save(owner=self.request.user)
        except IntegrityError as exc:
            # Client-generated UUIDs and scoped unique keys can still race
            # between validation and insertion. Return a client error rather
            # than exposing that database race as HTTP 500.
            raise serializers.ValidationError(
                {"detail": "An object with that identifier or key already exists."}
            ) from exc
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
    quota_setting = "ACCOUNT_CATEGORY_QUOTA"


class TodoEntryViewSet(BaseAuthenticatedViewSet):
    queryset = TodoEntry.objects.select_related("category").all()
    serializer_class = TodoEntrySerializer
    quota_setting = "ACCOUNT_TODO_QUOTA"


class TimeSessionViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    queryset = TimeSession.objects.select_related("todo").all()
    serializer_class = TimeSessionSerializer

    def get_queryset(self):
        return self.queryset.filter(todo__owner=self.request.user)

    def perform_create(self, serializer):
        with transaction.atomic():
            User.objects.select_for_update().get(pk=self.request.user.pk)
            if self.get_queryset().count() >= settings.ACCOUNT_TIME_SESSION_QUOTA:
                raise serializers.ValidationError(
                    {"detail": "This account has reached the time-session storage limit."}
                )
            instance = serializer.save()
        payload = serializer.data
        user_id = self.request.user.id
        transaction.on_commit(
            lambda uid=user_id, evt="timesession_created", p=payload: broadcast_user_update(
                uid, evt, p
            )
        )

    def perform_update(self, serializer):
        instance = serializer.save()
        payload = serializer.data
        user_id = self.request.user.id
        transaction.on_commit(
            lambda uid=user_id, evt="timesession_updated", p=payload: broadcast_user_update(
                uid, evt, p
            )
        )

    def perform_destroy(self, instance):
        instance_id = str(instance.id)
        user_id = self.request.user.id
        instance.delete()
        transaction.on_commit(
            lambda uid=user_id, evt="timesession_deleted", p={"id": instance_id}: broadcast_user_update(
                uid, evt, p
            )
        )


class LocationTravelTimeViewSet(BaseAuthenticatedViewSet):
    queryset = LocationTravelTime.objects.all()
    serializer_class = LocationTravelTimeSerializer
    quota_setting = "ACCOUNT_TRAVEL_TIME_QUOTA"


class RepeatRuleViewSet(viewsets.ModelViewSet):
    permission_classes = [permissions.IsAuthenticated]
    queryset = RepeatRule.objects.select_related("todo").all()
    serializer_class = RepeatRuleSerializer

    def get_queryset(self):
        return self.queryset.filter(todo__owner=self.request.user)

    def perform_create(self, serializer):
        with transaction.atomic():
            User.objects.select_for_update().get(pk=self.request.user.pk)
            if self.get_queryset().count() >= settings.ACCOUNT_REPEAT_RULE_QUOTA:
                raise serializers.ValidationError(
                    {"detail": "This account has reached the repeat-rule storage limit."}
                )
            instance = serializer.save()
        payload = serializer.data
        user_id = self.request.user.id
        transaction.on_commit(
            lambda uid=user_id, evt="repeatrule_created", p=payload: broadcast_user_update(
                uid, evt, p
            )
        )

    def perform_update(self, serializer):
        instance = serializer.save()
        payload = serializer.data
        user_id = self.request.user.id
        transaction.on_commit(
            lambda uid=user_id, evt="repeatrule_updated", p=payload: broadcast_user_update(
                uid, evt, p
            )
        )

    def perform_destroy(self, instance):
        instance_id = str(instance.id)
        user_id = self.request.user.id
        instance.delete()
        transaction.on_commit(
            lambda uid=user_id, evt="repeatrule_deleted", p={"id": instance_id}: broadcast_user_update(
                uid, evt, p
            )
        )


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

    @staticmethod
    def _enforce_response_quotas(user):
        counts_and_limits = (
            (Category.objects.filter(owner=user).count(), settings.ACCOUNT_CATEGORY_QUOTA),
            (TodoEntry.objects.filter(owner=user).count(), settings.ACCOUNT_TODO_QUOTA),
            (
                TimeSession.objects.filter(todo__owner=user).count(),
                settings.ACCOUNT_TIME_SESSION_QUOTA,
            ),
            (
                LocationTravelTime.objects.filter(owner=user).count(),
                settings.ACCOUNT_TRAVEL_TIME_QUOTA,
            ),
        )
        if any(count > limit for count, limit in counts_and_limits):
            raise serializers.ValidationError(
                {"detail": "Account data exceeds the supported sync limit; contact support."}
            )

    def get(self, request):
        user = request.user
        self._enforce_response_quotas(user)
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
        sessions = data.get("sessions", [])
        travel_times = data.get("location_travel_times", {})
        deleted_todo_ids = data.get("deleted_todo_ids", [])
        deleted_category_ids = data.get("deleted_category_ids", [])
        deleted_session_ids = data.get("deleted_session_ids", [])
        if not all(
            isinstance(value, list)
            for value in (
                categories,
                todos,
                sessions,
                deleted_todo_ids,
                deleted_category_ids,
                deleted_session_ids,
            )
        ):
            raise serializers.ValidationError(
                {"detail": "Synced resources and deletion lists must be arrays."}
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
        if len(sessions) > MAX_SYNC_SESSIONS:
            raise serializers.ValidationError(
                {"detail": f"At most {MAX_SYNC_SESSIONS} sessions can be synced at once."}
            )
        if len(travel_times) > MAX_SYNC_TRAVEL_TIMES:
            raise serializers.ValidationError(
                {"detail": f"At most {MAX_SYNC_TRAVEL_TIMES} travel times can be synced at once."}
            )

        context = {"request": request}
        try:
            with transaction.atomic():
                User.objects.select_for_update().get(pk=request.user.pk)
                self._delete_owned_ids(
                    request.user,
                    TimeSession,
                    deleted_session_ids,
                    "session",
                    owner_filter="todo__owner",
                    limit=MAX_SYNC_SESSIONS,
                )
                self._delete_owned_ids(
                    request.user,
                    TodoEntry,
                    deleted_todo_ids,
                    "todo",
                    owner_filter="owner",
                    limit=MAX_SYNC_TODOS,
                )
                self._delete_owned_ids(
                    request.user,
                    Category,
                    deleted_category_ids,
                    "category",
                    owner_filter="owner",
                    limit=MAX_SYNC_CATEGORIES,
                )
                self._sync_categories(request.user, categories, context)
                self._sync_todos(request.user, todos, context)
                self._sync_sessions(request.user, sessions, context)
                self._sync_travel_times(request.user, travel_times, context)
                self._enforce_response_quotas(request.user)
        except IntegrityError as exc:
            raise serializers.ValidationError(
                {"detail": "A synced object has an unavailable identifier or key."}
            ) from exc

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
            "notification_preference": ("notification_preference", "notificationPreference"),
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
            "planned_duration": ("planned_duration", "plannedDuration"),
            "descriptive_deadline": ("descriptive_deadline", "descriptiveDeadline"),
            "category_id": ("category_id", "category"),
            "status": ("status",),
            "priority": ("priority",),
            "location": ("location",),
            "reminder": ("reminder",),
            "notification_preference": ("notification_preference", "notificationPreference"),
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
    def _sync_sessions(user, sessions, context):
        aliases = {
            "todo": ("todo", "todo_id", "todoId"),
            "start": ("start",),
            "end": ("end",),
        }
        for session_data in sessions:
            if not isinstance(session_data, dict):
                raise serializers.ValidationError(
                    {"detail": "Each session must be an object."}
                )
            session_id = _parse_client_uuid(session_data.get("id"), "session")
            existing = TimeSession.objects.filter(pk=session_id).first()
            if existing is not None and existing.todo.owner_id != user.id:
                raise serializers.ValidationError(
                    {"detail": "A synced object has an unavailable identifier."}
                )

            payload = _copy_aliases(session_data, aliases)
            serializer = TimeSessionSerializer(
                existing,
                data=payload,
                partial=existing is not None,
                context=context,
            )
            serializer.is_valid(raise_exception=True)
            if existing is None:
                serializer.save(id=session_id)
            else:
                serializer.save()

    @staticmethod
    def _delete_owned_ids(
        user,
        model,
        raw_ids,
        item_name,
        *,
        owner_filter,
        limit,
    ):
        if len(raw_ids) > limit:
            raise serializers.ValidationError(
                {"detail": f"At most {limit} deleted {item_name} ids can be synced at once."}
            )
        parsed_ids = [_parse_client_uuid(value, item_name) for value in raw_ids]
        if len(set(parsed_ids)) != len(parsed_ids):
            raise serializers.ValidationError(
                {"detail": f"Deleted {item_name} ids must be unique."}
            )
        existing = model.objects.filter(pk__in=parsed_ids)
        foreign_exists = existing.exclude(**{owner_filter: user}).exists()
        if foreign_exists:
            raise serializers.ValidationError(
                {"detail": "A synced object has an unavailable identifier."}
            )
        existing.filter(**{owner_filter: user}).delete()

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
