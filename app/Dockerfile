# syntax=docker/dockerfile:1

ARG PYTHON_IMAGE=python:3.14-slim@sha256:f85c5697265c178cc6887276c55fe16cf3d14ca35c3df6a5eab3b360534a55d2

FROM ${PYTHON_IMAGE} AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_COMPILE=1

    
WORKDIR /build

COPY requirements.txt .

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --prefix=/install -r requirements.txt

FROM ${PYTHON_IMAGE} AS runner

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY --from=builder /install/ /usr/local/
COPY src ./src

ARG APP_VERSION
ARG GIT_COMMIT

RUN : "${APP_VERSION:?APP_VERSION build arg is required}" \
      "${GIT_COMMIT:?GIT_COMMIT build arg is required}"

ENV APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT}

LABEL org.internal.image.version=${APP_VERSION} \
      org.internal.image.revision=${GIT_COMMIT}

USER 10001:10001
 
EXPOSE 8000

# ECS runs health checks against the /health endpoint, so we can use that for the Docker HEALTHCHECK as well.
# HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
#     CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=3)"]

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
