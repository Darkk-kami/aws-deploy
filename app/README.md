# AWS Deploy application

This directory contains a small FastAPI service. It exposes:

- `GET /health` returns `{"status": "ok"}` and is intended for health checks.
- `GET /version` returns the image's application version and source commit, for example:
  `{"version": "v1.2.0", "git_commit": "012345..."}`.

The FastAPI application is created in `src/main.py` and served by Uvicorn on
`0.0.0.0:8000`. The container runs as the non-root user with UID/GID `10001`.

## Build metadata and environment

Every image build must provide both of these Docker build arguments:

| Name | Required | Purpose |
| --- | --- | --- |
| `APP_VERSION` | Yes | Human-readable release tag or build version. It is used by FastAPI and returned by `/version`. |
| `GIT_COMMIT` | Yes | Git commit that supplied the source code. It is returned by `/version`. |

The Dockerfile deliberately has no defaults for these arguments. A build without
either value fails, preventing an image from being published without enough
metadata to identify its source. During the build, both values are also set as
container environment variables and written to the image labels
`org.internal.image.version` and `org.internal.image.revision`. They are
build-time inputs that become runtime environment variables in the resulting
image; they do not need to be passed again when starting that image.

For a tagged release, use the release tag as `APP_VERSION`. For other builds,
use the GitHub Actions run's `${{ github.sha }}` (or the equivalent full local
Git commit SHA) as `APP_VERSION`. Always set `GIT_COMMIT` to the full commit SHA
that was built. A tag is useful as a release name, while the commit SHA
unambiguously identifies the exact source revision, including when branches or
tags move or multiple images are built from the same release.

`APP_ENV` is also read by `src/main.py`, but it currently does not change
application behavior and is not required by the Dockerfile. Set it only if a
deployment environment needs to supply it; environment-specific behavior
should be implemented before relying on it.

## Build the image

Run this from the repository root. It uses the current commit as both the
development version and the source revision:

```sh
docker build \
  -f app/Dockerfile \
  --build-arg APP_VERSION="$(git rev-parse HEAD)" \
  --build-arg GIT_COMMIT="$(git rev-parse HEAD)" \
  -t aws-deploy:local \
  app
```

## Why a multi-stage Docker build?

The Dockerfile uses the same pinned Python base image in two stages:

1. **`builder`** installs the packages from `requirements.txt` under `/install`.
   Pip's download cache is mounted for the build step so it can speed up
   rebuilds without being copied into the image.
2. **`runner`** starts from the base image again and copies in only the
   installed Python packages and application source. It does not inherit the
   builder's files or build-time state.

This keeps the runtime image focused on what is needed to run FastAPI and
Uvicorn, rather than the installer's cache or other builder-stage contents. The
base image is pinned by digest so rebuilding with the same Dockerfile uses the
same base-image contents.

## Run and check the service

Run the built image:

```sh
docker run --rm -p 8000:8000 aws-deploy:local
```

Then check `http://localhost:8000/health` and
`http://localhost:8000/version`.

The `/health` endpoint is suitable for an ECS
health check.

The Dockerfile's built-in `HEALTHCHECK` is currently commented
out because ECS already runs its own health checks

To run the service directly from `app/` for local development:

```sh
python -m pip install -r requirements.txt
APP_VERSION=dev GIT_COMMIT="$(git -C .. rev-parse HEAD)" \
  python -m uvicorn src.main:app --host 0.0.0.0 --port 8000
```

### Possible improvements

- Adding an `app/Dockerfile.dev` for local development. It could use
convenient development defaults and omit production-only constraints such as
requiring explicit version and commit build arguments, so developers can build
and run the service without preparing release metadata. 