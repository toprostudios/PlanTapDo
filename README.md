# PlanTapDo

PlanTapDo is a local-first personal task planner for iPhone and iPad. Version 1
ships without accounts or cloud sync; its authoritative product and release
scope is in [PRODUCT_PLAN.md](PRODUCT_PLAN.md). Android, desktop, and web
clients are intentionally out of scope.

## Repository layout

- `ios/PlanTapDo`: SwiftUI application for iOS 16 and newer.
- `backend`: retained future cloud-sync prototype; it is not used by the v1 app.

## iOS app

Open `ios/PlanTapDo.xcodeproj` in Xcode, or verify a device build without code signing:

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO build
```

The app provides Today, Upcoming, Tasks, and Settings tabs. Tasks can repeat
daily, weekly, monthly, or on selected weekdays, and completed tasks stay hidden
unless **Show completed tasks** is enabled. Recurrences are created on the day
they occur rather than pre-generated into future dates.

Tasks without a planned time remain simple list items; scheduled tasks appear on the vertical calendar. The live current-time line updates every second. Unstarted work is moved forward in the stored schedule without leaving a calendar ghost. Only a timer session created by pressing **Start** becomes historical calendar evidence; it remains visible after the task is completed.

Version 1 stores workspace state locally with complete file protection in
Application Support. There is no reachable account, login, or cloud-sync flow.

Onboarding and payment are intentionally paused: their source files remain available for later work but are excluded from the application target. The current release opens directly into the core planner.

Run the iOS unit tests on a connected iPhone or iPad:

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -destination 'platform=iOS,name=<connected device name>' \
  test
```

### TestFlight archive

Version 1 does not require a backend URL. Supply live privacy-policy and
support URLs when archiving.

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/PlanTapDo.xcarchive \
  'PRIVACY_POLICY_URL=https://www.your-domain.example/privacy' \
  'SUPPORT_URL=https://www.your-domain.example/support' \
  archive
```

Both public links must be live before submission. The privacy policy must match
the local-only data behavior described in `PRODUCT_PLAN.md`; the support page
must include a working way to contact you.

Use the repository's configured Apple team and automatic signing in Xcode, then
validate and upload the archive from Organizer. Before each upload, increment
`CURRENT_PROJECT_VERSION`; keep `MARKETING_VERSION` aligned with the App Store
version. The production API URL, Apple distribution certificate/profile, and
App Store Connect access are deployment credentials and are intentionally not
stored in this repository.

## Future cloud-sync prototype (not part of v1)

Python 3.13 or newer is recommended for Django 6.

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
export DJANGO_ENVIRONMENT=development
python manage.py migrate
python manage.py check
python manage.py test
python manage.py runserver
```

For an ASGI server with WebSocket support:

```bash
cd backend
source venv/bin/activate
daphne -b 0.0.0.0 -p 8000 timetodo_api.asgi:application
```

Production configuration is fail-closed: without the required secrets, transactional SMTP, explicit hosts, dedicated Supabase PostgreSQL role/schema, signed RLS tenant context, verified TLS, and Redis, the application refuses to start. Bootstrap the database with [backend/SUPABASE.md](backend/SUPABASE.md), then follow [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md) for the release command, reverse-proxy requirements, health checks, key rotation, backups, and security verification. The dated risk register and accepted product boundaries are in [SECURITY_REVIEW.md](SECURITY_REVIEW.md).

## Future API surface

- `POST /api/auth/register/`
- `POST /api/auth/email/verify/request/`
- `POST /api/auth/email/verify/confirm/`
- `POST /api/auth/password/reset/request/`
- `POST /api/auth/password/reset/confirm/`
- `POST /api/auth/token/`
- `POST /api/auth/token/refresh/`
- `POST /api/auth/logout/`
- `GET /api/auth/sessions/`
- `DELETE /api/auth/sessions/{session-id}/`
- `POST /api/auth/sessions/revoke-all/`
- `DELETE /api/auth/account/`
- `POST /api/auth/mfa/setup/`
- `POST /api/auth/mfa/confirm/`
- `POST /api/auth/mfa/disable/`
- `GET/PATCH /api/auth/me/`
- `/api/todos/`
- `/api/categories/`
- `/api/sessions/`
- `/api/repeat-rules/`
- `/api/travel-times/`
- `GET/POST /api/sync/`
- `/ws/todos/` with `Authorization: Bearer <access-token>` during the WebSocket handshake

All task data is isolated by authenticated personal account.
