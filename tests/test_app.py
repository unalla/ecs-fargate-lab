"""
This is the gate. A base-image bump PR runs exactly these tests — the same
ones a feature PR runs. If a new OS layer breaks the app, it fails here and
nothing is deployed.
"""

import importlib
import ssl
import sys

import pytest

sys.path.insert(0, "app")


@pytest.fixture()
def client():
    import app as app_module

    importlib.reload(app_module)
    app_module.app.config.update(TESTING=True)
    with app_module.app.test_client() as c:
        yield c


def test_healthz_returns_200(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "healthy"


def test_version_exposes_provenance(client):
    body = client.get("/version").get_json()
    for field in ("app_version", "git_sha", "image_digest", "base_digest", "hostname"):
        assert field in body, f"missing provenance field: {field}"


def test_index_renders_digest(client):
    r = client.get("/")
    assert r.status_code == 200
    assert b"Image digest" in r.data


def test_simulate_failure_flips_health(client):
    assert client.get("/healthz").status_code == 200
    client.post("/simulate-failure")
    assert client.get("/healthz").status_code == 500


def test_tls_stack_is_usable():
    """
    A real base-image canary. OpenSSL lives in the OS layer, so an incompatible
    base bump tends to surface as a broken TLS context rather than a Python error.
    """
    ctx = ssl.create_default_context()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2  # raises if the OS OpenSSL is too old
    assert ssl.HAS_TLSv1_3, "linked OpenSSL does not support TLS 1.3"
    assert ctx.verify_mode == ssl.CERT_REQUIRED
    assert ssl.OPENSSL_VERSION_INFO[0] >= 3, ssl.OPENSSL_VERSION


def test_python_runtime_is_expected_major_minor():
    """Catches a base image that silently moved you to a different interpreter."""
    assert sys.version_info[:2] == (3, 12)
