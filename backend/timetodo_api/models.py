from django.db import models
from django.contrib.auth.models import AbstractUser
import uuid

class User(AbstractUser):
    """Extend AbstractUser for user profile and settings."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

class Category(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    color_hex = models.CharField(max_length=7, default="#7c6ff7")  # e.g. "#7c6ff7"
    icon = models.CharField(max_length=10, blank=True, null=True, default="📁")
    notes = models.TextField(blank=True, null=True, default="")
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="categories")

    def __str__(self):
        return self.name

class TodoEntry(models.Model):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        IN_PROGRESS = "in_progress", "In Progress"
        COMPLETED = "completed", "Completed"
        ARCHIVED = "archived", "Archived"
        SKIPPED = "skipped", "Skipped"

    class Priority(models.TextChoices):
        LOW = "low", "Low"
        MEDIUM = "medium", "Medium"
        HIGH = "high", "High"
        URGENT = "urgent", "Urgent"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, null=True, default="")
    due_date = models.CharField(max_length=50, blank=True, null=True) # YYYY-MM-DD or ISO
    due_time = models.CharField(max_length=10, blank=True, null=True) # HH:MM
    do_date = models.CharField(max_length=50, blank=True, null=True)  # YYYY-MM-DD
    planned_start_time = models.CharField(max_length=10, blank=True, null=True) # HH:MM
    planned_duration = models.PositiveIntegerField(default=30, help_text="Minutes")
    descriptive_deadline = models.CharField(max_length=200, blank=True, null=True)
    category = models.ForeignKey(Category, on_delete=models.CASCADE, related_name="todos", null=True, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    priority = models.CharField(max_length=20, choices=Priority.choices, default=Priority.MEDIUM)
    location = models.CharField(max_length=200, blank=True, null=True)
    reminder = models.CharField(max_length=100, blank=True, null=True)
    labels = models.JSONField(default=list, blank=True)
    subtasks = models.JSONField(default=list, blank=True)
    assignee_id = models.CharField(max_length=100, blank=True, null=True)
    sort_order = models.IntegerField(default=0)
    completed_at = models.DateTimeField(blank=True, null=True)
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
    def duration(self) -> float | None:
        if self.end:
            return (self.end - self.start).total_seconds() / 60  # minutes
        return None

    def __str__(self):
        return f"Session for {self.todo.title}"

class LocationTravelTime(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="travel_times")
    location_key = models.CharField(max_length=200) # e.g. "hq office|gym"
    duration_minutes = models.PositiveIntegerField(default=15)

    class Meta:
        unique_together = ("owner", "location_key")

    def __str__(self):
        return f"{self.location_key}: {self.duration_minutes}m"

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
