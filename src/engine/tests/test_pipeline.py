"""End-to-end tests against the in-memory tenant.

Run from the repo root:  python -m pytest src/engine/tests -q
Uses the committed data pack in data/release (built first if missing).
"""
from __future__ import annotations

import io
import json
import shutil
import subprocess
import sys
import zipfile
from datetime import timedelta
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "src" / "engine"))

from vs_hydrate.api.fake import FakeTenant  # noqa: E402
from vs_hydrate.cli import Locked, main  # noqa: E402
from vs_hydrate.config import Config  # noqa: E402
from vs_hydrate.kit import Kit  # noqa: E402
from vs_hydrate.ops.seats import conversation_index  # noqa: E402
from vs_hydrate.render import PH_RE, render_office  # noqa: E402
from vs_hydrate.textextract import extract_text  # noqa: E402

from vs_hydrate import __version__ as VERSION  # noqa: E402

ZIP = ROOT / "data" / "release" / f"helix-datapack-{VERSION}.zip"


@pytest.fixture(scope="session")
def datapack_zip() -> Path:
    if not ZIP.exists():
        subprocess.run([sys.executable, str(ROOT / "src" / "tools" / "build_datapack.py"), "--no-recalc"], check=True)
    return ZIP


@pytest.fixture()
def kitdir(tmp_path, datapack_zip) -> Path:
    (tmp_path / "data" / "release").mkdir(parents=True)
    shutil.copy(datapack_zip, tmp_path / "data" / "release" / datapack_zip.name)
    shutil.copytree(ROOT / "data" / "scoring", tmp_path / "data" / "scoring")
    shutil.copytree(ROOT / "data" / "readiness", tmp_path / "data" / "readiness")
    shutil.copy(ROOT / "infra" / "config" / "tenant.example.yaml", tmp_path / "tenant.yaml")
    return tmp_path


def run(kitdir: Path, *args) -> tuple[int, dict]:
    cfg = str(kitdir / "tenant.yaml")
    buf = io.StringIO()
    old, sys.stdout = sys.stdout, buf
    try:
        code = main([*args, "--config", cfg, "--offline", "--json"])
    finally:
        sys.stdout = old
    return code, json.loads(buf.getvalue())


def fake(kitdir: Path) -> FakeTenant:
    return FakeTenant.open(kitdir / "out" / "offline-tenant.json", groups=["VS-Lab-Seats"])


def state(kitdir: Path) -> dict:
    return json.loads((kitdir / "out" / "state.json").read_text())


def hydrate(kitdir: Path, n: int = 2) -> None:
    assert run(kitdir, "tenant")[0] == 0
    code, body = run(kitdir, "seats", "--count", str(n))
    assert code == 0, body
    code, body = run(kitdir, "check")
    assert code == 0 and body["ready"] == n, body


# ------------------------------------------------------------------ data pack
def test_validate_passes(kitdir):
    code, body = run(kitdir, "validate")
    assert code == 0
    assert {c["check"] for c in body["checks"] if c["status"] == "fail"} == set()


def test_office_placeholders_render(datapack_zip):
    from datetime import date
    from zoneinfo import ZoneInfo

    from vs_hydrate.datapack import DataPack
    from vs_hydrate.render import Context
    from vs_hydrate.timeline import Timeline
    pack = DataPack.load(datapack_zip)
    ctx = Context(Timeline(date(2026, 10, 20), ZoneInfo("UTC")), "Jordan Avery", "Jordan", "lab0001@zava.example")
    for name, data in pack.files.items():
        txt = extract_text(name, render_office(name, data, ctx))
        assert not PH_RE.search(txt), f"unrendered placeholder in {name}"
    plan = extract_text("p.docx", render_office("Helix-Launch-Plan.docx", pack.files["Helix-Launch-Plan.docx"], ctx))
    assert "Friday 30 October 2026" in plan  # D+10 from 20 Oct 2026


def test_lint_catches_forbidden_phrase(tmp_path, datapack_zip):
    """A seeded item that matches a scoring check must break validation."""
    src = zipfile.ZipFile(datapack_zip)
    bad = tmp_path / "bad.zip"
    with zipfile.ZipFile(bad, "w") as z:
        for n in src.namelist():
            data = src.read(n)
            if n == "source/mail.yaml":
                data = data.replace(b"Helix is yours from tomorrow", b"Helix status review")
            z.writestr(n, data)
    from vs_hydrate.datapack import DataPack
    from vs_hydrate.integrity import scan_datapack
    from vs_hydrate.render import Context
    from vs_hydrate.timeline import Timeline
    from datetime import date
    from zoneinfo import ZoneInfo
    pack = DataPack.load(bad)
    assert pack.verify(), "checksum should flag the edit"
    forbidden = json.loads((ROOT / "data" / "scoring" / "scorecard.json").read_text())["seed_rules"]["forbidden"]
    ctx = Context(Timeline(date(2026, 10, 20), ZoneInfo("UTC")), "A B", "A", "a@b")
    assert any("Helix status review" in f for f in scan_datapack(pack, forbidden, ctx))


def test_conversation_index_chains():
    from datetime import datetime, timezone
    t0 = datetime(2026, 10, 3, 9, 12, tzinfo=timezone.utc)
    a = conversation_index(None, t0, t0, "seed", 0)
    b = conversation_index(a, t0, t0 + timedelta(days=1), "seed", 1)
    c = conversation_index(b, t0, t0 + timedelta(days=2), "seed", 2)
    assert len(a) == 22 and len(b) == 27 and len(c) == 32
    assert b.startswith(a) and c.startswith(b)


# ------------------------------------------------------------------ hydration
def test_seat_matches_day_one_check(kitdir):
    hydrate(kitdir, 1)
    st = state(kitdir)
    seat = st["seats"]["lab0001@zava.example"]
    t = fake(kitdir)
    inbox = [m for m in t.mail[seat["id"]] if m["folder"] == "inbox"]
    thread = [m for m in inbox if "helix sensor modules" in m["subject"].lower()]
    assert len(thread) == 6 and len({m["conversationId"] for m in thread}) == 1
    assert not any("eventMessage" in m["@odata.type"] for m in inbox), "invitations should be cleaned up"
    assert all(not m["isDraft"] for m in inbox)
    unread = {m["subject"] for m in inbox if not m["isRead"]}
    assert "Does the Helix date hold?" in unread
    ch = t.teams[seat["team_id"]]["channels"][seat["channel_id"]]
    assert ch["displayName"] == "Launch - Helix"
    assert sum(1 + len(m["replies"]) for m in ch["messages"]) == 20
    assert sum(1 for m in ch["messages"] if m["mentions"]) == 3
    assert t.teams[seat["team_id"]]["migration"] is False
    assert seat["id"] in t.teams[seat["team_id"]]["members"]
    accepted = [e for e in t.events[seat["id"]] if e["responseStatus"]["response"] == "accepted"]
    assert len(accepted) == 8
    assert seat["tap"]
    assert t.users[seat["id"]]["mailboxSettings"]["timeZone"] == "India Standard Time"


def test_learner_scores_like_the_example(kitdir):
    """M1-M4 done, UNCONFIRMED missed, M5 skipped -> 79, PASS (the operator guide example)."""
    hydrate(kitdir, 1)
    seat = state(kitdir)["seats"]["lab0001@zava.example"]
    t = fake(kitdir)
    uid = seat["id"]
    tl_day = seat["lab_day"]
    from datetime import date, timedelta as td
    d1 = (date.fromisoformat(tl_day) + td(days=1)).isoformat()
    t.simulate_mail(uid, "drafts", "RE: Helix customer FAQ", "Holding reply.\n\nSent by Copilot Cowork")
    t.simulate_event(uid, "Helix messaging review", f"{d1}T10:00:00", f"{d1}T10:30:00", "India Standard Time")
    t.simulate_event(uid, "Helix launch checklist", f"{d1}T14:00:00", f"{d1}T14:30:00", "India Standard Time")
    from openpyxl import Workbook
    wb = Workbook()
    wb.active.append(["Risk", "Category", "Likelihood", "Impact", "Owner", "Mitigation", "Status",
                      "Source file", "Source evidence", "Confidence"])
    wb.active.append(["Certification timing", "Regulatory", "High", "High", "TBD", "", "Open",
                      "Helix-Launch-Plan.docx", "Plan section 4", "Medium"])
    buf = io.BytesIO()
    wb.save(buf)
    t.simulate_drive_file(uid, "Documents/Cowork/Tasks/t1/output/Helix-Risk-Register.xlsx", buf.getvalue())
    t.simulate_drive_file(uid, "Documents/Cowork/skills/launch-status-report/SKILL.md",
                          b"---\nname: launch-status-report\n---\nA risk with no source is marked UNCONFIRMED.")
    t.simulate_drive_file(uid, "Documents/Cowork/Tasks/t2/output/Helix-Status-2026-10-12.docx", b"PK")
    t.simulate_mail(uid, "inbox", "Helix launch briefing - 12 October", "What changed overnight ...")
    t.save()

    code, res = run(kitdir, "score", "--seat", "lab0001@zava.example")
    assert code == 0
    assert res["score"] == 79 and res["passed"] is True
    assert res["checks"]["unconfirmed-marked"] == 0, "SKILL.md must not satisfy the M2 UNCONFIRMED check"
    assert "unconfirmed-marked" in res["recheck"]
    assert "M2 unconfirmed-marked" in res["feedback"]


def test_cancelled_block_and_guard(kitdir):
    hydrate(kitdir, 1)
    seat = state(kitdir)["seats"]["lab0001@zava.example"]
    t = fake(kitdir)
    t.simulate_event(seat["id"], "Helix status review", f"{seat['lab_day']}T16:00:00", f"{seat['lab_day']}T16:30:00",
                     "India Standard Time")
    t.save()
    _, res = run(kitdir, "score", "--seat", "lab0001@zava.example")
    assert res["checks"]["third-block-cancelled"] == 0


def test_guard_blocks_free_points(kitdir):
    sc = json.loads((kitdir / "data" / "scoring" / "scorecard.json").read_text())
    sc["guards"]["third-block-cancelled"]["enabled"] = True
    (kitdir / "data" / "scoring" / "scorecard.json").write_text(json.dumps(sc))
    hydrate(kitdir, 1)
    _, res = run(kitdir, "score", "--seat", "lab0001@zava.example")
    assert res["score"] == 0


def test_integrity_failure_marks_seat_failed(kitdir):
    run(kitdir, "tenant")
    run(kitdir, "seats", "--count", "1")
    seat = state(kitdir)["seats"]["lab0001@zava.example"]
    t = fake(kitdir)
    t.simulate_drive_file(seat["id"], "Skill-Inventory.docx", b"x")
    t.save()
    code, body = run(kitdir, "check")
    assert code == 2 and body["failed"] == 1
    assert "integrity" in " ".join(body["seats"]["lab0001@zava.example"]["reasons"])
    assert json.loads((kitdir / "out" / "seat-inventory.json").read_text()) == []


def test_missing_content_fails_check(kitdir):
    run(kitdir, "tenant")
    run(kitdir, "seats", "--count", "1")
    seat = state(kitdir)["seats"]["lab0001@zava.example"]
    t = fake(kitdir)
    ev = next(e for e in t.events[seat["id"]] if e["subject"] == "Helix price decision")
    t.events[seat["id"]].remove(ev)
    t.save()
    code, body = run(kitdir, "check")
    reasons = " ".join(body["seats"]["lab0001@zava.example"]["reasons"])
    assert body["failed"] == 1 and "calendar" in reasons and "F4" in reasons


def test_resume_after_interruption(kitdir, monkeypatch):
    run(kitdir, "tenant")
    from vs_hydrate.ops import seats as seats_mod
    calls = {"n": 0}
    orig = seats_mod.SeatWriter.p_calendar

    def flaky(self):
        calls["n"] += 1
        if calls["n"] == 1:
            from vs_hydrate.api.base import TenantError
            raise TenantError("simulated throttling", status=503, transient=True)
        return orig(self)
    monkeypatch.setattr(seats_mod.SeatWriter, "p_calendar", flaky)
    code, body = run(kitdir, "seats", "--count", "2", "--concurrency", "1")
    assert code == 2 and len(body["pending"]) == 1
    code, body = run(kitdir, "seats", "--count", "2")
    assert code == 0 and body["resumed"] is True and body["hydrated"] == 1
    st = state(kitdir)
    assert len(st["seats"]) == 2, "re-running must not create extra seats"
    t = fake(kitdir)
    for s in st["seats"].values():
        inbox = [m for m in t.mail[s["id"]] if m["folder"] == "inbox"]
        assert len(inbox) == 35, "no duplicate mail after resume"


def test_too_early_to_hydrate(kitdir):
    from datetime import date, timedelta as td
    cfg = (kitdir / "tenant.yaml").read_text().replace("lab_day: auto", f"lab_day: {(date.today() + td(days=5)).isoformat()}")
    (kitdir / "tenant.yaml").write_text(cfg)
    run(kitdir, "tenant")
    code, body = run(kitdir, "seats", "--count", "1")
    assert code == 3 and "too early" in body["error"]
    assert "seats" not in state(kitdir) or not state(kitdir)["seats"]


def test_dry_run_writes_nothing(kitdir):
    run(kitdir, "tenant")
    code, body = run(kitdir, "seats", "--count", "2", "--dry-run")
    assert code == 0 and body["planned_write_count"] > 100
    assert not state(kitdir)["seats"]
    assert not fake(kitdir).list_users_with_prefix("lab", "zava.example")


def test_retire_used_and_inventory(kitdir):
    hydrate(kitdir, 2)
    run(kitdir, "score", "--seat", "lab0001@zava.example")
    code, body = run(kitdir, "retire", "--used")
    assert code == 0 and body["retired"] == ["lab0001@zava.example"]
    t = fake(kitdir)
    assert t.get_user("lab0001@zava.example") is None
    assert t.get_user("lab0002@zava.example") is not None
    assert t.get_user("elena.marsh@zava.example") is not None, "personas are never retired"
    inv = json.loads((kitdir / "out" / "seat-inventory.json").read_text())
    assert [s["upn"] for s in inv] == ["lab0002@zava.example"]
    org = state(kitdir)["tenant"]["personas"]["elena"]
    assert all(e["isCancelled"] or "lab0001" not in json.dumps(e) for e in t.events[org])
    code, body = run(kitdir, "seats", "--count", "1")
    assert code == 0 and body["seats"][0]["upn"] == "lab0003@zava.example", "retired numbers are not reused"


def test_bad_config_exits_3(kitdir):
    (kitdir / "tenant.yaml").write_text("tenant: {}\n")
    code, body = run(kitdir, "validate")
    assert code == 3


def test_missing_permission_fails_validate(kitdir):
    run(kitdir, "tenant")
    t = fake(kitdir)
    t.roles.discard("Teamwork.Migrate.All")
    t.save()
    code, body = run(kitdir, "validate")
    perm = next(c for c in body["checks"] if c["check"] == "app permissions")
    assert code == 1 and "Teamwork.Migrate.All" in perm["detail"]
