# aws-deploy

## Application service

The FastAPI service in `app/` provides:

- `GET /health` — returns HTTP 200 with `{"status": "ok"}`.
- `GET /version` — returns HTTP 200 with the application version and Git commit supplied when the Docker image is built.

Build the image from the repository root, providing both the application version and full source commit:

```sh
docker build -f app/Dockerfile \
  --build-arg APP_VERSION="$(git rev-parse HEAD)" \
  --build-arg GIT_COMMIT="$(git rev-parse HEAD)" \
  -t aws-deploy-app:local app
```

CI can pass its Git tag as `APP_VERSION` for release images or the commit SHA for other builds. `GIT_COMMIT` should always be the full SHA for the exact source revision. The image exposes both values at `/version` and records them in the `org.internal.image.version` and `org.internal.image.revision` labels.

Run the app locally from `app/` with `python -m pip install -r requirements.txt && APP_VERSION=dev GIT_COMMIT="$(git -C .. rev-parse HEAD)" python -m uvicorn src.main:app --host 0.0.0.0 --port 8000`. Run tests from `app/` with `python -m pip install -r requirements-dev.txt && python -m pytest`.

## Continuous integration

The repository separates application and infrastructure pipelines. App CI
runs for pull requests that change `app/`; infrastructure CI runs for pull
requests that change `infra/`. Both also support manual dispatch.

**App CI** lints Python with Ruff, builds a Docker image, and runs that image
locally to check that `/health` returns HTTP 200. It audits Python dependencies
with `pip-audit` and scans the application filesystem for secrets and
misconfiguration with Trivy. This is not a Trivy scan of the built container
image. ECR image scanning is enabled on push, but the workflow does not
currently wait for or gate publishing on ECR scan findings. A blocking
container-image scan before publishing is a possible future improvement.

**Infrastructure CI** checks Terraform formatting, initializes and validates
the development configuration, scans Terraform configuration with Trivy, and
creates a Terraform plan. It does not apply changes. The plan supports review
before any future apply process, but no Terraform apply workflow currently
exists.

The plan job assumes the externally configured `AWS_INFRA_ROLE` through GitHub
OIDC. It also uses the `AWS_REGION` repository variable and `DOMAIN_NAME`
secret. The role needs access to the S3 state and lock file and to resources
Terraform reads. There is no explicit fork-PR guard in the workflow; its OIDC
trust policy and permissions must be configured carefully before untrusted
pull requests are allowed to run it.

## Image release and current deployment boundary

On pushes to `main` that change `app/`, the CD workflow uses semantic-release
to calculate a version from commit history. If a release is due, it builds the
image, smoke-tests `/health` in the local container, creates the GitHub
release, then pushes the image to ECR. It tags the image with both the
semantic version and `sha-<full-commit-sha>`. The version is readable as a
release label; the SHA precisely identifies the source commit. ECR tags are
immutable, and ECR image scanning on push is enabled.

This workflow publishes an image; it does **not** update the ECS service or
run a post-deployment health check. The local smoke test happens before the
push. ECS uses the ALB target group's `/health` check for task health, but the
Terraform configuration does not enable the ECS deployment circuit breaker
or automatic rollback. An ECS deployment, post-deployment verification, and
rollback strategy remain future work. ECR stores images; it is not the
deployment or rollback controller.

The CD workflow uses the external `AWS_DEPLOY_ROLE` via GitHub OIDC and
currently logs in to ECR and pushes images. Keep it separate from
`AWS_INFRA_ROLE`; the application workflow should not receive infrastructure
permissions. The role trust policy is configured outside this repository and
should restrict assumption to this repository and the intended branch or
GitHub Environment. Do not store long-lived AWS access keys in GitHub.

## Troubleshooting exercise: release completed, ALB targets unhealthy

Consider a release scenario in which GitHub reports success, ECS tasks appear
to be running, but customers receive HTTP 503 responses and the ALB target
group marks the targets unhealthy. A running ECS task only confirms that the
task's processes have started; it does not prove that the application is ready
or passing the ALB health check. If the ALB has no healthy targets, it cannot
forward requests and may return 503.

One important qualification for this repository: its CD workflow currently
builds, smoke-tests, and pushes an image to ECR; it does not update ECS. A
green CD run therefore confirms image publication, not a production
deployment. The investigation below applies if ECS was updated by a separate
mechanism or after an ECS deployment workflow is added.

### Investigation order

1. **Establish the timeline and exact version.** Check the GitHub Actions run,
   commit SHA, semantic release version, ECR image tags, and ECS task
   definition revision. The image's `/version` endpoint and
   `org.internal.image.revision` label can confirm the source SHA. Compare
   when tasks changed, target health started failing, and customer 503s began.
2. **Start with ALB target health.** In EC2 Target Groups, inspect registered
   targets, each target's health state and reason, and the configured
   protocol, port, path, matcher, interval, and timeout. The current Terraform
   expects HTTP on port `8000`, path `/health`, with `200-399` accepted every
   30 seconds. Check whether all targets fail or only some.
3. **Inspect the ECS service and task.** Check the deployment events, task
   definition revision, desired and running counts, container exit details,
   and CPU/memory graphs. `RUNNING` is not equivalent to passing an ALB health
   check.
4. **Inspect logs and metrics around the failure.** Review the ECS container
   log group `/aws/ecs/<tier>-<product>-ecs-service`. Check the CloudWatch
   dashboard's CPU utilization, memory utilization, and running task count.
   For ALB context, inspect CloudWatch `HealthyHostCount`,
   `UnHealthyHostCount`, `HTTPCode_ELB_5XX_Count`,
   `HTTPCode_Target_5XX_Count`, and `TargetResponseTime` for the relevant load
   balancer and target group. The latter ALB metrics are useful investigation
   signals but are not currently included in the Terraform dashboard.

### Likely causes and how to test them

1. **Health-check or target configuration mismatch.** The new task might
   listen on a different port or interface, the target group might use the
   wrong port/path, or the task security group might no longer allow traffic
   from the ALB security group. Compare the ALB listener, target group, ECS
   container mapping, and service security groups. Use the target group's
   unhealthy reason: a response-code mismatch suggests the path/application
   response; a timeout suggests reachability or a stalled process. Confirm the
   application listens on `0.0.0.0:8000` and `/health` returns 200. The current
   app does both, and the task security group permits port 8000 from the ALB
   security group. If those settings match the deployed revision and the
   registered target responds successfully, this cause is less likely.
2. **Application regression or resource pressure.** A release can start a
   process that remains alive while initialization is stuck, the handler
   errors, or responses time out. Look for startup exceptions and health
   request failures in ECS logs, and correlate them with CPU, memory, target
   response time, and task-count changes. The current alarms cover CPU and
   memory above 70% for two consecutive one-minute periods; they have no
   notification actions configured. Normal resource graphs and successful
   health responses from the deployed image make resource pressure or an
   application regression less likely.
3. **Dependency or configuration failure.** An application can be running but
   unable to serve requests because a required dependency, configuration value,
   or credential is missing or unreachable. Search the task logs for
   connection timeouts, authentication failures, DNS errors, or missing
   configuration, then check the specific dependency's health and network
   path. This repository's current app does not define a database dependency,
   so treat a database issue as a generic possibility only if one is added;
   do not assume one exists in this architecture. If there are no dependency
   errors and the service does not rely on an unavailable external dependency,
   eliminate this cause.

### Recovery and prevention

If failures began with a release and the previous image is known to be healthy,
the safest recovery is to restore the previous known-good, explicitly tagged
image through the authorized ECS deployment path, then verify target health
and `/health`. Avoid changing production resources ad hoc in the console
unless emergency procedures require it; reconcile any emergency change back
into the source of truth. This repository does not yet provide an ECS
deployment or rollback command, so that recovery path must be established
before claiming rollback is automated. ECS deployment circuit-breaker
rollback is also not configured in Terraform.

To prevent recurrence, add a controlled deployment path that promotes the
same immutable image through development and staging before production, runs
health checks after each deployment, and gates production with an authorized
GitHub Environment. Configure ECS deployment circuit-breaker rollback,
require CI checks and reviews before merge, and notify responders from
CloudWatch alarms. A successful workflow should mean that the deployed
application passed runtime health checks—not merely that an image was pushed
to ECR.

## Repository and production security

The security boundary is layered: GitHub controls who may change and approve
workflow source, while AWS IAM controls which GitHub workload may assume each
role and what that role can do. OIDC provides short-lived credentials, but it
does not by itself make an overly broad trust policy or IAM policy safe.

### What currently prevents a developer or compromised workflow from deploying arbitrary changes to production?

There is no production deployment path in this repository today: the
application workflow pushes images to ECR but does not deploy them to ECS, and
there is no Terraform apply workflow. The current controls therefore do not
amount to a production approval gate.

The active `main` ruleset requires a pull request and blocks branch deletion
and force-pushes, but it requires zero approvals and no CI status checks. The
repository is public, and no CODEOWNERS file or protected GitHub deployment
environment is configured. Consequently, do not rely on human approval,
CODEOWNERS, or environment approvals as controls that are already enforced.

For a future production path, protect the source branch with required reviews
and CI checks, require CODEOWNERS review for `.github/` and `infra/`, and gate
production with a GitHub Environment that has designated reviewers. Restrict
the AWS OIDC trust policy to this repository and the protected branch or
environment, and limit each role's permissions to its task. These GitHub and
AWS controls complement each other: GitHub limits who can change or approve a
workflow; AWS limits which workflow identity can obtain credentials and what
those credentials can do.

Current repository settings and files:

- The repository is currently **public**.
- An active ruleset on `main` requires pull requests and blocks branch
  deletion and non-fast-forward updates. It allows squash and rebase merges.
- The ruleset currently requires **zero approving reviews** and does not
  require status checks. Although CI workflows run, passing them is not
  currently enforced by this ruleset before merge.
- No `CODEOWNERS` file or GitHub deployment environments are configured in
  this repository. There is no configured staging/production promotion gate.
- GitHub Actions currently allows all actions and does not enforce full-SHA
  pinning in repository settings, although the workflows pin many actions to
  commit SHAs.

Therefore, do not treat required human review, CODEOWNERS review, protected
production environments, or a private repository as controls already in
force. They are recommended hardening steps: restrict repository access and
visibility as appropriate, require approvals and CI status checks for `main`,
add CODEOWNERS for workflows and Terraform, restrict allowed/pinned actions,
and protect production with an environment approval. The actual required
review count and approvers should be taken from GitHub settings after those
controls are configured.

To reduce the blast radius of a compromised workflow, scope each OIDC trust
policy to this repository and the intended ref or protected GitHub Environment,
and grant only the AWS actions and resources needed by that workflow. The
Terraform role is the most sensitive role if it is ever granted apply
permissions, because it could change or destroy managed infrastructure. The
current infrastructure workflow only plans. A compromised application
workflow should not inherit Terraform permissions; the current app role is
used by the CD workflow for ECR publishing, not ECS deployment.

The Terraform configuration does not integrate application secrets with
Secrets Manager or SSM. The configured environment-variable map is plaintext
configuration and must not contain secrets. Add a managed secret integration
before supplying application secrets; never put secrets in source, Dockerfiles,
or checked-in tfvars.

The intended future promotion path is `main` → development → staging →
production, with health verification and authorized approval at each relevant
environment boundary. Currently, a release from `main` is built and published
to ECR only; there is no implemented ECS deployment or staging/production
promotion. Source-code contribution, infrastructure modification, image
publishing, and production promotion should remain separate authorization
boundaries as the pipeline grows.

For the Terraform architecture, state, and operational details, see
[infra/README.md](infra/README.md).
