from django.contrib.auth.models import AbstractUser
from django.core.validators import MaxValueValidator, MinValueValidator, RegexValidator
from django.db import models
from django.db.models.functions import Lower
import uuid


hex_color_validator = RegexValidator(
    regex=r"^#[0-9A-Fa-f]{6}$",
    message="Use a six-digit hex color such as #7c6ff7.",
)
time_validator = RegexValidator(
    regex=r"^(?:[01]\d|2[0-3]):[0-5]\d$",
    message="Use a 24-hour time in HH:MM format.",
)

class User(AbstractUser):
    """Extend AbstractUser for user profile and settings."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email_verified_at = models.DateTimeField(blank=True, null=True)
    session_version = models.PositiveIntegerField(default=1)
    mfa_enabled = models.BooleanField(default=False)
    mfa_secret_encrypted = models.TextField(blank=True, default="")
    mfa_pending_secret_encrypted = models.TextField(blank=True, default="")
    mfa_recovery_code_hashes = models.JSONField(default=list, blank=True)

    class Meta(AbstractUser.Meta):
        constraints = [
            models.UniqueConstraint(Lower("username"), name="unique_username_casefolded"),
            models.UniqueConstraint(
                Lower("email"),
                condition=~models.Q(email=""),
                name="unique_email_casefolded",
            ),
        ]


class AuthChallenge(models.Model):
    class Kind(models.TextChoices):
        VERIFY_EMAIL = "verify_email", "Verify email"
        RESET_PASSWORD = "reset_password", "Reset password"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="auth_challenges")
    kind = models.CharField(max_length=20, choices=Kind.choices)
    code_digest = models.CharField(max_length=128)
    attempts = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    consumed_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        indexes = [
            models.Index(
                fields=["user", "kind", "created_at"],
                name="challenge_user_kind_idx",
            )
        ]


class UserSession(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="sessions")
    client_label = models.CharField(max_length=100, blank=True, default="PlanTapDo")
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(blank=True, null=True)

    class Meta:
        indexes = [
            models.Index(
                fields=["user", "revoked_at", "expires_at"],
                name="session_user_active_idx",
            )
        ]

class Category(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)
    color_hex = models.CharField(
        max_length=7,
        default="#7c6ff7",
        validators=[hex_color_validator],
    )
    icon = models.CharField(max_length=10, blank=True, null=True, default="📁")
    notes = models.TextField(blank=True, null=True, default="", max_length=10_000)
    notification_preference = models.CharField(max_length=40, default="none")
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="categories")

    def __str__(self):
        return self.name

    class Meta:
        indexes = [models.Index(fields=["owner", "name"], name="category_owner_name_idx")]

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

    class Recurrence(models.TextChoices):
        NONE = "none", "Does not repeat"
        DAILY = "daily", "Daily"
        WEEKLY = "weekly", "Weekly"
        MONTHLY = "monthly", "Monthly"
        CUSTOM = "custom", "Custom weekdays"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True, null=True, default="", max_length=50_000)
    due_date = models.CharField(max_length=50, blank=True, null=True) # YYYY-MM-DD or ISO
    due_time = models.CharField(
        max_length=10, blank=True, null=True, validators=[time_validator]
    )
    do_date = models.CharField(max_length=50, blank=True, null=True)  # YYYY-MM-DD
    planned_start_time = models.CharField(
        max_length=10, blank=True, null=True, validators=[time_validator]
    )
    planned_duration = models.PositiveIntegerField(
        default=30,
        help_text="Minutes",
        validators=[MaxValueValidator(525_600)],
    )
    descriptive_deadline = models.CharField(max_length=200, blank=True, null=True)
    category = models.ForeignKey(
        Category,
        on_delete=models.SET_NULL,
        related_name="todos",
        null=True,
        blank=True,
    )
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    priority = models.CharField(max_length=20, choices=Priority.choices, default=Priority.MEDIUM)
    location = models.CharField(max_length=200, blank=True, null=True)
    reminder = models.CharField(max_length=100, blank=True, null=True)
    notification_preference = models.CharField(max_length=40, blank=True, null=True)
    labels = models.JSONField(default=list, blank=True)
    subtasks = models.JSONField(default=list, blank=True)
    assignee_id = models.CharField(max_length=100, blank=True, null=True)
    sort_order = models.IntegerField(default=0)
    completed_at = models.DateTimeField(blank=True, null=True)
    recurrence_frequency = models.CharField(
        max_length=10,
        choices=Recurrence.choices,
        default=Recurrence.NONE,
    )
    recurrence_weekdays = models.JSONField(default=list, blank=True)
    recurrence_series_id = models.UUIDField(blank=True, null=True)
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="todos")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.title

    class Meta:
        indexes = [
            models.Index(
                fields=["owner", "do_date", "planned_start_time"],
                name="todo_owner_schedule_idx",
            ),
            models.Index(
                fields=["owner", "status", "updated_at"],
                name="todo_owner_status_idx",
            ),
        ]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(planned_duration__lte=525_600),
                name="todo_duration_reasonable",
            )
        ]

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

    class Meta:
        indexes = [models.Index(fields=["todo", "start"], name="session_todo_start_idx")]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(end__isnull=True) | models.Q(end__gte=models.F("start")),
                name="session_end_after_start",
            )
        ]

class LocationTravelTime(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name="travel_times")
    location_key = models.CharField(max_length=200) # e.g. "hq office|gym"
    duration_minutes = models.PositiveIntegerField(
        default=15,
        validators=[MaxValueValidator(10_080)],
    )

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["owner", "location_key"], name="unique_owner_location_key"
            ),
            models.CheckConstraint(
                condition=models.Q(duration_minutes__lte=10_080),
                name="travel_duration_reasonable",
            ),
        ]

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
    interval = models.PositiveIntegerField(
        default=1,
        help_text="Every N units",
        validators=[MinValueValidator(1), MaxValueValidator(365)],
    )
    until_date = models.DateField(blank=True, null=True)

    def __str__(self):
        return f"{self.frequency} repeat for {self.todo.title}"

    class Meta:
        indexes = [models.Index(fields=["todo", "frequency"], name="repeat_todo_frequency_idx")]
        constraints = [
            models.CheckConstraint(
                condition=models.Q(interval__gte=1, interval__lte=365),
                name="repeat_interval_reasonable",
            )
        ]
