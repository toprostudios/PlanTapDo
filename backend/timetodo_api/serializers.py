from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken
from .models import User, Category, TodoEntry, TimeSession, RepeatRule, LocationTravelTime


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name"]
        read_only_fields = ["id"]


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True, min_length=4)
    tokens = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ["id", "username", "email", "password", "first_name", "last_name", "tokens"]
        read_only_fields = ["id", "tokens"]

    def create(self, validated_data):
        user = User.objects.create_user(
            username=validated_data["username"],
            email=validated_data.get("email", ""),
            password=validated_data["password"],
            first_name=validated_data.get("first_name", ""),
            last_name=validated_data.get("last_name", ""),
        )
        return user

    def get_tokens(self, obj):
        refresh = RefreshToken.for_user(obj)
        return {
            "refresh": str(refresh),
            "access": str(refresh.access_token),
        }


class CategorySerializer(serializers.ModelSerializer):
    color = serializers.CharField(source="color_hex", required=False)

    class Meta:
        model = Category
        fields = ["id", "name", "color_hex", "color", "icon", "notes", "owner"]
        read_only_fields = ["id", "owner"]


class TodoEntrySerializer(serializers.ModelSerializer):
    category_id = serializers.PrimaryKeyRelatedField(
        queryset=Category.objects.all(), source="category", required=False, allow_null=True
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
            "owner",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "owner", "created_at", "updated_at"]


class TimeSessionSerializer(serializers.ModelSerializer):
    duration = serializers.ReadOnlyField()

    class Meta:
        model = TimeSession
        fields = ["id", "todo", "start", "end", "duration"]
        read_only_fields = ["id", "duration"]


class LocationTravelTimeSerializer(serializers.ModelSerializer):
    class Meta:
        model = LocationTravelTime
        fields = ["id", "location_key", "duration_minutes"]
        read_only_fields = ["id"]


class RepeatRuleSerializer(serializers.ModelSerializer):
    class Meta:
        model = RepeatRule
        fields = ["id", "todo", "frequency", "interval", "until_date"]
        read_only_fields = ["id"]

