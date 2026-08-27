# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately to the repository maintainers through the hosting provider’s private vulnerability-reporting feature or another pre-arranged private channel. Do not include secrets or personal data in the report, and do not open a public issue before a fix is available.

Include the affected endpoint or component, reproduction steps, impact, and any suggested mitigation. Maintainers should acknowledge the report promptly, preserve evidence, assess affected versions, rotate exposed credentials where necessary, and coordinate disclosure after patched deployments are available.

## Supported version

Security fixes are applied to the current deployment branch. Older unmaintained deployments should upgrade rather than assume they receive backports.

## Deployment boundary

The secure configuration and tests in this repository are one layer of the system. Operators must also follow [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md) for TLS, proxy trust, network isolation, secret storage, rate limiting, monitoring, backups, image scanning, and key rotation.

PlanTapDo's current data-protection boundary uses TLS with certificate and hostname verification in transit, Supabase-managed PostgreSQL encryption at rest, signed per-request tenant context with PostgreSQL RLS, and the deployment provider's encrypted secret/Redis storage. Django data lives in a non-exposed `plantapdo` schema accessed through separate migration and runtime roles; Supabase's Data API is not part of the application and should be disabled. Passwords and MFA recovery codes are one-way Argon2id hashes; TOTP secrets use a separate application encryption key. The iOS state directory is completely file-protected and excluded from device backups. Task content is not end-to-end encrypted, so a principal with authorized plaintext application access can read it; production database, dashboard, backup, and secret access must therefore remain least-privilege, MFA-protected, and audited. See [backend/SUPABASE.md](backend/SUPABASE.md).
