# PlanTapDo — Technical Scope Report

**Scope:** Native iOS client and Django backend
**Excluded:** Android, desktop, and web clients

## iOS

The SwiftUI client uses an observable view model and Combine-based REST client. Its supported navigation is Today, Future, Categories, and Settings. Task descriptions are edited in task details and are deliberately omitted from list rows. Planned time is nullable throughout the client so an ordinary to-do never receives a default calendar time.

The hourly calendar scrolls vertically only. One-, three-, and seven-day columns are fit to the available width. For today's pending scheduled tasks, the visual start position follows the current-time line after the planned start passes. Pressing Start marks the task in progress and changes the control to Stop.

## Backend

The Django 6 service exposes JWT registration/token endpoints, owner-filtered REST resources, full-state sync, and authenticated Channels WebSockets. Category, todo, time-session, and repeat-rule relationships are validated so one account cannot attach another account's data.

Production security settings are environment-driven. Development can use SQLite and the in-memory channel layer; Postgres and Redis dependencies are available for deployment.

## Verification expectations

- `python manage.py check`
- `python manage.py makemigrations --check --dry-run`
- `python manage.py test`
- Unsigned generic iOS device build through `xcodebuild`

The repository should contain no Android Gradle source, Node/Vite workspace, desktop/web client, or generated frontend dependencies.
