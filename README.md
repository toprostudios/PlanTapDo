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

The app provides Today, Future, Categories, and Settings tabs. Personal account management lives in Settings. Tasks without a planned time remain simple list items; scheduled tasks appear on the vertical calendar. An overdue task that has not been started is moved below the current-time line until Start is pressed.

The Debug configuration uses `http://127.0.0.1:8000/api/`. Set the `API_BASE_URL` Xcode build setting when testing on a physical device or against another server.

## Backend

Python 3.13 or newer is recommended for Django 6.

```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
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

Production deployments must set `DJANGO_DEBUG=False`, `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`, and `DJANGO_CORS_ALLOWED_ORIGINS`. Redis can be configured with `REDIS_HOST`; local development uses the in-memory channel layer.

## API surface

- `POST /api/auth/register/`
- `POST /api/auth/token/`
- `POST /api/auth/token/refresh/`
- `GET/PATCH /api/auth/me/`
- `/api/todos/`
- `/api/categories/`
- `/api/sessions/`
- `/api/repeat-rules/`
- `/api/travel-times/`
- `GET/POST /api/sync/`
- `/ws/todos/?token=<access-token>`

All task data is isolated by authenticated personal account.
