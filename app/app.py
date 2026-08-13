"""
Deployment provenance demo app.

Its only job is to tell you, honestly, which image is serving this request.
That makes rolling deploys and rollbacks visible instead of theoretical.
"""

import os
import socket
from datetime import datetime, timezone

from flask import Flask, jsonify, render_template

app = Flask(__name__)

# Injected at build time by the pipeline. Defaults keep local runs honest
# about the fact that nothing was stamped.
GIT_SHA = os.environ.get("GIT_SHA", "local")
IMAGE_DIGEST = os.environ.get("IMAGE_DIGEST", "unbuilt")
BASE_DIGEST = os.environ.get("BASE_DIGEST", "unpinned")
APP_VERSION = os.environ.get("APP_VERSION", "0.0.0-dev")

STARTED_AT = datetime.now(timezone.utc)

# Flipped by /simulate-failure so you can watch the ECS circuit breaker
# fail a deployment and roll it back on its own.
_healthy = True


def _provenance():
    return {
        "app_version": APP_VERSION,
        "git_sha": GIT_SHA,
        "image_digest": IMAGE_DIGEST,
        "base_digest": BASE_DIGEST,
        "hostname": socket.gethostname(),
        "started_at": STARTED_AT.isoformat(),
        "uptime_seconds": int(
            (datetime.now(timezone.utc) - STARTED_AT).total_seconds()
        ),
    }


@app.get("/")
def index():
    return render_template("index.html", healthy=_healthy, **_provenance())


@app.get("/healthz")
def healthz():
    """ALB target group health check hits this."""
    if not _healthy:
        return jsonify({"status": "unhealthy"}), 500
    return jsonify({"status": "healthy"}), 200


@app.get("/version")
def version():
    return jsonify(_provenance()), 200


@app.post("/simulate-failure")
def simulate_failure():
    """Make this task start failing health checks. Restart to recover."""
    global _healthy
    _healthy = False
    return jsonify({"status": "unhealthy", "note": "health checks will now fail"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
