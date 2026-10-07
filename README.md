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




## Troubleshooting Exercise

For the troubleshooting scenario, I would approach it by following the request path from the customer back through the infrastructure.

The scenario is that a new release has been deployed, GitHub Actions says the deployment was successful, ECS shows that the tasks are running, but customers are receiving HTTP 503 responses and the load balancer is reporting unhealthy targets.

The first thing I would clarify is that there is actually no contradiction between the ECS task being `RUNNING` and the ALB saying the target is `UNHEALTHY`.

ECS saying that the task is running basically tells me that the container has started and the task itself is alive. It does not necessarily mean that the application inside the container is healthy or that it is capable of responding to requests.

The ALB performs its own health check against the target. So I can have a container that is technically running, but the application inside it could be listening on the wrong port, returning an error from the health endpoint, taking too long to respond, or being unable to reach one of its dependencies.

So the first thing I would investigate is the **ALB target health**, because the ALB is already telling me that the targets are unhealthy.

### What I would investigate first

I would first confirm the deployment itself.

I would go to GitHub Actions and confirm:

* which commit was deployed
* which image/version was deployed
* when the deployment happened
* which environment was affected
* whether the deployment completed successfully

That gives me a timeline so I can correlate the deployment with when the 503 errors started.

After that, I would go directly to the Application Load Balancer and inspect the target group.

I would look at:

* whether the targets are registered
* whether they are healthy or unhealthy
* the reason the target is marked unhealthy
* the health-check path
* the health-check port
* the health-check protocol
* the expected response code
* whether all targets are unhealthy or only some of them

This is important because the target group's unhealthy reason can immediately narrow down the problem.

For example, if the health check is returning the wrong HTTP status, I would investigate the application or health-check path.

If the health check is timing out, I would investigate connectivity, security groups, the application process, or resource pressure.

I would then move into ECS and CloudWatch.

In ECS I would check:

* task status
* task definition revision
* deployment events
* desired versus running task count
* whether tasks are restarting
* CPU utilization
* memory utilization

Then I would check the application's CloudWatch logs around the exact time the deployment happened.

I would look for application startup errors, exceptions, failed health checks, connection failures, configuration problems, and anything that indicates that the application is technically running but unable to serve requests.

I would also check the ALB metrics, particularly healthy and unhealthy host count, HTTP 5xx responses, and target response time.

The general idea is that I want to correlate:

```text
Deployment
    ↓
ECS task starts
    ↓
ALB health check
    ↓
Target becomes unhealthy
    ↓
ALB returns 503
```

That gives me a much better picture than simply looking at whether the ECS task is running.

### Possible cause 1 — Health-check or target configuration mismatch

The first possible cause is a configuration mismatch between the ALB, target group, ECS task, and application.

For example, the new task could be listening on a different port or interface, the target group could be checking the wrong port or path, or the ECS security group could no longer allow traffic from the ALB security group.

I would compare the complete chain:

```text
ALB listener
    ↓
Target group
    ↓
Target port
    ↓
ECS container port
    ↓
Application listening port
```

For this application, I would confirm that the application is listening on `0.0.0.0:8000` and that the `/health` endpoint returns HTTP 200.

I would also confirm that the ECS task security group allows TCP 8000 from the ALB security group.

The target group's unhealthy reason is particularly useful here.

If the ALB is receiving a response but the response code does not match what the health check expects, I would investigate the application or health-check path.

If the ALB is timing out completely, I would investigate connectivity, the security group, the application process, or resource pressure.

If all of those settings match the deployed revision and the registered target responds successfully to the health check, then I can eliminate this as the primary cause.

### Possible cause 2 — Application regression or resource pressure

The second possibility is that the application itself is unhealthy even though the container is running.

A new release could start successfully but then get stuck during initialization, encounter an application error, or become too resource-intensive to respond properly.

I would check the application logs first for startup exceptions, failed health-check requests, and application errors.

Then I would correlate those logs with:

* CPU utilization
* memory utilization
* target response time
* running task count
* ALB 5xx responses

If CPU or memory suddenly increased around the time the new release was deployed, that could indicate resource pressure.

If the resources are normal but the application logs show exceptions or failed requests, then I would treat it more like an application regression.

The important thing is that I would not automatically assume that the issue is autoscaling.

I would use the metrics to prove whether the workload is actually resource-constrained.

### Possible cause 3 — Dependency or configuration failure

Another possibility is that the application is running but cannot actually serve requests because something it depends on is unavailable or incorrectly configured.

That could be a database, another service, a required configuration value, a secret, or some other dependency.

I would search the application logs for things like:

* connection timeouts
* authentication failures
* DNS failures
* missing configuration
* dependency errors
* connection-pool exhaustion

Then I would investigate the specific dependency and verify that the application can actually reach it.

For example, if the application requires a database connection before it can successfully respond to `/health`, the ECS task could remain `RUNNING` while the ALB continues to mark it unhealthy because the application cannot complete the health check.

If the logs show no dependency errors and the application does not rely on an unavailable external dependency, then I can eliminate this cause.

### Safest immediate recovery action

If I establish that the issue started immediately after the new release and the previous version was known to be healthy, I would not start making random changes to production.

The safest immediate recovery would be to restore the **previous known-good version**.

Because the application image is versioned and pinned, I can identify the previous working image and redeploy that explicitly.

The goal is to restore customer availability first and investigate the faulty release separately.

I would then verify:

* ECS tasks are running
* ALB targets are healthy
* `/health` returns successfully
* 503 responses have stopped
* application logs are normal

I would avoid making ad-hoc production changes through the AWS console unless there is an actual emergency requiring it. If an emergency change is made, it should subsequently be reconciled back into the infrastructure source of truth.

For automated recovery, I would configure the ECS deployment circuit breaker with rollback. That way, if a new ECS deployment fails to become healthy, ECS can automatically roll back to the previous deployment.

The important distinction is that **ECS does not automatically roll back simply because an ALB target is unhealthy unless the appropriate deployment rollback behavior has been configured.**

Preventing the same problem from reaching customers

The immediate recovery gets the service back online, but that is not the end of the incident.

Once the customer impact has been resolved, I would conduct a Post-Incident Review (PIR) to understand exactly what happened and why our existing controls did not catch it before it reached customers.

The PIR should capture:

what happened
customer and business impact
the timeline of the incident
what deployment or change introduced the issue
the root cause
contributing factors
what detected the issue
what went well and what did not
what actions are required to prevent recurrence

The important part is that the PIR should result in tracked corrective actions with owners and priorities, rather than simply documenting what happened.

For example, if the root cause was that a new application version passed the deployment pipeline but failed the ALB health check, the corrective actions could include:

adding a deployment-time runtime health check
improving application smoke tests
validating the ALB health endpoint before production promotion
configuring ECS deployment circuit-breaker rollback
adding appropriate CloudWatch alerting
improving deployment observability
adding a test specifically covering the failure that caused the incident

The deployment process should therefore validate the running application, not just whether the deployment commands completed successfully.

The overall promotion process should be:

Feature branch
      ↓
Pull request
      ↓
CI validation
      ↓
Review
      ↓
Merge
      ↓
Build immutable image
      ↓
Push to ECR
      ↓
Deploy to development
      ↓
Runtime health check
      ↓
Promote to staging
      ↓
Runtime health check
      ↓
Authorized production promotion
      ↓
Production health check

If an incident still occurs, the response should then follow the incident-management lifecycle:

Detect
  ↓
Investigate
  ↓
Mitigate / Recover
  ↓
Restore service
  ↓
Post-Incident Review
  ↓
Root cause analysis
  ↓
Corrective actions
  ↓
Track and verify remediation

The goal is not simply to fix the individual incident. The goal is to identify why the existing controls allowed it to reach customers and then improve the engineering process so that the same class of failure is less likely to happen again.

---

# Engineering Judgement

## Why did I choose this AWS architecture?

I chose ECS Fargate because I wanted the simplest architecture that still gives me the security, reliability, and scalability required for the application.

I could have used EKS, but for a relatively straightforward containerized application, Kubernetes introduces additional operational overhead and cost that I don't think is justified by this workload.

ECS Fargate gives me managed container orchestration without having to manage the underlying EC2 instances, while still integrating cleanly with the ALB, IAM, CloudWatch, and the rest of the AWS architecture.

So the decision was basically a balance between **cost, operational simplicity, security, and what the application actually needs**.

Another possible architecture would be CloudFront with a VPC Origin in front of an internal ALB, with the ECS tasks remaining private.

That would give me additional edge capabilities and further isolate the ALB from direct Internet access, but it also introduces another layer of infrastructure.

For this particular use case, I felt that an internet-facing ALB with private ECS tasks was the simpler architecture that still satisfies the requirement that the application workload itself is not directly exposed to the Internet.

## Why did I choose VPC endpoints?

The application only needs private access to a small number of AWS services.

In this architecture, the ECS tasks need access to ECR, CloudWatch Logs, and S3.

Rather than giving the private subnets a general Internet egress path through a NAT Gateway, I can use VPC endpoints for the specific AWS services that the workload needs.

That gives me a much more restricted network path.

The S3 Gateway Endpoint also doesn't have the same hourly endpoint charge as interface endpoints, while the interface endpoints do have hourly and data-processing costs.

So I would not say that VPC endpoints are universally cheaper than NAT Gateway.

The reason I chose them here is that the workload has a small and clearly defined set of AWS dependencies, so it makes sense to give the workload private access to exactly those services rather than providing general outbound Internet access.

---

# Reliability and Rollback

If a new deployment starts and fails its health checks, the desired behavior is that the new deployment should not become the healthy production version.

The ALB health checks are responsible for determining whether the new targets are actually healthy.

With ECS deployment circuit-breaker rollback configured, the deployment can be considered failed if the new version cannot reach a healthy state, and ECS can roll back to the previous deployment.

The general behavior would therefore be:

```text
Previous healthy version
          ↓
Deploy new version
          ↓
New ECS tasks start
          ↓
ALB health checks
          ↓
     Healthy?
      /      \
    Yes       No
     |         |
Continue     Deployment
             fails
                ↓
          Roll back to
          previous version
```

For a manual rollback, I would use the previous explicitly versioned and pinned application image.

For example, if production is currently running:

```text
v1.4.0
```

and I determine that:

```text
v1.3.2
```

was the last known-good version, I would explicitly redeploy `v1.3.2`.

I prefer this approach because the deployment configuration should always tell me exactly which version I intend to run.

I do not want Terraform to simply select whatever happens to be the newest image in ECR because that makes the actual deployed version less deterministic and makes rollback more difficult.

The Terraform configuration should represent the desired state, and the application version should be an explicit input to that state.


## Production Readiness

Before considering this environment production-ready for a fintech platform, there are three main areas I would improve: **scalability, availability and disaster recovery, and security hardening**.

### 1. Application Auto Scaling

The first improvement I would make is introducing ECS Service Auto Scaling.

The current architecture is intentionally kept simple, and the service is currently configured around a fixed task count. For a production fintech workload, I would not want capacity to be fixed like that.

The service should be able to automatically scale out when demand increases and scale back in when demand decreases.

I would configure scaling based on metrics such as:

* CPU utilization
* Memory utilization
* Request count per target
* Potentially application-specific metrics if the workload requires them

I would also define sensible minimum and maximum task counts.

This would allow the application to handle traffic spikes without requiring manual intervention, while still allowing the environment to scale back down when demand decreases.

I would combine this with the existing ALB health checks and ECS deployment health checks so that scaling does not simply add more unhealthy tasks when there is an application problem.

### 2. Multi-Region Availability and Disaster Recovery

The second major improvement would be adding a proper disaster recovery strategy.

The current architecture is deployed within a single AWS region and uses multiple Availability Zones. That protects the workload against an individual Availability Zone failure, but it does not protect against a full regional failure.

For a fintech platform, I would want to evaluate a multi-region architecture with clearly defined recovery objectives.

For example, I could have a secondary deployment of the same application architecture in another AWS region and use Route 53 health checks and DNS failover to direct traffic to the healthy region if the primary region becomes unavailable.

CloudFront could also be introduced as a global entry point, particularly if I decide to move toward the CloudFront VPC Origin architecture discussed earlier.

The important part is that the secondary region should be capable of actually serving the application. This means considering:

* ECS infrastructure
* ALB infrastructure
* ECR image availability
* Terraform infrastructure
* required configuration and secrets
* DNS and routing
* monitoring and alerting

I would also regularly test the failover process rather than simply assuming that having infrastructure in another region means the disaster recovery strategy works.

The goal is to move from:

> "The application is highly available within one region"

to:

> "The application has a defined and tested recovery path if the entire region becomes unavailable."

### 3. Security Hardening and Threat Protection

The third improvement would be additional security hardening.

The current architecture already has several security controls:

* ECS tasks are in private subnets
* the ALB is the public entry point
* security groups restrict traffic between the ALB and ECS
* IAM follows least privilege
* GitHub uses OIDC rather than long-lived AWS credentials
* HTTPS is used for external traffic
* AWS-service connectivity uses VPC endpoints rather than giving the workload unrestricted Internet access
* CloudWatch provides monitoring and logging

However, for a fintech platform, I would add additional layers of protection around the public-facing application.

The first thing I would consider is **AWS WAF** in front of the application entry point.

This would allow me to introduce controls such as:

* rate limiting
* IP-based restrictions
* protection against common web attacks
* malicious request filtering
* bot-related controls

I would also introduce **Amazon GuardDuty** for threat detection and strengthen centralized security monitoring so that suspicious AWS activity or potentially compromised resources can be detected and investigated.

I would also review the existing IAM policies, security groups, logging, encryption, container security scanning, and CloudTrail configuration to make sure there are no unnecessary permissions or exposed resources.

The important point is that putting ECS in private subnets is only one layer of security.

For a fintech platform, I would assume that the public-facing application will continuously be targeted by automated scanning, bots, and malicious requests, so I would add additional preventive and detective controls around the existing architecture.

### Summary

The three improvements I would prioritize are:

1. **Scalability** — introduce ECS auto scaling and proper capacity management so the application can respond to changes in demand.
2. **Availability and disaster recovery** — introduce a tested multi-region strategy with DNS/traffic failover so the platform can recover from a regional failure.
3. **Security hardening** — add WAF, GuardDuty, and stronger threat detection and protection around the existing networking, IAM, logging, and monitoring controls.

These improvements build directly on the architecture I have already designed rather than introducing unnecessary components. They address the three areas I would consider most important before taking this architecture into a higher-criticality production environment: **can it scale, can it recover from a major failure, and can it withstand and detect attacks?**
