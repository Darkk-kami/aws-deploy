"""FastAPI health and build-version endpoints."""

import logging
import os

import uvicorn
from fastapi import FastAPI

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger(__name__)

APP_VERSION = os.environ.get("APP_VERSION")
GIT_COMMIT = os.environ.get("GIT_COMMIT")
APP_ENV = os.environ.get("APP_ENV")

app = FastAPI(title="aws-deploy", version=APP_VERSION, description=f"Git commit: {GIT_COMMIT}")

@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/version")
def version() -> dict[str, str]:
    return {"version": APP_VERSION, "git_commit": GIT_COMMIT}


def main() -> None:
    uvicorn.run(app, host="0.0.0.0", port=8000)