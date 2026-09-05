# PlanTapDo future backend security review

Review date: 2026-08-28

> Scope note: this is a historical review of the retained future cloud-sync
> prototype. It is not a v1 App Store release certification. The shipping v1
> app is local-only; see [PROJECT_STATUS.md](PROJECT_STATUS.md) for its current
> implementation state and remaining submission gates.

## Executive assessment

The future backend prototype is a **production candidate**, not a production certification.
No critical or unresolved high-severity code vulnerability was found in the
reviewed application. The strongest existing controls are fail-closed
production settings, short-lived/revocable JWTs, Argon2id password hashing,
per-account ORM filtering, validated foreign-key ownership, bounded write
payloads, authenticated WebSockets, complete iOS file protection, device-only
Keychain storage, hashed Python dependency locks, and a non-root/read-only
container design.

The database design is now ready for a new Supabase project, but production is
blocked until the bootstrap and verification SQL have actually passed against
that project and the operational controls below are enabled. A source review
cannot verify a provider dashboard, IAM policy, WAF, backup, restore, alert, or
network rule that does not yet exist.

## Severity summary

| Severity | Open | Addressed in this review |
| --- | ---: | ---: |
| Critical | 0 | 0 |
| High | 0 | 2 |
| Medium | 0 | 11 |
| Low | 0 | 4 |

## Addressed findings

### H-01: Django tables could have entered Supabase's exposed `public` schema

The previous PostgreSQL configuration had no schema boundary. Django normally
uses the connection's default `public` schema; existing Supabase projects can
automatically grant Data API roles access to new public objects. Application
ownership checks do not protect a second database API that bypasses Django.

Resolution: production requires a non-reserved `POSTGRES_SCHEMA`, uses only
that schema in `search_path`, and has no `public` fallback. The Supabase kit
creates `plantapdo`, revokes `anon`/`authenticated`/`service_role` access, and
recommends disabling the unused Data API. See
[`backend/SUPABASE.md`](backend/SUPABASE.md) and
[`backend/supabase/bootstrap.sql`](backend/supabase/bootstrap.sql).

### H-02: The API could have run with database-owner credentials

The old settings accepted any non-empty PostgreSQL user, including Supabase's
`postgres` project owner. Compromise of an API container would then become a
database-administration compromise.

Resolution: the long-running service now fails unless it uses
`plantapdo_runtime`; migrations require the separate `plantapdo_migrator` role.
Readiness verifies the current schema and role. The runtime role has DML but no
DDL access, and the API never receives the migrator password.

### M-01: Redis TLS validation was documented but not enforced

A `rediss://` scheme alone did not ensure the configured query options required
certificate and hostname validation.

Resolution: production refuses to start unless `REDIS_URL` explicitly contains
`ssl_cert_reqs=required&ssl_check_hostname=true`.

### M-02: Release API URL validation was too permissive

The iOS client required HTTPS in Release but would accept an HTTPS URL with
userinfo, a query/fragment, or an unexpected path. That made a bad build-time
configuration easier to overlook.

Resolution: Release accepts only credential-free HTTPS URLs whose path is
exactly `/api`; Debug HTTP is restricted to loopback hosts.

### M-03: Tokens remained available after first device unlock

The Keychain used `AfterFirstUnlockThisDeviceOnly`, although PlanTapDo has no
background-sync requirement.

Resolution: tokens now use `WhenUnlockedThisDeviceOnly`, so they remain
device-bound and unavailable while the device is locked.

### L-01: Dependency and configuration gates needed Supabase coverage

Resolution: production-setting tests cover private-schema, runtime-role, and
Redis TLS failures. Deployment documentation and the ECS template now use the
Supabase session pooler, project CA, distinct secrets, and a post-migration
privilege check.

### M-04: Account lifecycle was incomplete

Resolution: registration now requires a one-time emailed verification code;
password reset uses a separately scoped one-time code and revokes all sessions.
Authenticator-app TOTP MFA includes one-time recovery codes, with encrypted
TOTP secrets and one-way-hashed recovery codes. Device sessions are listed and
can be revoked individually or all at once. Authenticated users can permanently
delete their account and all related task data in-app after password and, when
enabled, MFA verification. Production fails closed without a TLS SMTP provider
and independent MFA encryption key.

### M-05: Logout was best-effort when the device was offline

Resolution: every access/refresh pair now belongs to a server-side device
session and contains the account session generation. Logout revokes that
session, while revoke-all increments the generation and revokes every device.
The iOS client immediately removes active credentials but retains a separate
device-only Keychain revocation record and retries the idempotent refresh-token
revocation endpoint on later launches until the server confirms it.

### M-06: A runtime database credential could read every tenant's task data

Resolution: Supabase row-level policies now protect every task-content table.
After JWT and device-session validation, Django signs a transaction-local
tenant UUID with an independent 64-byte key. A locked security-definer function
validates the HMAC before RLS releases rows. The runtime role cannot read the
database copy of the key, so possession of only its database password cannot
forge another tenant. Readiness fails unless the signing key and all five RLS
tables are active.

Authentication tables necessarily remain readable to the Django runtime role
so credentials can be checked before a tenant exists. They contain Argon2id
password hashes and encrypted MFA secrets, not task bodies. Network isolation,
credential rotation, and audited operator access remain required.

### M-07: Read endpoints and account storage had no quotas

Resolution: atomic per-account quotas now bound categories, todos, travel-time
records, time sessions, repeat rules, and active device sessions. Both
individual writes and full-sync uploads enforce the same limits while holding
an account lock, and full-sync responses refuse legacy over-limit accounts
instead of materializing an unbounded payload. This preserves the iOS array
contract while establishing a finite response-size ceiling.

Edge rate limits are still required because application quotas/throttles are not
a volumetric DDoS boundary.

### L-02: Registration revealed whether identifiers were already used

Resolution: case-insensitive username and email conflicts now return the same
HTTP 202 status and generic body as an accepted registration. Verification and
password-reset requests also use generic responses, and code endpoints are
scoped/throttled. SMTP timing remains an operational side channel, so use an
asynchronous transactional provider/edge rate controls for high-risk launches.

### L-03: Local task content could enter device backups

Resolution: the state file already used complete file protection; its
application-support directory is now also explicitly excluded from iCloud and
Finder backups. Cloud bearer tokens and pending logout records remain
`WhenUnlockedThisDeviceOnly` Keychain items and never migrate through backup.

### M-08: A server refresh could overwrite pending local changes

Resolution: cloud workspaces now persist an unsynchronized-state marker and
deletion tombstones. The client uploads pending categories, tasks, timer
sessions, travel times, and deletions before accepting the returned canonical
state. Timer sessions use stable client-generated UUIDs, and the sync endpoint
validates ownership for both session upserts and deletions. A stale download is
discarded if the local mutation generation changes while it is in flight.

### M-09: Account lifecycle edge cases weakened identity verification

Resolution: registration now validates the entire request before checking for
identifier conflicts, so a weak password cannot distinguish an existing
account by producing a different status. The generic email-code confirmation
path performs equivalent password-hash work for missing accounts to reduce its
timing signal. A verified profile can no longer replace its email address until
a dedicated re-verification flow exists.

### M-10: Authentication failures could leave stale client sessions active

Resolution: a WebSocket closes if its periodic revocation/cache check errors
instead of silently losing the authentication monitor. The iOS refresh path
also compares the session it started with before saving rotated credentials, so
a late network response cannot restore credentials after logout or an account
switch.

### M-11: Local recovery and notification scheduling needed stronger bounds

Resolution: every successful protected state write now maintains a protected
backup, and launch falls back to it if the primary JSON is damaged. Local
notification updates are generation-checked to prevent stale asynchronous work
from restoring deleted reminders, tolerate duplicate category identifiers, and
select the nearest 64 reminders to respect iOS's pending-notification limit.

### L-04: Client/server validation and purchase presentation were incomplete

Resolution: notification preferences and lead times now use a shared bounded
format, duplicate subtask identifiers are rejected, and unknown local values
decode safely to off. The Advanced UI displays StoreKit's localized live price
and disables unavailable products instead of presenting hard-coded prices.

## Accepted product boundary

PlanTapDo is not end-to-end encrypted. The API must process task content, and
authorized application/database operators or a compromised API principal can
read plaintext. Supabase encryption at rest, RLS, restricted operator access,
and encrypted provider backups reduce that risk but do not change the product
claim. Do not market the product as end-to-end encrypted without a separate
client-side encryption design and feature-impact review.

## Production deployment gates

- Run the Supabase bootstrap, set interactive role passwords, migrate with the
  migrator role, and pass `verify.sql`.
- Disable the Supabase Data API, enforce PostgreSQL SSL, install the project CA,
  and restrict database networks to the application/migration egress path.
- Store runtime and migration database passwords separately; the service must
  never receive the migration or Supabase project-owner password.
- Deploy authenticated TLS Redis with certificate/hostname verification.
- Put Django behind an HTTPS proxy/WAF with body, request, login, registration,
  and WebSocket connection limits; verify trusted proxy header rewriting.
- Enable MFA for Supabase and hosting administrators, least-privilege IAM,
  audit logs, secret rotation, alerts, backups/PITR, and tested restores.
- Provision transactional SMTP, the MFA key, and the signed RLS tenant key;
  exercise email verification, reset, MFA recovery, offline logout retry, and
  revoke-all against staging before general availability.

## Verification performed

- Django API and production-configuration tests: 60 passed.
- iOS unit tests: 21 passed on a connected physical iPhone.
- Django migration drift check: no changes detected.
- Django production `check --deploy`: no issues with a representative
  fail-closed configuration.
- Bandit application scan: no findings after excluding test/migration code.
- `pip-audit` against the hashed lockfile: no known vulnerabilities reported on
  the review date.
- Unsigned generic iPhoneOS Debug and Release builds: succeeded.
- Secret-pattern/current tracked-file review: no committed production
  credential or private-key material found.
