from django.db import models
from django.contrib.auth.models import AbstractUser
import uuid

class User(AbstractUser):
    """Extend AbstractUser if additional fields are needed later."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

class Category(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    color_hex = models.CharField(max_length=7)  # e.g. "#FF5733"
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="categories")

    def __str__(self):
        return self.name

class TodoEntry(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        IN_PROGRESS = "in_progress", "In Progress"
        COMPLETED = "completed", "Completed"
        ARCHIVED = "archived", "Archived"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, null=True)
    due_date = models.DateTimeField(blank=True, null=True)
    planned_duration = models.PositiveIntegerField(blank=True, null=True, help_text="Minutes")
    category = models.ForeignKey(Category, on_delete=models.CASCADE, related_name="todos")
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="todos")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.title

class TimeSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    todo = models.ForeignKey(TodoEntry, on_delete=models.CASCADE, related_name="time_sessions")
    start = models.DateTimeField()
    end = models.DateTimeField(blank=True, null=True)

    @property
    def duration(self):
        if self.end:
            return (self.end - self.start).total_seconds() / 60  # minutes
        return None

    def __str__(self):
        return f"Session for {self.todo.title}"

class RepeatRule(models.Model):
    class Frequency(models.TextChoices):
        DAILY = "daily", "Daily"
        WEEKLY = "weekly", "Weekly"
        MONTHLY = "monthly", "Monthly"
        YEARLY = "yearly", "Yearly"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    todo = models.ForeignKey(TodoEntry, on_delete=models.CASCADE, related_name="repeat_rules")
    frequency = models.CharField(max_length=10, choices=Frequency.choices)
    interval = models.PositiveIntegerField(default=1, help_text="Every N units")
    until_date = models.DateField(blank=True, null=True)

    def __str__(self):
        return f"{self.frequency} repeat for {self.todo.title}"
