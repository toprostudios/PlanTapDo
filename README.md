# PlanTapDo

PlanTapDo is a personal task planner for iPhone and iPad. The repository now contains only the native SwiftUI client and its Django API; Android and desktop/web builds are intentionally out of scope.

## Repository layout

- `ios/PlanTapDo`: SwiftUI application for iOS 16 and newer.
- `backend`: Django 6 REST API, JWT authentication, authenticated Channels WebSockets, and a Supabase-ready private PostgreSQL schema.

## iOS app

Open `ios/PlanTapDo.xcodeproj` in Xcode, or verify a device build without code signing:

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -sdk iphoneos \
  -destination generic/platform=iOS \
  CODE_SIGNING_ALLOWED=NO build
```

The app provides Today, Future, Categories, and Settings tabs. Categories open into their own focused task lists, while Settings contains both general preferences and weekly reports. Tasks can repeat daily, weekly, monthly, or on selected weekdays, and completed tasks stay hidden unless **Show completed tasks** is enabled.

Tasks without a planned time remain simple list items; scheduled tasks appear on the vertical calendar. The live current-time line updates every second. Unstarted work is moved forward in the stored schedule without leaving a calendar ghost. Only a timer session created by pressing **Start** becomes historical calendar evidence; it remains visible after the task is completed.

Cloud accounts keep a protected local cache and synchronize categories, tasks, timer sessions, travel times, and offline deletions with the Django API. A pending local upload is persisted across launches so a temporary network failure cannot turn the next server refresh into local data loss.

The Debug configuration uses `http://127.0.0.1:8000/api/`. Release builds fail closed until the `API_BASE_URL` Xcode build setting is set to the deployed API's public `https://` URL. Cloud credentials are stored in the iOS Keychain; local workspace state is stored with complete file protection in Application Support.

Onboarding and payment are intentionally paused: their source files remain available for later work but are excluded from the application target. The current release opens directly into the core planner.

Run the iOS unit tests on a connected iPhone or iPad:

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -destination 'platform=iOS,name=<connected device name>' \
  test
```

### TestFlight archive

Deploy the backend first and confirm that its public readiness endpoint returns
HTTP 200. Then archive with the exact public API root; the trailing `/api/` is
required. Release builds accept only HTTPS and deliberately disable cloud sync
when this value is missing or invalid.

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -configuration Release \
  -destination generic/platform=iOS \
  -archivePath build/PlanTapDo.xcarchive \
  'API_BASE_URL=https://api.your-domain.example/api/' \
  'PRIVACY_POLICY_URL=https://www.your-domain.example/privacy' \
  'SUPPORT_URL=https://www.your-domain.example/support' \
  archive
```

Both public links must be live before submission. The privacy policy link is
shown inside Settings and must match the privacy-policy URL supplied in App
Store Connect; the support page must include a working way to contact you.

Use the repository's configured Apple team and automatic signing in Xcode, then
validate and upload the archive from Organizer. Before each upload, increment
`CURRENT_PROJECT_VERSION`; keep `MARKETING_VERSION` aligned with the App Store
version. The production API URL, Apple distribution certificate/profile, and
App Store Connect access are deployment credentials and are intentionally not
stored in this repository.

## Backend

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

## API surface

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
