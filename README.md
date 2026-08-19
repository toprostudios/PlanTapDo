# PlanTapDo

PlanTapDo is a personal task planner for iPhone and iPad. The repository now contains only the native SwiftUI client and its Django API; Android and desktop/web builds are intentionally out of scope.

## Repository layout

- `ios/PlanTapDo`: SwiftUI application for iOS 16 and newer.
- `backend`: Django 6 REST API, JWT authentication, and authenticated Channels WebSockets.

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

Tasks without a planned time remain simple list items; scheduled tasks appear on the vertical calendar. The live current-time line updates every second. Overdue work is rescheduled in the stored task data, while the original planned block remains as a pale trail and timer sessions render as solid actual history in the category color (or black for unplanned work).

The Debug configuration uses `http://127.0.0.1:8000/api/`. Release builds fail closed until the `API_BASE_URL` Xcode build setting is set to the deployed API's public `https://` URL. Cloud credentials are stored in the iOS Keychain; local workspace state is stored with complete file protection in Application Support.

Onboarding and payment are intentionally paused: their source files remain available for later work but are excluded from the application target. The current release opens directly into the core planner.

Run the iOS unit tests after installing an iOS Simulator runtime in Xcode:

```bash
xcodebuild -project ios/PlanTapDo.xcodeproj \
  -scheme PlanTapDo \
  -destination 'platform=iOS Simulator,name=<installed simulator name>' \
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
  archive
```

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

Production configuration is fail-closed: without the required secrets, explicit hosts, PostgreSQL, and Redis, the application refuses to start. Follow [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md) for the release command, reverse-proxy requirements, health checks, key rotation, backups, and security verification.

## API surface

- `POST /api/auth/register/`
- `POST /api/auth/token/`
- `POST /api/auth/token/refresh/`
- `POST /api/auth/logout/`
- `GET/PATCH /api/auth/me/`
- `/api/todos/`
- `/api/categories/`
- `/api/sessions/`
- `/api/repeat-rules/`
- `/api/travel-times/`
- `GET/POST /api/sync/`
- `/ws/todos/` with `Authorization: Bearer <access-token>` during the WebSocket handshake

All task data is isolated by authenticated personal account.
