# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately to the repository maintainers through the hosting provider’s private vulnerability-reporting feature or another pre-arranged private channel. Do not include secrets or personal data in the report, and do not open a public issue before a fix is available.

Include the affected endpoint or component, reproduction steps, impact, and any suggested mitigation. Maintainers should acknowledge the report promptly, preserve evidence, assess affected versions, rotate exposed credentials where necessary, and coordinate disclosure after patched deployments are available.

## Supported version

Security fixes are applied to the current deployment branch. Older unmaintained deployments should upgrade rather than assume they receive backports.

## Current v1 boundary

The shipping v1 app is local-only: it has no reachable account, cloud-sync, or
server-hosted task-data flow. Planner state is stored in Application Support
with complete file protection and excluded from device backups. Advanced
purchase entitlements are checked locally through StoreKit. See
[PROJECT_STATUS.md](PROJECT_STATUS.md) for the current release gates.

## Future backend boundary

The backend security material applies only if the future cloud-sync prototype
is deployed. Operators must then follow [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md)
for TLS, proxy trust, network isolation, secret storage, rate limiting,
monitoring, backups, image scanning, and key rotation. Its Supabase/RLS, MFA,
and server-side data protections do not describe the shipping v1 app.
