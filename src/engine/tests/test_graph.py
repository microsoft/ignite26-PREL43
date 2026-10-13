"""Transport tests for the Microsoft Graph backend, with HTTP stubbed out."""
from __future__ import annotations

import base64
import datetime as dt
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "src" / "engine"))

from vs_hydrate.api import graph  # noqa: E402
from vs_hydrate.api.base import NotReady, TenantError  # noqa: E402


class Resp:
    def __init__(self, status, body=None, headers=None, content=None):
        self.status_code = status
        self._body = body
        self.headers = {"Content-Type": "application/json", **(headers or {})}
        self.content = content if content is not None else (json.dumps(body).encode() if body is not None else b"")
        self.text = self.content.decode(errors="replace")

    def json(self):
        return self._body


@pytest.fixture()
def cert(tmp_path) -> Path:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "vs-test")])
    now = dt.datetime.now(dt.timezone.utc)
    c = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
         .serial_number(1).not_valid_before(now).not_valid_after(now + dt.timedelta(days=1))
         .sign(key, hashes.SHA256()))
    p = tmp_path / "vs.pem"
    p.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                                    serialization.NoEncryption()) + c.public_bytes(serialization.Encoding.PEM))
    return p


@pytest.fixture()
def api(cert, monkeypatch):
    roles = {"roles": ["User.ReadWrite.All", "Teamwork.Migrate.All"]}
    tok = "h." + base64.urlsafe_b64encode(json.dumps(roles).encode()).decode().rstrip("=") + ".s"

    class App:
        def __init__(self, *a, **k):
            assert k["client_credential"]["thumbprint"]

        def acquire_token_for_client(self, scopes):
            return {"access_token": tok}
    import msal
    monkeypatch.setattr(msal, "ConfidentialClientApplication", App)
    monkeypatch.setattr(graph.time, "sleep", lambda s: None)
    return graph.GraphTenant("t", "c", str(cert))


def stub(api, monkeypatch, responses):
    calls = []

    def request(method, url, **kw):
        calls.append((method, url, kw))
        return responses.pop(0)
    sess = api._session()
    monkeypatch.setattr(sess, "request", request)
    return calls


def test_roles_from_token(api):
    assert api.granted_roles() == {"User.ReadWrite.All", "Teamwork.Migrate.All"}


def test_retries_on_throttling(api, monkeypatch):
    calls = stub(api, monkeypatch, [Resp(429, {"error": {}}, {"Retry-After": "2"}), Resp(503, {"error": {}}),
                                    Resp(200, {"id": "u1"})])
    assert api.get_user("a@b")["id"] == "u1"
    assert len(calls) == 3


def test_error_is_reported(api, monkeypatch):
    stub(api, monkeypatch, [Resp(403, {"error": {"code": "Authorization_RequestDenied", "message": "nope"}})])
    with pytest.raises(TenantError) as e:
        api.create_user({})
    assert e.value.status == 403 and "Authorization_RequestDenied" in str(e.value)


def test_team_creation_polls_operation(api, monkeypatch):
    calls = stub(api, monkeypatch, [
        Resp(202, None, {"Location": "/teams('T1')/operations('OP1')"}),
        Resp(200, {"status": "inProgress"}), Resp(200, {"status": "succeeded"})])
    assert api.create_migration_team("Zava Product Launches", "d", "2026-10-01T09:00:00.000Z") == "T1"
    body = calls[0][2]["json"]
    assert body["@microsoft.graph.teamCreationMode"] == "migration"
    assert calls[2][1].endswith("/teams/T1/operations/OP1")


def test_files_folder_not_ready(api, monkeypatch):
    stub(api, monkeypatch, [Resp(404, {"error": {"code": "NotFound", "message": "x"}})])
    with pytest.raises(NotReady):
        api.channel_files_folder("T1", "C1")


def test_paging(api, monkeypatch):
    stub(api, monkeypatch, [Resp(200, {"value": [{"id": 1}], "@odata.nextLink": "https://graph.microsoft.com/v1.0/next"}),
                            Resp(200, {"value": [{"id": 2}]})])
    assert [x["id"] for x in api.subscribed_skus()] == [1, 2]


def test_completed_migration_is_idempotent(api, monkeypatch):
    stub(api, monkeypatch, [Resp(400, {"error": {"code": "BadRequest", "message": "Channel is not in migration mode"}})])
    api.complete_channel_migration("T1", "C1")
