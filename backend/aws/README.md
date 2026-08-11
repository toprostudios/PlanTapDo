# AWS deployment: PlanTapDo API

This directory prepares the API for a managed AWS deployment. Use **ECS on Fargate** rather than an internet-facing EC2 instance. The production topology is:

```text
Internet → Route 53 → ACM certificate → Application Load Balancer → ECS/Fargate (2+ tasks)
                                                            ├── RDS Proxy → PostgreSQL (private)
                                                            └── ElastiCache Redis TLS (private)
```

The ALB is the only public component. Fargate tasks, RDS, and Redis belong in private subnets across at least two Availability Zones. The API image is stored in ECR and task logs go to CloudWatch Logs.

## Before deployment

Create these AWS resources, all in one region:

1. A VPC with two public subnets for the ALB and two private subnets for ECS, RDS, and Redis. Give private ECS subnets NAT egress so tasks can pull from ECR, write logs, and send telemetry.
2. An ACM certificate for `api.your-domain.example`, validated in Route 53, and a public Application Load Balancer with an HTTPS listener. Redirect HTTP (80) to HTTPS (443).
3. An RDS PostgreSQL instance or Multi-AZ cluster with KMS storage encryption, automated backups, deletion protection, TLS required, and a private subnet group. Create the `plantapdo` database and a least-privilege `plantapdo` database user. Put an RDS Proxy in front of it, require TLS on the proxy, and use the proxy endpoint as `POSTGRES_HOST`; this lets the standard container CA bundle verify the endpoint certificate with `sslmode=verify-full`.
4. A TLS-enabled ElastiCache Redis deployment with KMS encryption at rest, in-transit encryption, and an ACL authentication token. It must be private and its endpoint must be expressed as `rediss://default:PASSWORD@HOST:PORT/0?ssl_cert_reqs=required`.
5. An ECR repository named `plantapdo-api`, an ECS cluster, a CloudWatch log group named `/ecs/plantapdo-api` (30+ day retention), and an ECS service.

Security groups must permit only these flows:

| Source | Destination | Port |
| --- | --- | --- |
| Internet | ALB | 443 |
| ALB security group | ECS task security group | 8000 |
| ECS task security group | RDS security group | 5432 |
| ECS task security group | Redis security group | Redis endpoint port |

Do not assign public IPs to ECS tasks and do not allow database or Redis ingress from the internet.

## Secrets and IAM

Store one JSON secret in AWS Secrets Manager. Its keys must be:

```json
{
  "DJANGO_SECRET_KEY": "at-least-64-random-characters",
  "JWT_SIGNING_KEY": "a-different-at-least-64-random-characters",
  "POSTGRES_PASSWORD": "the-database-password",
  "REDIS_URL": "rediss://default:redis-password@redis-host:6379/0?ssl_cert_reqs=required",
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

Set the image URI, region, public API hostname, RDS Proxy endpoint, secret ARN, task roles, and release SHA in `task-definition.template.json`. Validate that no `REPLACE_WITH_` value remains, then register it:

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

Run migrations as a one-off ECS task using the **same task definition, private subnets, security group, and secret injection** as the service, overriding its command with:

```text
python manage.py migrate --noinput
```

Wait for that task to succeed before updating the ECS service. Do not run migrations from every web task at startup.

Then deploy the registered revision and wait until the service is stable:

```bash
aws ecs update-service --cluster plantapdo-production --service plantapdo-api \
  --task-definition plantapdo-api:REVISION --force-new-deployment
aws ecs wait services-stable --cluster plantapdo-production --services plantapdo-api
```

Verify `https://api.your-domain.example/health/live/` and `/health/ready/` return 200, inspect the CloudWatch logs, and exercise login, sync, and WebSocket updates on a physical device. A failed deployment should roll back automatically; investigate the ECS service events and target-group health before retrying.

## Operations checklist

- Schedule `python manage.py flushexpiredtokens` daily as an ECS scheduled task using the same security configuration.
- Enable RDS automated backups, point-in-time recovery, maintenance notifications, and restore testing.
- Alert on ALB 5xx, ECS task restarts, RDS capacity/connections, Redis memory/evictions, and application 401/403/429/5xx rates.
- Rotate Secrets Manager values deliberately. ECS-injected secrets do not refresh in running tasks; deploy a new task revision after rotation.
- Keep images immutable, scan them before release, and retain a known-good previous task definition for rollback.
- Enable CloudTrail, GuardDuty, Security Hub, AWS Config, ECR enhanced scanning, and alarms for Secrets Manager/KMS policy changes. Encrypt CloudWatch Logs with KMS and restrict log access because operational metadata can still be sensitive.
- Test that PostgreSQL reports an encrypted connection and that hostname verification fails when given a mismatched endpoint. Verify Redis connections reject an untrusted certificate.
