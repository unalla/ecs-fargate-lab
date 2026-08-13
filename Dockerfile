# The base image is passed in by CI from base-image.lock, pinned by digest.
# Never a floating tag: a pinned digest is what makes a rebuild auditable.
ARG BASE_IMAGE=python:3.12-slim

# ---------- build stage ----------
FROM ${BASE_IMAGE} AS builder

WORKDIR /build

# Dependencies first, on their own layer. This is the layer-ordering point:
# app code changes daily, dependencies change monthly, the OS changes on CVE.
# Ordering cheapest-changing to most-changing means a base bump reuses
# everything above it from cache and a code change reuses everything below.
COPY app/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- runtime stage ----------
FROM ${BASE_IMAGE} AS runtime

# Rebuild the OS layer rather than patching it: apt runs at build time only,
# and the result is an immutable artifact you can roll back to by digest.
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 appuser

COPY --from=builder /install /usr/local
WORKDIR /srv
COPY app/ /srv/

# Build-time provenance, surfaced by the app at /version.
ARG GIT_SHA=local
ARG IMAGE_DIGEST=unbuilt
ARG BASE_DIGEST=unpinned
ARG APP_VERSION=0.0.0-dev
ENV GIT_SHA=${GIT_SHA} \
    IMAGE_DIGEST=${IMAGE_DIGEST} \
    BASE_DIGEST=${BASE_DIGEST} \
    APP_VERSION=${APP_VERSION} \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER appuser
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -fsS http://localhost:8080/healthz || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", \
     "--access-logfile", "-", "--error-logfile", "-", "app:app"]
