from django.contrib.auth.hashers import identify_hasher
from django.test import TestCase
from django.urls import reverse
from django.conf import settings
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken
from asgiref.sync import async_to_sync
from channels.testing import WebsocketCommunicator
from .models import User, Category, TodoEntry, TimeSession, LocationTravelTime
from .asgi import application
from .security import revoke_access_token


class AccountAndSyncTests(TestCase):
    def setUp(self):
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
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn("tokens", response.data)
        self.assertIn("access", response.data["tokens"])
        self.assertEqual(response.data["username"], "newuser")
        created_user = User.objects.get(username="newuser")
        self.assertEqual(identify_hasher(created_user.password).algorithm, "argon2")

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

    def test_registration_requires_unique_email_case_insensitively(self):
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

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("email", response.data)

    def test_user_profile_me(self):
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["username"], "testuser")
        self.assertEqual(response.data["email"], "test@plantapdo.app")

        # Update profile
        update_response = self.client.patch(self.me_url, {"first_name": "UpdatedName"}, format="json")
        self.assertEqual(update_response.status_code, status.HTTP_200_OK)
        self.assertEqual(update_response.data["first_name"], "UpdatedName")

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
                "original_planned_start_time": "09:30",
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
        self.assertEqual(todo_res.data["original_planned_start_time"], "09:30")
        self.assertEqual(todo_res.data["recurrence_frequency"], "daily")
        self.assertEqual(len(todo_res.data["subtasks"]), 1)

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
        self.assertEqual(len(post_res.data["travel_times"]), 1)
        self.assertEqual(post_res.data["travel_times"][0]["duration_minutes"], 20)

    def test_sync_rejects_non_object_payload(self):
        response = self.client.post(self.sync_url, [], format="json")

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data["detail"], "Sync payload must be an object.")

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
        refresh = RefreshToken.for_user(self.user)
        access = refresh.access_token
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
        response = client.post(
            reverse("auth_logout"), {"refresh": str(refresh)}, format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        access_response = client.get(self.me_url)
        self.assertEqual(access_response.status_code, status.HTTP_401_UNAUTHORIZED)
        refresh_response = client.post(
            reverse("token_refresh"), {"refresh": str(refresh)}, format="json"
        )
        self.assertEqual(refresh_response.status_code, status.HTTP_401_UNAUTHORIZED)

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


class WebSocketAuthenticationTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(username="socket-user", password="securepassword123")

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
        token = str(RefreshToken.for_user(self.user).access_token)

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

    def test_rejects_tokens_in_query_strings(self):
        token = str(RefreshToken.for_user(self.user).access_token)

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
        token = RefreshToken.for_user(self.user).access_token
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
        token = RefreshToken.for_user(self.user).access_token
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
            message = await communicator.receive_output(timeout=2)
            self.assertEqual(message["type"], "websocket.close")
            self.assertEqual(message["code"], 4401)

        async_to_sync(scenario)()

    def test_socket_rejects_client_side_mutations(self):
        token = str(RefreshToken.for_user(self.user).access_token)

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
from datetime import timedelta
