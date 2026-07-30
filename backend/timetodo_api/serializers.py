from rest_framework import serializers
from .models import User, Category, TodoEntry, TimeSession, RepeatRule


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "username", "email", "first_name", "last_name"]
        read_only_fields = ["id"]


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ["id", "name", "color_hex", "owner"]
        read_only_fields = ["id", "owner"]


class TodoEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = TodoEntry
        fields = [
            "id",
            "title",
            "description",
            "due_date",
            "planned_duration",
            "category",
            "status",
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


class RepeatRuleSerializer(serializers.ModelSerializer):
    class Meta:
        model = RepeatRule
        fields = ["id", "todo", "frequency", "interval", "until_date"]
        read_only_fields = ["id"]
