# Backend deployment and security runbook

The application is configured to fail closed in staging and production. Infrastructure controls are still required: application settings cannot replace a TLS terminator, network policy, managed secret store, edge rate limiting, encrypted backups, or an incident-response process.

## Runtime architecture

- Run the ASGI application with Daphne behind a trusted HTTPS reverse proxy or load balancer.
- Use PostgreSQL with `sslmode=verify-full`, a trusted CA bundle, and a dedicated, least-privilege application role.
- Use authenticated Redis over `rediss://` with certificate validation for shared API throttles, access-token revocation, and Channels.
- Keep PostgreSQL and Redis on private networks; do not expose either service publicly.
- Run the container as its bundled non-root user and mount no writable source-code volume.
- Terminate public TLS with modern protocols and redirect all HTTP traffic to HTTPS.

The included `Dockerfile` pins the Python patch release, installs a transitive dependency lockfile with verified package hashes, and runs as UID/GID `10001`. Build the image in CI, scan the resulting image, sign it, and promote the same immutable digest between environments. Do not rebuild separately for production.

## Required configuration

Start from `.env.example`, but put real values in the deployment platform’s secret manager—not in an `.env` file committed to source control.

Required for staging and production:

- `DJANGO_ENVIRONMENT=staging` or `production`
- `DJANGO_DEBUG=False`
- `DJANGO_SECRET_KEY`: at least 64 random characters
- `JWT_SIGNING_KEY`: a different random value of at least 64 characters
- `DJANGO_ALLOWED_HOSTS`: exact public API hostnames; wildcards are rejected
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_HOST`
- `POSTGRES_SSLMODE=verify-full` and `POSTGRES_SSLROOTCERT`: an absolute path to the trusted database CA bundle
- `REDIS_URL`

Generate secrets with a cryptographically secure generator:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
```

The native iOS client does not require CORS. Leave `DJANGO_CORS_ALLOWED_ORIGINS` empty unless a browser client is deployed; then use only exact HTTPS origins. Configure `DJANGO_CSRF_TRUSTED_ORIGINS` independently if a cookie-authenticated browser surface is ever added.

Set `DJANGO_TRUST_PROXY_SSL_HEADER=True` only when the trusted proxy removes every client-supplied `X-Forwarded-Proto` header and writes its own. Set `DJANGO_NUM_PROXIES` to the exact proxy count so application throttling cannot be keyed from an attacker-controlled forwarding header.

## Release procedure

Run migrations once as a release job before starting the new application revision:

```bash
python manage.py check --deploy
python manage.py migrate --noinput
python manage.py check --deploy
```

Then start the ASGI process:

```bash
daphne --bind 0.0.0.0 --port 8000 --verbosity 1 timetodo_api.asgi:application
```

Do not use Django’s development server in production. Do not run migrations concurrently from every application replica.

Health endpoints:

- `GET /health/live/` verifies the process can answer HTTP.
- `GET /health/ready/` verifies PostgreSQL and the shared cache.

Configure readiness probes through the HTTPS proxy. The readiness response deliberately contains no dependency names or error details.

## Edge and network controls

- Apply request-rate and connection limits at the load balancer, API gateway, or WAF. DRF throttles are defense in depth and are not a DDoS or brute-force boundary.
- Cap request bodies at 2 MiB at the proxy to match `DJANGO_MAX_REQUEST_BYTES`.
- Configure idle and maximum connection timeouts for HTTP and WebSockets.
- Permit WebSocket upgrades only for `/ws/todos/` and preserve the `Authorization` header.
- Never place access or refresh tokens in URLs. Query-string WebSocket tokens are rejected.
- Restrict egress to required PostgreSQL, Redis, Sentry, DNS, and platform endpoints.

## Tokens and account security

- Access tokens expire after 15 minutes by default.
- Refresh tokens expire after seven days, rotate on use, and the previous token is blacklisted.
- `POST /api/auth/logout/` blacklists the supplied refresh token and places the current access-token identifier in shared Redis until it expires. HTTP and WebSocket authentication both enforce that denylist.
- Schedule `python manage.py flushexpiredtokens` daily to remove expired blacklist rows.
- Without MFA, new passwords require at least 15 characters and Django's common-password and similarity checks. Newly stored passwords use explicitly parameterized Argon2id; legacy scrypt and PBKDF2 hashes remain readable and are upgraded after successful login.

Rotate JWT and Django secrets through the secret manager. `DJANGO_SECRET_KEY_FALLBACKS` supports a short Django-key transition window; remove old keys promptly. JWT signing-key rotation invalidates existing sessions, so coordinate it as an intentional reauthentication event.

## Data protection and operations

- Encrypt PostgreSQL and Redis storage, backups, and network traffic.
- Use KMS-backed encryption for RDS, ElastiCache, ECR, CloudWatch Logs, and Secrets Manager. The API stores user task content as ordinary database values; its at-rest protection therefore depends on RDS/KMS, encrypted snapshots, least-privilege database access, and audited operator access rather than custom field-level cryptography.
- Use automated point-in-time PostgreSQL backups with a defined retention period.
- Test restoration regularly; an untested backup is not a recovery plan.
- Restrict production database access to audited operator roles with MFA.
- Configure Sentry with `send_default_pii=False` (the application default), scrub infrastructure logs, and never log authorization headers or request bodies.
- Alert on elevated 401, 403, 429, and 5xx rates; readiness failures; database saturation; Redis failures; and unusual registration or login activity.
- Keep load-balancer access logs on a controlled retention schedule and prevent credentials from entering log fields.

## Release security gates

Install the development tool set and run every gate before publishing an image:

```bash
pip install -r requirements-dev.txt
DJANGO_ENVIRONMENT=test python manage.py test timetodo_api
DJANGO_ENVIRONMENT=test python manage.py makemigrations --check --dry-run
bandit --recursive timetodo_api --exclude timetodo_api/tests.py,timetodo_api/migrations
pip-audit --requirement requirements.lock --disable-pip
```

When production dependencies change, regenerate the reviewed hash lock with `pip-compile --generate-hashes --strip-extras --output-file=requirements.lock requirements.txt`. The container must continue installing with `--require-hashes`; never hand-edit or partially update the generated lock.

Also run `python manage.py check --deploy` with the real production configuration, scan the container OS packages, and review all dependency updates. Re-run the vulnerability audit on a schedule because a clean result only reflects advisories known at scan time.

## AWS ECS/Fargate

The deployment kit in [`aws/`](aws/README.md) targets ECS on Fargate behind an Application Load Balancer, with RDS for PostgreSQL, ElastiCache for Redis, ECR for images, CloudWatch Logs, and Secrets Manager. It is the supported AWS production topology; do not expose Daphne directly to the internet or run it against SQLite.
