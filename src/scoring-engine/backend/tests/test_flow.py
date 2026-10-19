import io
import zipfile
from datetime import datetime, timedelta, timezone

from app.checks.office_text import extract_text
from app.rubric import RubricError, parse_rubric
from app.worker import claim, process
from tests.conftest import write_mock

UPN = "labuser001@ignite.test"
RUBRIC = """
checks:
  - id: brief
    type: onedrive_file
    params: {folder: /Cowork, name_pattern: "*brief*", extensions: [docx], content_contains: [Contoso]}
    fail_message: No brief found.
  - id: prompt
    type: copilot_interaction
    mode: deferred
    params: {prompt_contains: [Contoso]}
"""


def iso(dt):
    return dt.isoformat().replace("+00:00", "Z")


async def setup_event(client, admin):
    e = (await client.post("/api/admin/events", headers=admin,
                           json={"slug": "ignite", "name": "Ignite", "status": "live"})).json()
    uc = (await client.post(f"/api/admin/events/{e['id']}/use-cases", headers=admin,
                            json={"code": "cowork", "title": "Cowork"})).json()
    r = await client.post(f"/api/admin/use-cases/{uc['id']}/steps", headers=admin,
                          json={"code": "step-1", "title": "Brief", "rubric_yaml": RUBRIC})
    assert r.status_code == 201, r.text
    i = (await client.post("/api/admin/integrations", headers=admin,
                           json={"name": "Partner test", "vendor": "Demo Labs"})).json()
    tok = (await client.post("/oauth/token", data={"grant_type": "client_credentials", "client_id": i["client_id"],
                                                    "client_secret": i["client_secret"]})).json()
    return e, i, {"Authorization": f"Bearer {tok['access_token']}"}


def payload(started: datetime, external_id="skl-1", first="Asha"):
    return {"event_id": "ignite", "use_case_id": "cowork", "step_id": "step-1",
            "lab": {"lab_instance_id": "inst-1", "lab_started_at": iso(started)},
            "participant": {"external_id": external_id, "first_name": first, "last_name": "Kumar",
                            "email": "asha@example.com"},
            "lab_account": {"upn": UPN}}


async def drain():
    while ids := await claim(10):
        for sid in ids:
            await process(sid)


async def test_rubric_validation():
    assert len(parse_rubric(RUBRIC).checks) == 2
    try:
        parse_rubric("checks:\n  - id: x\n    type: nope\n")
    except RubricError as exc:
        assert "unknown check type" in exc.errors[0]
    else:
        raise AssertionError("expected RubricError")


async def test_handshake_rejects_bad_secret(client, admin):
    _, i, _ = await setup_event(client, admin)
    r = await client.post("/oauth/token", data={"client_id": i["client_id"], "client_secret": "wrong"})
    assert r.status_code == 401
    r = await client.post("/v1/steps/complete", json={}, headers={"Authorization": "Bearer junk"})
    assert r.status_code == 401


async def test_incomplete_then_complete(client, admin):
    event, _, vendor = await setup_event(client, admin)
    started = datetime.now(timezone.utc) - timedelta(minutes=10)

    r = await client.post("/v1/steps/complete", json=payload(started), headers={**vendor, "Idempotency-Key": "a"})
    assert r.status_code == 202 and r.json()["status"] == "evaluating"
    sid = r.json()["submission_id"]
    await drain()
    res = (await client.get(f"/v1/submissions/{sid}", headers=vendor)).json()
    assert res["status"] == "incomplete" and res["completed"] is False
    assert res["reasons"] == [{"check": "brief", "message": "No brief found."}]

    # idempotent replay returns the same submission
    again = await client.post("/v1/steps/complete", json=payload(started), headers={**vendor, "Idempotency-Key": "a"})
    assert again.json()["submission_id"] == sid and again.headers.get("Idempotent-Replayed") == "true"

    now = iso(datetime.now(timezone.utc))
    old = iso(started - timedelta(hours=1))
    write_mock({"users": {UPN: {
        "drive": {"/Cowork": [
            {"id": "f0", "name": "old brief.docx", "file": {}, "createdDateTime": old, "createdBy": {"user": {"email": UPN}}},
            {"id": "f1", "name": "Contoso brief.docx", "file": {}, "createdDateTime": now,
             "createdBy": {"user": {"email": UPN}}}]},
        "file_contents": {"f1": "Account brief for Contoso"},
    }}})
    r = await client.post("/v1/steps/complete", json=payload(started), headers={**vendor, "Idempotency-Key": "b"})
    await drain()
    res = (await client.get(f"/v1/submissions/{r.json()['submission_id']}", headers=vendor)).json()
    assert res["status"] == "complete", res
    assert res["verification"]["status"] == "pending"  # deferred Copilot evidence not there yet

    board = (await client.get(f"/api/admin/events/{event['id']}/leaderboard", headers=admin)).json()
    assert board["rows"][0]["completed_steps"] == 1 and board["rows"][0]["rank"] == 1
    assert board["rows"][0]["attempts"] == 2

    card = await client.post("/api/public/events/ignite/scorecard", json={"upn": UPN.upper()})
    assert card.status_code == 200, card.text
    card = card.json()
    assert card["steps"][0]["status"] == "complete" and card["completed_steps"] == 1
    assert "rows" not in card  # a participant only ever sees their own scorecard
    missing = await client.post("/api/public/events/ignite/scorecard", json={"upn": "nobody@ignite.test"})
    assert missing.status_code == 404
    assert (await client.get("/api/public/events/ignite/leaderboard")).status_code in (404, 405)

    progress = (await client.get("/v1/events/ignite/participants/skl-1/progress", headers=vendor)).json()
    assert progress["completed_steps"] == 1

    for fmt in ("csv", "xlsx"):
        exp = await client.get(f"/api/admin/events/{event['id']}/leaderboard/export", params={"format": fmt},
                               headers=admin)
        assert exp.status_code == 200 and len(exp.content) > 50


async def test_revoked_integration_blocks_tokens(client, admin):
    _, i, vendor = await setup_event(client, admin)
    await client.post(f"/api/admin/integrations/{i['id']}/status", params={"status": "revoked"}, headers=admin)
    r = await client.post("/v1/steps/complete", json=payload(datetime.now(timezone.utc)), headers=vendor)
    assert r.status_code == 401


async def test_validation_errors_are_readable(client, admin):
    _, _, vendor = await setup_event(client, admin)
    r = await client.post("/v1/steps/complete", json={"event_id": "ignite"}, headers=vendor)
    assert r.status_code == 422
    assert {e["field"] for e in r.json()["detail"]["errors"]} >= {"lab", "lab_account", "participant"}


def test_office_text_extraction():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("word/document.xml", "<w:document><w:t>Hello</w:t><w:t>Contoso &amp; Co</w:t></w:document>")
    text = extract_text(buf.getvalue(), "docx")
    assert "Contoso & Co" in text and "Hello" in text


async def test_sync_scores_without_partner_calls(client, admin):
    """Partner never calls the API: organiser imports a roster and syncs from Microsoft 365."""
    from app import sync

    event, _, _ = await setup_event(client, admin)
    started = datetime.now(timezone.utc) - timedelta(minutes=30)
    r = await client.post(f"/api/admin/events/{event['id']}/roster", headers=admin,
                          json={"csv": f"upn,first_name,last_name,lab_started_at\n{UPN},Mei,Chen,{iso(started)}\n"
                                       "labuser002@ignite.test,Liam,Walsh,\n"})
    assert r.json() == {"added": 2, "updated": 0, "rows": 2}

    async def run_sync():
        run = (await client.post(f"/api/admin/events/{event['id']}/sync", headers=admin)).json()
        assert await sync.claim_run() == run["id"]
        await sync.execute(run["id"])
        return (await client.get(f"/api/admin/events/{event['id']}/sync-runs", headers=admin)).json()

    first = await run_sync()
    assert first["runs"][0]["status"] == "completed" and first["runs"][0]["new_completions"] == 0
    assert first["runs"][0]["watermark_from"] is None and first["last_synced_at"]

    done_at = datetime.now(timezone.utc) - timedelta(minutes=5)
    write_mock({"users": {UPN: {
        "drive": {"/Cowork": [{"id": "f1", "name": "Contoso brief.docx", "file": {}, "createdDateTime": iso(done_at),
                               "createdBy": {"user": {"email": UPN}}}]},
        "file_contents": {"f1": "Contoso brief"}}}})
    second = await run_sync()
    run2 = second["runs"][0]
    assert run2["new_completions"] == 1 and run2["watermark_from"] == first["last_synced_at"]

    third = await run_sync()  # delta: the completed step is not re-scanned
    assert third["runs"][0]["steps_skipped"] == 1 and third["runs"][0]["steps_checked"] == 1

    board = (await client.get(f"/api/admin/events/{event['id']}/leaderboard", headers=admin)).json()
    top = board["rows"][0]
    assert top["name"] == "Mei Chen" and top["completed_steps"] == 1
    assert top["elapsed_seconds"] == 25 * 60  # timed by the evidence, not by when the sync ran

    # A partner call later for the same lab account adopts the synced participant instead of duplicating it.
    _, _, vendor = await setup_vendor_only(client, admin)
    await client.post("/v1/steps/complete", json=payload(started, external_id="skl-77"), headers=vendor)
    board = (await client.get(f"/api/admin/events/{event['id']}/leaderboard", headers=admin)).json()
    assert board["participants_total"] == 2


async def setup_vendor_only(client, admin):
    i = (await client.post("/api/admin/integrations", headers=admin, json={"name": "Second", "vendor": "Second Labs"})).json()
    tok = (await client.post("/oauth/token", data={"client_id": i["client_id"], "client_secret": i["client_secret"]})).json()
    return None, i, {"Authorization": f"Bearer {tok['access_token']}"}
