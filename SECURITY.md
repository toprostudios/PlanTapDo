# Security policy

## Reporting a vulnerability

Report suspected vulnerabilities privately to the repository maintainers through the hosting provider’s private vulnerability-reporting feature or another pre-arranged private channel. Do not include secrets or personal data in the report, and do not open a public issue before a fix is available.

Include the affected endpoint or component, reproduction steps, impact, and any suggested mitigation. Maintainers should acknowledge the report promptly, preserve evidence, assess affected versions, rotate exposed credentials where necessary, and coordinate disclosure after patched deployments are available.

## Supported version

Security fixes are applied to the current deployment branch. Older unmaintained deployments should upgrade rather than assume they receive backports.

## Deployment boundary

The secure configuration and tests in this repository are one layer of the system. Operators must also follow [backend/DEPLOYMENT.md](backend/DEPLOYMENT.md) for TLS, proxy trust, network isolation, secret storage, rate limiting, monitoring, backups, image scanning, and key rotation.

PlanTapDo's current data-protection boundary uses TLS with peer verification in transit and AWS KMS-backed service encryption at rest. Passwords are one-way Argon2id hashes and are never encrypted for later recovery. Task content is not application-layer encrypted, so a principal with authorized plaintext database access can read it; production database and backup access must therefore remain private, least-privilege, MFA-protected, and audited.
