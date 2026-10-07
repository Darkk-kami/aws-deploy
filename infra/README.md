# Infrastructure

## Architecture
<img width="5850" height="3810" alt="infra" src="https://github.com/user-attachments/assets/4bd3d7a2-7103-4b6f-9cfe-4256bba0d7b0" />

The application runs in AWS `eu-west-2` (London), selected for the target
users' latency among the standard AWS regions considered. The service is a
small container workload, so ECS with Fargate provides the required
orchestration without the additional Kubernetes control-plane and operational
complexity of EKS.

The request path distinguishes the public, encrypted connection from the
private, unencrypted connection inside the VPC:

```text
PUBLIC INTERNET
    -- HTTPS :443 (TLS encrypted) -->
INTERNET-FACING ALB (public subnets; TLS terminates here)
    -- HTTP :8000 (private VPC traffic; not TLS-encrypted) -->
ECS FARGATE TASK (private subnets; no public IP)
```

Only the client-to-ALB leg is HTTPS. The ALB terminates TLS with an existing
ACM certificate, then forwards requests as plain HTTP to the task on port
8000 over the VPC network. The task is in a private subnet, has no public IP,
and its security group accepts application traffic only from the ALB security
group. The target group checks `/health` every 30 seconds and considers HTTP
200-399 healthy. An HTTPS request for
`www.<domain>` is redirected to the configured non-`www` domain. There is no
port 80 listener, so this is not an HTTP-to-HTTPS redirect. The ACM certificate
must cover both hostnames if clients are expected to connect to both over
HTTPS, because TLS negotiation happens before the ALB can redirect.

The VPC CIDR is `10.10.0.0/16`. It has two public `/27` subnets for the ALB and
two private `/24` subnets for ECS tasks. The VPC module defaults to two
Availability Zones and assigns subnets round-robin across the first available
zones; the configuration does not pin specific zone names. The public route
table has a default route through an Internet Gateway. The private route table
has no general Internet/NAT route. ECS tasks do not receive public IP
addresses.

Private tasks reach the AWS services needed to pull images and send container
logs through ECR API, ECR DKR, and CloudWatch Logs interface endpoints and an
S3 gateway endpoint. The S3 endpoint is also needed because ECR image layers
are stored in S3. There is no NAT Gateway. This avoids a NAT Gateway's fixed
hourly cost for this workload, but interface endpoints also have costs; the
overall cost depends on endpoint count, Availability Zone placement, and
traffic.

Security groups allow public HTTPS ingress to the ALB, ALB-to-task traffic on
the application port, and task egress to the configured endpoints and S3
prefix list. Tasks are not directly reachable from the Internet. The task
definition uses Fargate with 256 CPU units and 512 MiB memory, `X86_64`
architecture, a read-only root filesystem, a non-root UID/GID (`10001`), and
dropped Linux capabilities.

ECR image tags are immutable, images are scanned on push, and the lifecycle
policy retains the three most recent images. ECR uses AES256 encryption at
rest. An ECS execution role is created for image pulls and log delivery. The
ALB access, connection, and health-check
log delivery sources are connected to CloudWatch Logs destinations in the
module's log group, with a resource policy granting the delivery service
write access. The ECS execution role's log permissions are scoped to the
configured `/aws/ecs/<tier>-<product>-ecs-service` log group. These settings
are provisioned when Terraform is applied; the infrastructure workflow in
this repository currently plans but does not apply them. The GitHub Actions
IAM roles are not created by this Terraform configuration: the infrastructure
workflow assumes an externally configured role using GitHub OIDC.

CloudWatch has two separate ECS service alarms. Each alarm triggers when its
own average metric (CPU or memory utilization) exceeds 70% for two consecutive
one-minute periods. One dashboard contains CPU, memory, and running-task-count
widgets.


## Alternative Architecture Considered

CloudFront with a VPC Origin and an internal ALB is a valid alternative. It
could add edge caching, geographic controls, WAF integration, and remove the
ALB's direct public reachability, but would add services and configuration not
needed for this small workload.

## Repository structure and modularity

```text
infra/
├── config-dev/       # Development root module: backend, provider, inputs, outputs
└── modules/
    ├── alb/          # Public ALB, HTTPS listener, target group, security group
    ├── cloudwatch/   # ECS alarms and the service dashboard
    ├── ecr/          # Image repository and lifecycle policy
    ├── ecs/          # Cluster, task/service, execution role, task security group
    └── vpc/          # VPC, subnets, route tables, Internet Gateway, endpoints
```

`config-dev` is the root module: it supplies environment values and composes
the child modules. Each child module groups one infrastructure responsibility
behind input variables and outputs. The root connects those interfaces: the
VPC supplies subnet and endpoint IDs; the ALB supplies its security group and
target group; ECR supplies the repository URL and ARN; ECS supplies its cluster
and service names to CloudWatch. This keeps the environment-specific wiring
separate from reusable resource definitions. A production root module does not
currently exist.

The checked-in `terraform.tfvars` contains placeholders for the domain and
image tag. Replace these with the real domain and a tag available in ECR before
using the configuration to deploy. The ACM certificate is an external
prerequisite: Terraform looks up an already-issued certificate for the domain
in the configured region; it does not request or validate a certificate.

## Terraform CI

`.github/workflows/ci_infra.yml` runs on infrastructure pull requests and
manual dispatch. It checks Terraform formatting, initializes and validates
`config-dev` without a backend in the validation job, scans `infra/` with
Trivy, then initializes the S3 backend and creates a plan with a five-minute
lock timeout. It does not apply the plan or provision production. There is no
production root module or automated Terraform apply workflow in this
repository yet.

The plan job assumes the externally configured `AWS_INFRA_ROLE` repository
secret through GitHub OIDC. It also uses the `AWS_REGION` repository variable
and `DOMAIN_NAME` secret. The assumed role needs access to the state backend
and the AWS resources that Terraform reads.

## Terraform state and environments: Q&A

### Q1. How do I manage Terraform remote state without `AdministratorAccess`?

I use a dedicated IAM role with least-privilege permissions instead of
`AdministratorAccess`. In CI, GitHub Actions assumes the externally configured
`AWS_INFRA_ROLE` through GitHub OIDC, receiving temporary credentials rather
than relying on long-lived AWS access keys. The role is limited to the S3
backend bucket and state prefix it needs, including access to the S3 lock file,
and to the AWS resources Terraform must inspect for its plan. For deployments,
the role would also need the specific create, update, and delete permissions
required by the managed resources; this repository currently runs plans only
and does not implement Terraform apply.


### Q2. How do I prevent simultaneous Terraform runs from changing the same state?

I keep the Terraform configuration in one version-controlled repository as
the source of truth, and route changes through pull requests and a controlled
CI/CD workflow. This GitOps-style process gives changes a single reviewed
entry point instead of letting multiple administrators make independent
changes or run applies from their own machines. It reduces conflicting changes
and makes infrastructure changes reviewable and auditable.

The S3 backend lock file, enabled with `use_lockfile = true`, is a separate
technical safeguard: Terraform acquires it to prevent simultaneous operations
against the same state. The CI plan waits up to five minutes for the lock.
Repository controls reduce the chance of competing runs; the backend lock
protects the state if runs still overlap. This repository currently creates
plans only—the controlled apply workflow is not implemented yet.

### Q3. How do I keep development and production state separate?

I currently have only `config-dev`, with a development-specific bucket and
state key. I have not implemented production configuration yet. When adding
production, I intend to create a separate root directory such as `config-prod`
with its own backend state location and environment values, while reusing the
shared modules. That makes the environment boundary explicit and avoids
pointing a development plan at production state. Terraform workspaces are
another option, but they are not used here.

## Monitoring and operational response

The CloudWatch dashboard has three ECS service metrics:

- **CPU utilization** and **memory utilization** show resource pressure.
- **Running task count** shows how many tasks are actually running and helps
  identify availability or capacity changes.

The two CloudWatch alarms are separate: one alarms when average CPU
utilization exceeds 70%, and the other when average memory utilization exceeds
70%, each for two consecutive one-minute periods. The dashboard helps an
operator understand behavior over time; an alarm is intended to signal a
condition that needs investigation. Running task count is on the dashboard but
does not currently have its own alarm. No alarm actions or notification
destination are configured, so an alarm does not yet notify a responder.
Configure an appropriate on-call/platform recipient before relying on these
alarms operationally. The goal is to identify abnormal conditions before
customers have to report them.

For an initial investigation, check the dashboard to establish when CPU,
memory, or task count changed; compare that time with deployment activity;
then inspect the application logs for errors or repeated failures. Use these
signals to distinguish application problems, workload changes, insufficient
task resources, and infrastructure issues.

The ECS task uses the `awslogs` driver to send container output, including
application/server logs written to standard output and standard error, to
`/aws/ecs/<tier>-<product>-ecs-service` in CloudWatch Logs. ALB access,
connection, and health-check logs are delivered to the ALB module's CloudWatch
log group. The `config-dev/terraform.tfvars` currently sets
`log_retention_days = 1` for both groups. The reusable modules default this
input to 30 days when it is not supplied, but the dev root overrides that
default. Retention should be set to match the environment's troubleshooting,
security, compliance, and cost requirements; 30 days is not the current
development retention.

Terraform configures an ALB target-group health check on `/health`, and CI
smoke-tests the built image before it is pushed. The CD workflow does not
deploy to ECS or verify health after deployment. The ECS service has no
deployment circuit-breaker/rollback configuration, so automatic rollback
should not be claimed as implemented.
