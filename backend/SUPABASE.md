# Supabase PostgreSQL deployment

PlanTapDo uses Supabase as managed PostgreSQL only. The iOS app continues to
authenticate with the Django API and never connects to Supabase directly:

```text
iOS app -> HTTPS/WSS -> Django API -> TLS PostgreSQL -> Supabase
                              |
                              +-> TLS Redis (throttles, logout, WebSockets)
```

Supabase Auth, publishable keys, service-role keys, PostgREST, GraphQL, and
Realtime are not part of this design. Do not add a Supabase key or database
connection string to the iOS target.

## 1. Secure the Supabase project

In the Supabase Dashboard:

1. Choose a region close to the Django deployment.
2. Enable **Enforce SSL on incoming connections** under Database SSL settings.
3. Download the project CA certificate used by `sslmode=verify-full` and make it
   available to the API and migration workloads as a read-only file.
4. Disable the **Data API** integration because this application never uses
   REST or GraphQL database endpoints. Keep the `plantapdo` schema out of the
   exposed-schema list even if the Data API is later enabled for another use.
5. Apply database network restrictions for the fixed egress addresses of the
   API and migration runner. On AWS, route task egress through controlled NAT
   gateways with stable addresses. Use Supabase PrivateLink where the plan and
   hosting topology support it.
6. Enable the backup/PITR option appropriate to the recovery objective and
   schedule restore tests. A provider setting is not a tested recovery plan.

These controls follow Supabase's guidance for [SSL enforcement](https://supabase.com/docs/guides/platform/ssl-enforcement), [disabling an unused Data API](https://supabase.com/docs/guides/api/securing-your-api#disable-the-data-api), and [platform network restrictions](https://supabase.com/docs/guides/security/platform-security).

## 2. Bootstrap the private schema and roles

Run [`supabase/bootstrap.sql`](supabase/bootstrap.sql) in the SQL editor as the
project owner. It creates:

- `plantapdo`: an internal schema with no `public`, `anon`, `authenticated`, or
  `service_role` access;
- `plantapdo_migrator`: owns tables created by Django and can perform DDL;
- `plantapdo_runtime`: can only read and modify rows in existing application
  tables and cannot create schema objects;
- `plantapdo_security`: holds a tenant-context signing key that the runtime role
  cannot read, plus the security-definer verifier used by row-level policies.

Assign the two roles independent, generated passwords of at least 32
characters. To keep plaintext passwords out of shell and SQL-editor history,
connect with `psql` using the project-owner connection and use its interactive
password prompts:

```text
\password plantapdo_migrator
\password plantapdo_runtime
```

Store both passwords in the deployment platform's secret manager. The web/API
workload receives only the runtime password. Only the one-off migration job
receives the migrator password.

Using a project-owner `psql` connection, run
[`supabase/provision_tenant_context.psql`](supabase/provision_tenant_context.psql).
The database generates a 64-byte tenant-context key inside the locked security
schema and the script prints its 128-character lowercase hex representation.
Copy that value directly into the API secret manager as
`DB_TENANT_CONTEXT_KEY`; do not pipe or capture this operator-only command in
CI logs. Re-running the script returns the existing key rather than silently
rotating it. The migrator and runtime roles cannot read the stored copy.

## 3. Choose the connection endpoint

For a persistent Daphne deployment, use Supabase's direct connection on port
`5432` when the hosting network supports IPv6 (or the Supabase IPv4 add-on).
Use the shared pooler's **session mode** on port `5432` when the host is
IPv4-only. Do not use transaction mode on port `6543` for this persistent
Django deployment; transaction mode does not support prepared statements and
needs different connection-lifetime behavior.

The Dashboard's **Connect** panel provides the exact host. With a direct
connection the user is `plantapdo_runtime`; with the shared session pooler it
is normally `plantapdo_runtime.<project-ref>`. This repository accepts either
form but verifies that the underlying role is exactly `plantapdo_runtime`.
Supabase documents the endpoint trade-offs in [Connect to your database](https://supabase.com/docs/guides/database/connecting-to-postgres).

## 4. Configure the runtime workload

Use the following shape, with secrets injected rather than committed:

```dotenv
DJANGO_ENVIRONMENT=production
DATABASE_ROLE=runtime
POSTGRES_DB=postgres
POSTGRES_SCHEMA=plantapdo
POSTGRES_HOST=db.<project-ref>.supabase.co
POSTGRES_PORT=5432
POSTGRES_USER=plantapdo_runtime
POSTGRES_PASSWORD=<runtime-role-password>
POSTGRES_SSLMODE=verify-full
POSTGRES_SSLROOTCERT=/run/secrets/supabase-ca.crt
POSTGRES_CONN_MAX_AGE=60
DB_TENANT_CONTEXT_KEY=<same-128-character-hex-key-provisioned-in-postgres>
```

The configured search path contains only `plantapdo`. It deliberately has no
`public` fallback: a missing bootstrap must stop the deployment instead of
placing Django tables in Supabase's default Data API schema. The readiness
probe also verifies the current schema, runtime database role, signed tenant
context, and RLS state.

## 5. Run migrations with the DDL role

Create a one-off release job with the same host, schema, CA certificate, and
network path, but supply only these role-specific values:

```dotenv
DATABASE_ROLE=migration
POSTGRES_USER=plantapdo_migrator
POSTGRES_PASSWORD=<migrator-role-password>
```

For a session-pooler endpoint, append `.<project-ref>` to the username. Then:

```bash
python manage.py check --deploy
python manage.py migrate --noinput
python manage.py check --deploy
```

Migration `0008_enable_tenant_rls` enables and creates the policies as part of
the release transaction. [`supabase/enable_rls.sql`](supabase/enable_rls.sql)
is the idempotent operator repair script; it is not an optional replacement for
the migration.

Run [`supabase/verify.sql`](supabase/verify.sql) in the SQL editor after the
first migration and whenever database permissions change. It verifies the RLS
policies, signing-key isolation, and role grants. Start/update the runtime
service only after migration, RLS enablement, and privilege verification pass.

Every authenticated HTTP request runs in one database transaction. After JWT
and server-side session validation, Django sets a transaction-local tenant UUID
and HMAC signature. RLS releases category, task, travel-time, time-session, and
repeat-rule rows only when `plantapdo_security.current_tenant_id()` validates
that signature. A stolen runtime database password alone can neither read task
rows without context nor forge another account's context. Authentication tables
remain outside RLS because login and password recovery must locate users before
an authenticated tenant exists; keep the runtime credential and database
network path restricted accordingly.

## 6. Release gates and operations

- Confirm the Supabase table editor shows Django tables only in `plantapdo`,
  never `public`.
- Confirm the Data API is disabled and that `anon`, `authenticated`, and
  `service_role` have no `USAGE` on `plantapdo`.
- Connect as `plantapdo_runtime` without the signed context and verify direct
  selects return no tenant content. Do not test with the table-owning migrator,
  which correctly bypasses non-forced RLS for migrations.
- Verify an API readiness request returns HTTP 200 using runtime credentials,
  and returns 503 if migration credentials are deliberately substituted.
- Monitor database connections and slow/erroring queries by the distinct role
  names. Rotate runtime and migrator passwords independently.
- Keep Redis: it remains required for multi-replica throttling, token
  revocation, and WebSocket delivery. Supabase PostgreSQL does not replace it.
- Do not run migrations from every application replica at startup.
