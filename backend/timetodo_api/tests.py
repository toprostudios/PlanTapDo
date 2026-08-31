from datetime import timedelta
import re
from unittest import mock

from django.contrib.auth.hashers import identify_hasher
from django.core.cache import cache
from django.core import mail
from django.test import TestCase, override_settings
from django.urls import reverse
from django.conf import settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import AccessToken
from asgiref.sync import async_to_sync
from channels.testing import WebsocketCommunicator
from .account_security import issue_session_tokens, totp_code
from .models import User, Category, TodoEntry, TimeSession, LocationTravelTime, UserSession
from .asgi import application
from .security import revoke_access_token


class AccountAndSyncTests(TestCase):
    def setUp(self):
        cache.clear()
        mail.outbox.clear()
        self.client = APIClient()
        self.register_url = reverse("auth_register")
        self.me_url = reverse("auth_me")
        self.sync_url = reverse("sync_state")

        # Create test user
        self.user = User.objects.create_user(
            username="testuser",
            email="test@plantapdo.app",
            password="securepassword123",
            first_name="Test",
            last_name="User",
        )
        self.client.force_authenticate(user=self.user)

    def test_user_registration(self):
        client = APIClient()
        payload = {
            "username": "newuser",
            "email": "new@plantapdo.app",
            "password": "N3w!PlanTapDo#2026",
            "first_name": "New",
            "last_name": "Account",
        }
        response = client.post(self.register_url, payload, format="json")
        self.assertEqual(response.status_code, status.HTTP_202_ACCEPTED)
        self.assertNotIn("tokens", response.data)
        self.assertTrue(response.data["verification_required"])
        self.assertEqual(len(mail.outbox), 1)
        code = re.search(r"\b\d{8}\b", mail.outbox[0].body).group(0)
        confirmation = client.post(
            reverse("auth_email_verify_confirm"),
            {"email": payload["email"], "code": code, "client_label": "Test iPhone"},
            format="json",
        )
        self.assertEqual(confirmation.status_code, status.HTTP_200_OK)
        self.assertIn("access", confirmation.data["tokens"])
        self.assertEqual(confirmation.data["username"], "newuser")
        created_user = User.objects.get(username="newuser")
        self.assertEqual(identify_hasher(created_user.password).algorithm, "argon2")
        self.assertIsNotNone(created_user.email_verified_at)
        self.assertTrue(UserSession.objects.filter(user=created_user, client_label="Test iPhone").exists())

    def test_user_registration_rejects_short_password(self):
        client = APIClient()
        response = client.post(
            self.register_url,
            {
                "username": "short-password",
                "email": "short@plantapdo.app",
                "password": "short",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)

    def test_user_registration_rejects_common_password(self):
        client = APIClient()
        response = client.post(
            self.register_url,
            {
                "username": "common-password",
                "email": "common@plantapdo.app",
                "password": "password123",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.data)

    def test_registration_conflict_is_generic_case_insensitively(self):
        client = APIClient()
        response = client.post(
            self.register_url,
            {
                "username": "duplicate-email",
                "email": "TEST@plantapdo.app",
                "password": "An0ther!Strong#Password",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_202_ACCEPTED)
        self.assertEqual(
            set(response.data),
            {"detail", "verification_required"},
        )
        self.assertNotIn("email", str(response.data).lower())

    def test_registration_validation_does_not_reveal_existing_identifier(self):
        client = APIClient()
        existing = client.post(
            self.register_url,
            {
                "username": self.user.username,
                "email": self.user.email,
                "password": "short",
            },
            format="json",
        )
        missing = client.post(
            self.register_url,
            {
                "username": "not-registered",
                "email": "not-registered@plantapdo.app",
                "password": "short",
            },
            format="json",
        )

        self.assertEqual(existing.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(existing.status_code, missing.status_code)
        self.assertEqual(existing.data, missing.data)

    def test_user_profile_me(self):
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["username"], "testuser")
        self.assertEqual(response.data["email"], "test@plantapdo.app")

        # Update profile
        update_response = self.client.patch(self.me_url, {"first_name": "UpdatedName"}, format="json")
        self.assertEqual(update_response.status_code, status.HTTP_200_OK)
        self.assertEqual(update_response.data["first_name"], "UpdatedName")

    def test_verified_profile_cannot_change_email_without_reverification(self):
        self.user.email_verified_at = timezone.now()
        self.user.save(update_fields=["email_verified_at"])

        response = self.client.patch(
            self.me_url,
            {"email": "unverified-new-address@plantapdo.app"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.user.refresh_from_db()
        self.assertEqual(self.user.email, "test@plantapdo.app")
        self.assertIsNotNone(self.user.email_verified_at)

    def test_account_deletion_requires_password_and_removes_all_account_data(self):
        category = Category.objects.create(name="Private", owner=self.user)
        todo = TodoEntry.objects.create(title="Delete me", owner=self.user, category=category)
        TimeSession.objects.create(todo=todo, start=timezone.now())
        LocationTravelTime.objects.create(
            owner=self.user,
            location_key="home|office",
            duration_minutes=20,
        )

        wrong_password = self.client.delete(
            reverse("auth_account_delete"),
            {"password": "not-the-password", "mfa_code": ""},
            format="json",
        )
        self.assertEqual(wrong_password.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=self.user.pk).exists())

        mfa_setup = self.client.post(
            reverse("auth_mfa_setup"),
            {"password": "securepassword123"},
            format="json",
        )
        self.assertEqual(mfa_setup.status_code, status.HTTP_200_OK)
        mfa_secret = mfa_setup.data["secret"]
        mfa_confirmation = self.client.post(
            reverse("auth_mfa_confirm"),
            {"code": totp_code(mfa_secret)},
            format="json",
        )
        self.assertEqual(mfa_confirmation.status_code, status.HTTP_200_OK)

        self.user.refresh_from_db()
        tokens = issue_session_tokens(self.user, client_label="Deletion test")
        authenticated_client = APIClient()
        authenticated_client.credentials(
            HTTP_AUTHORIZATION=f"Bearer {tokens['access']}"
        )
        missing_mfa = authenticated_client.delete(
            reverse("auth_account_delete"),
            {"password": "securepassword123", "mfa_code": ""},
            format="json",
        )
        self.assertEqual(missing_mfa.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(User.objects.filter(pk=self.user.pk).exists())

        deleted = authenticated_client.delete(
            reverse("auth_account_delete"),
            {
                "password": "securepassword123",
                "mfa_code": totp_code(mfa_secret),
            },
            format="json",
        )

        self.assertEqual(deleted.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(User.objects.filter(pk=self.user.pk).exists())
        self.assertFalse(Category.objects.filter(pk=category.pk).exists())
        self.assertFalse(TodoEntry.objects.filter(pk=todo.pk).exists())
        self.assertFalse(TimeSession.objects.filter(todo_id=todo.pk).exists())
        self.assertFalse(
            LocationTravelTime.objects.filter(location_key="home|office").exists()
        )
        self.assertEqual(
            authenticated_client.get(self.me_url).status_code,
            status.HTTP_401_UNAUTHORIZED,
        )

    def test_category_and_todo_creation(self):
        cat_res = self.client.post(
            reverse("category-list"),
            {"name": "Work", "color_hex": "#7c6ff7", "icon": "💼", "notes": "Project notes"},
            format="json",
        )
        self.assertEqual(cat_res.status_code, status.HTTP_201_CREATED)
        category_id = cat_res.data["id"]

        todo_res = self.client.post(
            reverse("todo-list"),
            {
                "title": "Build Sync API",
                "description": "Cross-platform sync implementation",
                "planned_duration": 45,
                "category_id": category_id,
                "priority": "high",
                "do_date": "2026-07-31",
                "planned_start_time": "10:00",
                "recurrence_frequency": "daily",
                "recurrence_series_id": "33333333-3333-3333-3333-333333333333",
                "labels": ["backend", "sync"],
                "subtasks": [{"id": "sub1", "title": "Models", "completed": True}],
            },
            format="json",
        )
        self.assertEqual(todo_res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(todo_res.data["title"], "Build Sync API")
        self.assertEqual(todo_res.data["priority"], "high")
        self.assertEqual(todo_res.data["recurrence_frequency"], "daily")
        self.assertEqual(len(todo_res.data["subtasks"]), 1)

    def test_client_generated_category_and_todo_ids_are_preserved(self):
        category_id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        todo_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

        category_response = self.client.post(
            reverse("category-list"),
            {"id": category_id, "name": "Optimistic category"},
            format="json",
        )
        todo_response = self.client.post(
            reverse("todo-list"),
            {
                "id": todo_id,
                "title": "Optimistic task",
                "category_id": category_id,
            },
            format="json",
        )

        self.assertEqual(category_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(todo_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(str(category_response.data["id"]), category_id)
        self.assertEqual(str(todo_response.data["id"]), todo_id)
        self.assertTrue(Category.objects.filter(pk=category_id, owner=self.user).exists())
        self.assertTrue(TodoEntry.objects.filter(pk=todo_id, owner=self.user).exists())

    def test_client_generated_time_session_id_is_preserved(self):
        todo = TodoEntry.objects.create(owner=self.user, title="Stable timer")
        session_id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"

        response = self.client.post(
            reverse("session-list"),
            {
                "id": session_id,
                "todo": str(todo.id),
                "start": "2026-08-24T13:00:00Z",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(str(response.data["id"]), session_id)
        self.assertTrue(TimeSession.objects.filter(pk=session_id, todo=todo).exists())

    def test_duplicate_travel_time_returns_validation_error(self):
        payload = {"location_key": "home|office", "duration_minutes": 20}
        first_response = self.client.post(
            reverse("travel-time-list"), payload, format="json"
        )
        duplicate_response = self.client.post(
            reverse("travel-time-list"), payload, format="json"
        )

        self.assertEqual(first_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(duplicate_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("location_key", duplicate_response.data)

    def test_custom_recurrence_weekdays_round_trip(self):
        response = self.client.post(
            reverse("todo-list"),
            {
                "title": "Strength training",
                "recurrence_frequency": "custom",
                "recurrence_weekdays": [6, 2, 4],
                "recurrence_series_id": "77777777-7777-7777-7777-777777777777",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["recurrence_frequency"], "custom")
        self.assertEqual(response.data["recurrence_weekdays"], [2, 4, 6])

    def test_custom_recurrence_requires_a_weekday(self):
        response = self.client.post(
            reverse("todo-list"),
            {
                "title": "Invalid repeat",
                "recurrence_frequency": "custom",
                "recurrence_weekdays": [],
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("recurrence_weekdays", response.data)

    def test_ios_hex_color_is_normalized(self):
        response = self.client.post(
            reverse("category-list"),
            {"name": "Learning", "color_hex": "60A5FA"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["color_hex"], "#60a5fa")

    def test_todo_can_remain_unscheduled_without_description(self):
        response = self.client.post(
            reverse("todo-list"),
            {
                "title": "Simple list item",
                "description": None,
                "planned_start_time": None,
                "do_date": "2026-08-09",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(response.data["description"])
        self.assertIsNone(response.data["planned_start_time"])

    def test_sync_get_and_post(self):
        # Create sample state
        cat = Category.objects.create(owner=self.user, name="Personal", color_hex="#3ecf8e")
        TodoEntry.objects.create(owner=self.user, title="Run 5k", category=cat, priority="medium")

        # GET sync
        get_res = self.client.get(self.sync_url)
        self.assertEqual(get_res.status_code, status.HTTP_200_OK)
        self.assertIn("user", get_res.data)
        self.assertIn("categories", get_res.data)
        self.assertIn("todos", get_res.data)
        self.assertEqual(len(get_res.data["categories"]), 1)
        self.assertEqual(len(get_res.data["todos"]), 1)

        # POST sync push
        sync_payload = {
            "categories": [
                {
                    "id": "11111111-1111-1111-1111-111111111111",
                    "name": "Side Hustle",
                    "color_hex": "#f5a623",
                    "icon": "⚡",
                    "notes": "Hustle notes",
                }
            ],
            "todos": [
                {
                    "id": "22222222-2222-2222-2222-222222222222",
                    "title": "Launch App",
                    "category_id": "11111111-1111-1111-1111-111111111111",
                    "priority": "urgent",
                    "status": "pending",
                    "planned_duration": 60,
                    "recurrence_frequency": "custom",
                    "recurrence_weekdays": [2, 5],
                    "recurrence_series_id": "66666666-6666-6666-6666-666666666666",
                }
            ],
            "location_travel_times": {
                "hq office|gym": 20
            },
        }

        post_res = self.client.post(self.sync_url, sync_payload, format="json")
        self.assertEqual(post_res.status_code, status.HTTP_200_OK)
        self.assertEqual(len(post_res.data["categories"]), 2)
        self.assertEqual(len(post_res.data["todos"]), 2)
        synced_todo = next(
            todo for todo in post_res.data["todos"] if todo["title"] == "Launch App"
        )
        self.assertEqual(synced_todo["recurrence_weekdays"], [2, 5])
        self.assertEqual(len(post_res.data["travel_times"]), 1)
        self.assertEqual(post_res.data["travel_times"][0]["duration_minutes"], 20)

    def test_sync_rejects_non_object_payload(self):
        response = self.client.post(self.sync_url, [], format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], "Sync payload must be an object.")

    def test_sync_round_trips_client_sessions_and_offline_deletions(self):
        deleted_todo = TodoEntry.objects.create(owner=self.user, title="Delete offline")
        deleted_category = Category.objects.create(owner=self.user, name="Old category")
        synced_todo = TodoEntry.objects.create(owner=self.user, title="Tracked work")
        session_id = "88888888-8888-4888-8888-888888888888"

        response = self.client.post(
            self.sync_url,
            {
                "sessions": [
                    {
                        "id": session_id,
                        "todo": str(synced_todo.id),
                        "start": "2026-08-24T13:00:00Z",
                        "end": "2026-08-24T13:30:00Z",
                    }
                ],
                "deleted_todo_ids": [str(deleted_todo.id)],
                "deleted_category_ids": [str(deleted_category.id)],
                "deleted_session_ids": [],
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(TodoEntry.objects.filter(pk=deleted_todo.id).exists())
        self.assertFalse(Category.objects.filter(pk=deleted_category.id).exists())
        self.assertTrue(
            TimeSession.objects.filter(pk=session_id, todo=synced_todo).exists()
        )
        returned = next(item for item in response.data["sessions"] if str(item["id"]) == session_id)
        self.assertEqual(str(returned["todo"]), str(synced_todo.id))

    def test_sync_cannot_delete_or_attach_another_accounts_session(self):
        other = User.objects.create_user(username="session-owner", password="securepassword123")
        foreign_todo = TodoEntry.objects.create(owner=other, title="Private")
        foreign_session = TimeSession.objects.create(todo=foreign_todo, start=timezone.now())

        delete_response = self.client.post(
            self.sync_url,
            {"deleted_session_ids": [str(foreign_session.id)]},
            format="json",
        )
        attach_response = self.client.post(
            self.sync_url,
            {
                "sessions": [
                    {
                        "id": "99999999-9999-4999-8999-999999999999",
                        "todo": str(foreign_todo.id),
                        "start": "2026-08-24T13:00:00Z",
                    }
                ]
            },
            format="json",
        )

        self.assertEqual(delete_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(attach_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertTrue(TimeSession.objects.filter(pk=foreign_session.id).exists())

    def test_api_responses_disable_caching_and_embedding(self):
        response = self.client.get(self.me_url)

        self.assertEqual(response["Cache-Control"], "no-store")
        self.assertEqual(response["X-Frame-Options"], "DENY")
        self.assertIn("default-src 'none'", response["Content-Security-Policy"])

    def test_personal_data_endpoints_require_authentication(self):
        client = APIClient()

        for url in (
            reverse("category-list"),
            reverse("todo-list"),
            reverse("session-list"),
            reverse("travel-time-list"),
            reverse("repeat-rule-list"),
            self.sync_url,
            self.me_url,
        ):
            with self.subTest(url=url):
                response = client.get(url)
                self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_invalid_task_time_is_rejected(self):
        response = self.client.post(
            reverse("todo-list"),
            {"title": "Invalid time", "planned_start_time": "29:99"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("planned_start_time", response.data)

    def test_invalid_notification_preference_is_rejected(self):
        category_response = self.client.post(
            reverse("category-list"),
            {"name": "Unsafe reminder", "notificationPreference": "unexpected:5"},
            format="json",
        )
        todo_response = self.client.post(
            reverse("todo-list"),
            {"title": "Unsafe reminder", "notificationPreference": "before:10081"},
            format="json",
        )

        self.assertEqual(category_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(todo_response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("notificationPreference", category_response.data)
        self.assertIn("notificationPreference", todo_response.data)

    def test_duplicate_subtask_ids_are_rejected(self):
        response = self.client.post(
            reverse("todo-list"),
            {
                "title": "Ambiguous subtasks",
                "subtasks": [
                    {"id": "same", "title": "First", "completed": False},
                    {"id": "same", "title": "Second", "completed": False},
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("subtasks", response.data)

    def test_invalid_sync_rolls_back_every_change(self):
        response = self.client.post(
            self.sync_url,
            {
                "categories": [
                    {
                        "id": "44444444-4444-4444-4444-444444444444",
                        "name": "Must roll back",
                        "color_hex": "#123456",
                    }
                ],
                "todos": [
                    {
                        "id": "55555555-5555-5555-5555-555555555555",
                        "title": "Invalid",
                        "category_id": "44444444-4444-4444-4444-444444444444",
                        "planned_start_time": "99:99",
                    }
                ],
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(Category.objects.filter(name="Must roll back").exists())

    def test_logout_blacklists_refresh_and_revokes_current_access_token(self):
        tokens = issue_session_tokens(self.user, "Logout test")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        response = client.post(
            reverse("auth_logout"), {"refresh": tokens["refresh"]}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        access_response = client.get(self.me_url)
        self.assertEqual(access_response.status_code, status.HTTP_401_UNAUTHORIZED)
        refresh_response = client.post(
            reverse("token_refresh"), {"refresh": tokens["refresh"]}, format="json"
        )
        self.assertEqual(refresh_response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_logout_retry_is_idempotent_without_access_token(self):
        tokens = issue_session_tokens(self.user, "Offline iPhone")
        client = APIClient()
        first = client.post(
            reverse("auth_logout_retry"), {"refresh": tokens["refresh"]}, format="json"
        )
        second = client.post(
            reverse("auth_logout_retry"), {"refresh": tokens["refresh"]}, format="json"
        )

        self.assertEqual(first.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(second.status_code, status.HTTP_204_NO_CONTENT)
        self.assertIsNotNone(UserSession.objects.get(client_label="Offline iPhone").revoked_at)

    def test_revoke_all_invalidates_every_device_session(self):
        first = issue_session_tokens(self.user, "First iPhone")
        second = issue_session_tokens(self.user, "Second iPhone")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {first['access']}")

        response = client.post(reverse("auth_session_revoke_all"), {}, format="json")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

        for tokens in (first, second):
            refresh_response = APIClient().post(
                reverse("token_refresh"), {"refresh": tokens["refresh"]}, format="json"
            )
            self.assertEqual(refresh_response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_password_reset_is_non_enumerating_and_revokes_sessions(self):
        self.user.email_verified_at = timezone.now()
        self.user.save(update_fields=["email_verified_at"])
        tokens = issue_session_tokens(self.user, "Reset test")
        client = APIClient()
        missing = client.post(
            reverse("auth_password_reset_request"),
            {"email": "missing@plantapdo.app"},
            format="json",
        )
        existing = client.post(
            reverse("auth_password_reset_request"),
            {"email": self.user.email},
            format="json",
        )
        self.assertEqual(missing.status_code, existing.status_code)
        self.assertEqual(missing.data, existing.data)
        code = re.search(r"\b\d{8}\b", mail.outbox[-1].body).group(0)
        confirmation = client.post(
            reverse("auth_password_reset_confirm"),
            {
                "email": self.user.email,
                "code": code,
                "new_password": "A-New!Secure#Password2026",
            },
            format="json",
        )
        self.assertEqual(confirmation.status_code, status.HTTP_204_NO_CONTENT)
        self.assertTrue(User.objects.get(pk=self.user.pk).check_password("A-New!Secure#Password2026"))
        refresh_response = client.post(
            reverse("token_refresh"), {"refresh": tokens["refresh"]}, format="json"
        )
        self.assertEqual(refresh_response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_verified_login_tracks_session_and_requires_mfa_when_enabled(self):
        self.user.email_verified_at = timezone.now()
        self.user.save(update_fields=["email_verified_at"])
        setup = self.client.post(
            reverse("auth_mfa_setup"),
            {"password": "securepassword123"},
            format="json",
        )
        self.assertEqual(setup.status_code, status.HTTP_200_OK)
        confirmation = self.client.post(
            reverse("auth_mfa_confirm"),
            {"code": totp_code(setup.data["secret"])},
            format="json",
        )
        self.assertEqual(confirmation.status_code, status.HTTP_200_OK)
        self.assertEqual(len(confirmation.data["recovery_codes"]), 10)

        anonymous = APIClient()
        missing_mfa = anonymous.post(
            reverse("token_obtain_pair"),
            {"username": self.user.username, "password": "securepassword123"},
            format="json",
        )
        self.assertEqual(missing_mfa.status_code, status.HTTP_401_UNAUTHORIZED)
        login = anonymous.post(
            reverse("token_obtain_pair"),
            {
                "username": self.user.username,
                "password": "securepassword123",
                "mfa_code": totp_code(setup.data["secret"]),
                "client_label": "MFA iPhone",
            },
            format="json",
        )
        self.assertEqual(login.status_code, status.HTTP_200_OK)
        self.assertTrue(UserSession.objects.filter(user=self.user, client_label="MFA iPhone").exists())

    def test_session_inventory_identifies_current_device(self):
        tokens = issue_session_tokens(self.user, "Current iPhone")
        issue_session_tokens(self.user, "Other iPad")
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
        response = client.get(reverse("auth_session_list"))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 2)
        current = next(item for item in response.data if item["current"])
        self.assertEqual(current["client_label"], "Current iPhone")

    @override_settings(ACCOUNT_CATEGORY_QUOTA=1)
    def test_account_quota_bounds_list_responses(self):
        Category.objects.create(owner=self.user, name="Only category")
        response = self.client.post(
            reverse("category-list"), {"name": "Over quota"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Category.objects.filter(owner=self.user).count(), 1)

    def test_health_endpoints_do_not_expose_internals(self):
        client = APIClient()
        live_response = client.get(reverse("health_live"))
        ready_response = client.get(reverse("health_ready"))

        self.assertEqual(live_response.status_code, status.HTTP_200_OK)
        self.assertEqual(ready_response.status_code, status.HTTP_200_OK)
        self.assertEqual(live_response.json(), {"status": "ok"})
        self.assertEqual(ready_response.json(), {"status": "ok"})

    def test_short_lived_rotating_tokens_are_enabled(self):
        self.assertLessEqual(
            settings.SIMPLE_JWT["ACCESS_TOKEN_LIFETIME"].total_seconds(), 15 * 60
        )
        self.assertTrue(settings.SIMPLE_JWT["ROTATE_REFRESH_TOKENS"])
        self.assertTrue(settings.SIMPLE_JWT["BLACKLIST_AFTER_ROTATION"])
        self.assertTrue(settings.SIMPLE_JWT["CHECK_REVOKE_TOKEN"])


class OwnershipIsolationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="owner", password="securepassword123")
        self.other_user = User.objects.create_user(username="other", password="securepassword123")
        self.other_category = Category.objects.create(owner=self.other_user, name="Private")
        self.other_todo = TodoEntry.objects.create(owner=self.other_user, title="Private todo")
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_cannot_assign_another_users_category(self):
        response = self.client.post(
            reverse("todo-list"),
            {"title": "Invalid reference", "category_id": str(self.other_category.id)},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(TodoEntry.objects.filter(owner=self.user).exists())

    def test_cannot_create_session_for_another_users_todo(self):
        response = self.client.post(
            reverse("session-list"),
            {"todo": str(self.other_todo.id), "start": "2026-08-01T12:00:00Z"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertFalse(TimeSession.objects.filter(todo=self.other_todo).exists())

    def test_cannot_create_repeat_rule_for_another_users_todo(self):
        response = self.client.post(
            reverse("repeat-rule-list"),
            {"todo": str(self.other_todo.id), "frequency": "weekly", "interval": 1},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_sync_rejects_foreign_ids_instead_of_crashing(self):
        response = self.client.post(
            reverse("sync_state"),
            {
                "categories": [
                    {"id": str(self.other_category.id), "name": "Overwrite attempt"}
                ]
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.other_category.refresh_from_db()
        self.assertEqual(self.other_category.name, "Private")

    def test_cannot_retrieve_another_users_objects(self):
        category_response = self.client.get(
            reverse("category-detail", args=[self.other_category.id])
        )
        todo_response = self.client.get(reverse("todo-detail", args=[self.other_todo.id]))

        self.assertEqual(category_response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(todo_response.status_code, status.HTTP_404_NOT_FOUND)

    def test_deleting_a_category_does_not_delete_tasks(self):
        own_category = Category.objects.create(owner=self.user, name="Temporary")
        own_todo = TodoEntry.objects.create(
            owner=self.user, category=own_category, title="Keep this task"
        )

        response = self.client.delete(reverse("category-detail", args=[own_category.id]))

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        own_todo.refresh_from_db()
        self.assertIsNone(own_todo.category)

    def test_session_end_cannot_precede_start(self):
        own_todo = TodoEntry.objects.create(owner=self.user, title="Timed task")
        response = self.client.post(
            reverse("session-list"),
            {
                "todo": str(own_todo.id),
                "start": "2026-08-01T12:00:00Z",
                "end": "2026-08-01T11:00:00Z",
            },
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("end", response.data)
        self.assertFalse(TimeSession.objects.filter(todo=own_todo).exists())

    def test_session_and_repeat_rule_crud_operations(self):
        own_todo = TodoEntry.objects.create(owner=self.user, title="Session todo")
        session_resp = self.client.post(
            reverse("session-list"),
            {
                "todo": str(own_todo.id),
                "start": "2026-08-01T12:00:00Z",
                "end": "2026-08-01T12:30:00Z",
            },
            format="json",
        )
        self.assertEqual(session_resp.status_code, status.HTTP_201_CREATED)
        session_id = session_resp.data["id"]

        patch_resp = self.client.patch(
            reverse("session-detail", args=[session_id]),
            {"end": "2026-08-01T12:45:00Z"},
            format="json",
        )
        self.assertEqual(patch_resp.status_code, status.HTTP_200_OK)

        rule_resp = self.client.post(
            reverse("repeat-rule-list"),
            {"todo": str(own_todo.id), "frequency": "daily", "interval": 1},
            format="json",
        )
        self.assertEqual(rule_resp.status_code, status.HTTP_201_CREATED)
        rule_id = rule_resp.data["id"]

        del_rule_resp = self.client.delete(reverse("repeat-rule-detail", args=[rule_id]))
        self.assertEqual(del_rule_resp.status_code, status.HTTP_204_NO_CONTENT)

        del_session_resp = self.client.delete(reverse("session-detail", args=[session_id]))
        self.assertEqual(del_session_resp.status_code, status.HTTP_204_NO_CONTENT)


class WebSocketAuthenticationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="socket-user", password="securepassword123")

    def access_token(self):
        return AccessToken(issue_session_tokens(self.user, "Socket test")["access"])

    def test_rejects_anonymous_connection(self):
        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[(b"origin", b"http://localhost")],
            )
            connected, close_code = await communicator.connect()
            self.assertFalse(connected)
            self.assertEqual(close_code, 4401)

        async_to_sync(scenario)()

    def test_accepts_valid_access_token(self):
        token = self.access_token()

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[
                    (b"origin", b"http://localhost"),
                    (b"authorization", f"Bearer {token}".encode("ascii")),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await communicator.disconnect()

        async_to_sync(scenario)()

    def test_accepts_native_client_without_origin_header(self):
        token = self.access_token()

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[(b"authorization", f"Bearer {token}".encode("ascii"))],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await communicator.disconnect()

        async_to_sync(scenario)()

    def test_rejects_untrusted_browser_origin(self):
        token = self.access_token()

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[
                    (b"origin", b"https://attacker.example"),
                    (b"authorization", f"Bearer {token}".encode("ascii")),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertFalse(connected)

        async_to_sync(scenario)()

    def test_rejects_tokens_in_query_strings(self):
        token = self.access_token()

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                f"/ws/todos/?token={token}",
                headers=[(b"origin", b"http://localhost")],
            )
            connected, close_code = await communicator.connect()
            self.assertFalse(connected)
            self.assertEqual(close_code, 4401)

        async_to_sync(scenario)()

    def test_rejects_revoked_access_token(self):
        token = self.access_token()
        revoke_access_token(token)

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[
                    (b"origin", b"http://localhost"),
                    (b"authorization", f"Bearer {token}".encode("ascii")),
                ],
            )
            connected, close_code = await communicator.connect()
            self.assertFalse(connected)
            self.assertEqual(close_code, 4401)

        async_to_sync(scenario)()

    def test_connected_socket_closes_when_access_token_expires(self):
        token = self.access_token()
        token.set_exp(lifetime=timedelta(seconds=2))

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[
                    (b"origin", b"http://localhost"),
                    (b"authorization", f"Bearer {token}".encode("ascii")),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            message = await communicator.receive_output(timeout=4)
            self.assertEqual(message["type"], "websocket.close")
            self.assertEqual(message["code"], 4401)

        async_to_sync(scenario)()

    def test_connected_socket_fails_closed_when_auth_monitor_errors(self):
        token = self.access_token()
        token.set_exp(lifetime=timedelta(seconds=1))

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[
                    (b"origin", b"http://localhost"),
                    (b"authorization", f"Bearer {token}".encode("ascii")),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            with mock.patch(
                "timetodo_api.consumers.socket_token_is_active",
                side_effect=RuntimeError("cache unavailable"),
            ):
                message = await communicator.receive_output(timeout=3)
            self.assertEqual(message["type"], "websocket.close")
            self.assertEqual(message["code"], 4401)

        async_to_sync(scenario)()

    def test_socket_rejects_client_side_mutations(self):
        token = self.access_token()

        async def scenario():
            communicator = WebsocketCommunicator(
                application,
                "/ws/todos/",
                headers=[
                    (b"origin", b"http://localhost"),
                    (b"authorization", f"Bearer {token}".encode("ascii")),
                ],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await communicator.send_json_to({"type": "forged", "data": {"admin": True}})
            message = await communicator.receive_output()
            self.assertEqual(message["type"], "websocket.close")
            self.assertEqual(message["code"], 4405)

        async_to_sync(scenario)()
