# AWS deployment: PlanTapDo API

This directory prepares the API for a managed AWS deployment. Use **ECS on Fargate** rather than an internet-facing EC2 instance. The production topology is:

```text
Internet → Route 53 → ACM certificate → Application Load Balancer → ECS/Fargate (2+ tasks)
                                                            ├── NAT → Supabase PostgreSQL
                                                            └── ElastiCache Redis TLS (private)
```

The ALB is the only component with direct public ingress. Fargate tasks and Redis belong in private subnets across at least two Availability Zones; controlled NAT egress reaches Supabase. Restrict Supabase database access to the NAT gateways' fixed public addresses. The API image is stored in ECR and task logs go to CloudWatch Logs.

## Before deployment

Create these AWS resources, all in one region:

1. A VPC with two public subnets for the ALB/NAT gateways and two private subnets for ECS and Redis. Give each NAT gateway a stable Elastic IP; tasks need controlled egress for Supabase, ECR, logs, and telemetry.
2. An ACM certificate for `api.your-domain.example`, validated in Route 53, and a public Application Load Balancer with an HTTPS listener. Redirect HTTP (80) to HTTPS (443).
3. A hardened Supabase project bootstrapped according to [`../SUPABASE.md`](../SUPABASE.md). Use the shared pooler's session-mode endpoint on port 5432 for IPv4 ECS tasks, allowlist only the NAT Elastic IPs, enable database SSL enforcement, disable the unused Data API, and enable the required backup/PITR tier. Download the Supabase CA to `backend/certs/supabase-ca.crt` in the protected CI build context.
4. A TLS-enabled ElastiCache Redis deployment with KMS encryption at rest, in-transit encryption, and an ACL authentication token. It must be private and its endpoint must be expressed as `rediss://default:PASSWORD@HOST:PORT/0?ssl_cert_reqs=required&ssl_check_hostname=true`.
5. An ECR repository named `plantapdo-api`, an ECS cluster, a CloudWatch log group named `/ecs/plantapdo-api` (30+ day retention), and an ECS service.

Security groups must permit only these flows:

| Source | Destination | Port |
| --- | --- | --- |
| Internet | ALB | 443 |
| ALB security group | ECS task security group | 8000 |
| ECS task through controlled NAT | Supabase session pooler | 5432 |
| ECS task security group | Redis security group | Redis endpoint port |

Do not assign public IPs to ECS tasks. Keep Redis private and do not leave Supabase database ingress open to arbitrary addresses.

## Secrets and IAM

Store one JSON secret in AWS Secrets Manager. Its keys must be:

```json
{
  "DJANGO_SECRET_KEY": "at-least-64-random-characters",
  "JWT_SIGNING_KEY": "a-different-at-least-64-random-characters",
  "DB_TENANT_CONTEXT_KEY": "the-same-128-character-hex-key-provisioned-in-supabase",
  "MFA_ENCRYPTION_KEY": "an-independent-fernet-key",
  "POSTGRES_RUNTIME_PASSWORD": "the-runtime-role-password",
  "POSTGRES_MIGRATOR_PASSWORD": "the-separate-migration-role-password",
  "REDIS_URL": "rediss://default:redis-password@redis-host:6379/0?ssl_cert_reqs=required&ssl_check_hostname=true",
  "EMAIL_HOST_USER": "transactional-mail-user",
  "EMAIL_HOST_PASSWORD": "transactional-mail-password",
  "SENTRY_DSN": ""
}
```

Use a customer-managed KMS key appropriate for production secrets and enable automatic rotation. The **task execution role** needs `secretsmanager:GetSecretValue` for this secret, `kms:Decrypt` only for that key, and permissions to write to the specified CloudWatch log group; it also needs the standard ECR image-pull permissions. Keep the **application task role** empty unless the application later needs an AWS API. Never put a secret, password, or DSN in task-definition `environment` values.

The Fargate platform version must support selecting JSON keys from Secrets Manager. The `:KEY::` suffix in the task template selects a key from the JSON secret.

## Build and publish the image

From the repository root, replace the capitalized values and use an immutable git SHA tag:

```bash
AWS_REGION=REPLACE_WITH_AWS_REGION
AWS_ACCOUNT_ID=REPLACE_WITH_AWS_ACCOUNT_ID
IMAGE_TAG=$(git rev-parse --short HEAD)

aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
docker build --platform linux/amd64 --tag "plantapdo-api:$IMAGE_TAG" backend
docker tag "plantapdo-api:$IMAGE_TAG" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/plantapdo-api:$IMAGE_TAG"
docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/plantapdo-api:$IMAGE_TAG"
```

Set the image URI, AWS/Supabase regions, Supabase project reference/session-pooler host, public API hostname, secret ARN, task roles, and release SHA in `task-definition.template.json`. Confirm the reviewed Supabase CA is present in the build context. Validate that no `REPLACE_WITH_` value remains, then register it:

```bash
aws ecs register-task-definition --cli-input-json file://backend/aws/task-definition.template.json
```

## Service and load balancer configuration

Create an ECS service with a desired count of **2**, deployment circuit breaker with rollback enabled, a 30-second health-check grace period, and the task private subnets/security group. Configure the ALB target group as:

| Setting | Value |
| --- | --- |
| Target type | `ip` |
| Protocol / port | HTTP / 8000 |
| Health check path | `/health/ready/` |
| Success code | `200` |
| Deregistration delay | 30 seconds |

Set `DJANGO_ALLOWED_HOSTS` to the exact public API hostname, not a URL. `DJANGO_TRUST_PROXY_SSL_HEADER=True` and `DJANGO_NUM_PROXIES=1` are required because the ALB terminates TLS and sends traffic to the task over HTTP. Configure the ALB idle timeout and WebSocket behavior to suit the client; preserve the `Authorization` header for `/ws/todos/`.

## Migrations and release

Run migrations as a one-off ECS task using the same image, private subnets, and security group as the service, but a separate task-definition revision that sets `DATABASE_ROLE=migration`, uses `plantapdo_migrator.<project-ref>`, and maps `POSTGRES_PASSWORD` from `POSTGRES_MIGRATOR_PASSWORD`. Never give the long-running service this secret. Override the migration task command with:

```text
python manage.py migrate --noinput
```

Migration `0008_enable_tenant_rls` creates the tenant policies automatically
and fails the release if the Supabase security bootstrap/key is missing. Run
`supabase/verify.sql` as the project owner after the task. Wait for both to
succeed before updating the ECS service. Do not run migrations from every web
task at startup.

Then deploy the registered revision and wait until the service is stable:

```bash
aws ecs update-service --cluster plantapdo-production --service plantapdo-api \
  --task-definition plantapdo-api:REVISION --force-new-deployment
aws ecs wait services-stable --cluster plantapdo-production --services plantapdo-api
```

Verify `https://api.your-domain.example/health/live/` and `/health/ready/` return 200, inspect the CloudWatch logs, and exercise login, sync, and WebSocket updates on a physical device. A failed deployment should roll back automatically; investigate the ECS service events and target-group health before retrying.

## Operations checklist

- Schedule `python manage.py flushexpiredtokens` daily as an ECS scheduled task using the same security configuration.
- Enable the appropriate Supabase backup/PITR tier, database/maintenance notifications, and restore testing.
- Alert on ALB 5xx, ECS task restarts, Supabase capacity/connections, Redis memory/evictions, and application 401/403/429/5xx rates.
- Rotate Secrets Manager values deliberately. ECS-injected secrets do not refresh in running tasks; deploy a new task revision after rotation.
- Keep images immutable, scan them before release, and retain a known-good previous task definition for rollback.
- Enable CloudTrail, GuardDuty, Security Hub, AWS Config, ECR enhanced scanning, and alarms for Secrets Manager/KMS policy changes. Encrypt CloudWatch Logs with KMS and restrict log access because operational metadata can still be sensitive.
- Test that PostgreSQL reports an encrypted connection and that hostname verification fails when given a mismatched endpoint. Verify Redis connections reject an untrusted certificate.
