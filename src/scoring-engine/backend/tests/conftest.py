import json
import os
import tempfile
from pathlib import Path

_tmp = Path(tempfile.mkdtemp())
os.environ.update({
    "VS_DATABASE_URL": f"sqlite+aiosqlite:///{_tmp / 'test.db'}",
    "VS_GRAPH_MODE": "mock",
    "VS_GRAPH_MOCK_FILE": str(_tmp / "mock_graph.json"),
    "VS_AUTH_MODE": "local",
    "VS_ADMIN_PASSWORD": "pw",
})

import httpx  # noqa: E402
import pytest  # noqa: E402

from app.db import engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Base  # noqa: E402

MOCK_FILE = _tmp / "mock_graph.json"


def write_mock(data: dict) -> None:
    tmp = MOCK_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    os.replace(tmp, MOCK_FILE)
    # mtime resolution can be coarse; force a visible change for the mock source cache
    st = MOCK_FILE.stat()
    os.utime(MOCK_FILE, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000))


@pytest.fixture(autouse=True)
async def fresh_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    write_mock({"users": {}})
    yield


@pytest.fixture
async def client():
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as c:
        yield c


@pytest.fixture
async def admin(client):
    r = await client.post("/api/auth/login", json={"username": "admin", "password": "pw"})
    assert r.status_code == 200
    return {"Authorization": f"Bearer {r.json()['access_token']}"}
