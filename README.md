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

Pull requests run separate app and infrastructure workflows:

- **App CI** lints Python with Ruff, audits Python dependencies with `pip-audit`, scans source and the Dockerfile with Trivy, builds the Docker image with commit metadata, and verifies `/health` returns HTTP 200.
- **Infrastructure CI** checks Terraform formatting and validation, scans Terraform configuration with Trivy, and creates a Terraform plan.

The Terraform plan job uses GitHub OIDC and requires the repository secret
`AWS_ROLE` to identify a plan-only IAM role. Configure the role trust policy
for this repository's GitHub Actions identity. Its permissions should allow
reading Terraform state and inspecting managed AWS resources; S3 lock-file
permissions may also be required by the configured backend. The plan job is
skipped for pull requests from forks so AWS credentials are not exposed to
untrusted PR code.

Trivy ignores two documented infrastructure findings in `.trivyignore`: the
intentionally public application load balancer, and SSE-S3 on the ALB access
log bucket, which does not support SSE-KMS. Other high and critical findings
fail the security checks.

## Application delivery

`.github/workflows/cd_app.yml` runs when changes under `app/` are pushed to
`main`. It uses the composite action in `.github/actions/release/` to run
`semantic-release` against the conventional-commit history and calculate the
next version. Commits that do not trigger a release do not build or publish an
image.

For a release, the workflow builds and smoke-tests the image, creates the
GitHub Release and tag, and publishes the image to ECR with the release version
and `sha-<full-commit-sha>` tags. ECR tags are immutable, so an existing tag
cannot be overwritten. The workflow uses GitHub OIDC and requires the
`AWS_DEPLOY_ROLE` secret to contain an IAM role trusted by this repository's
GitHub Actions identity, with permissions to log in to ECR and push to this
repository. Publishing an image does not update the ECS service.
