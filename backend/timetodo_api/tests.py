from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken
from asgiref.sync import async_to_sync
from channels.testing import WebsocketCommunicator
from .models import User, Category, TodoEntry, TimeSession, LocationTravelTime
from .asgi import application


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
        self.client.logout()
        payload = {
            "username": "newuser",
            "email": "new@plantapdo.app",
            "password": "newpassword123",
            "first_name": "New",
            "last_name": "Account",
        }
        response = self.client.post(self.register_url, payload, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn("tokens", response.data)
        self.assertIn("access", response.data["tokens"])
        self.assertEqual(response.data["username"], "newuser")

    def test_user_registration_rejects_short_password(self):
        self.client.logout()
        response = self.client.post(
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
                "labels": ["backend", "sync"],
                "subtasks": [{"id": "sub1", "title": "Models", "completed": True}],
            },
            format="json",
        )
        self.assertEqual(todo_res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(todo_res.data["title"], "Build Sync API")
        self.assertEqual(todo_res.data["priority"], "high")
        self.assertEqual(len(todo_res.data["subtasks"]), 1)

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
                f"/ws/todos/?token={token}",
                headers=[(b"origin", b"http://localhost")],
            )
            connected, _ = await communicator.connect()
            self.assertTrue(connected)
            await communicator.disconnect()

        async_to_sync(scenario)()
