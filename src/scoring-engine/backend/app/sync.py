"""Organiser-initiated sync: score every lab account straight from Microsoft 365, no partner call needed.

Each run records a watermark (`watermark_to`): evidence up to that instant has been scanned. The next run
is a delta over scoring state: steps already complete are never re-scanned, participants who finished
everything are skipped, and only open steps are re-checked. Open steps are always evaluated over the whole
lab window rather than only "since the watermark", because a step can need evidence from both sides of
it (for example a file before the last sync and the email after). Completions found by a sync are timed
by the evidence itself (when the participant did the work), not by when the sync ran.
"""
import asyncio
import csv
import io
import logging
from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import notifier
from app.config import get_settings
from app.db import SessionLocal, utcnow
from app.engine import MAX_TRANSIENT_ATTEMPTS, evaluate
from app.graph import get_source
from app.models import Event, Participant, Step, StepProgress, Submission, SyncRun
from app.rubric import Rubric
from app.services import event_steps, recompute_progress

log = logging.getLogger("sync")


# ---------- roster ----------

def parse_roster_csv(text: str) -> list[dict[str, Any]]:
    """Columns (header row required): upn, first_name, last_name, email, external_id, lab_started_at."""
    reader = csv.DictReader(io.StringIO(text.strip()))
    rows = []
    for raw in reader:
        row = {(k or "").strip().lower(): (v or "").strip() for k, v in raw.items()}
        if "@" not in row.get("upn", ""):
            continue
        started = row.get("lab_started_at")
        rows.append({
            "upn": row["upn"], "first_name": row.get("first_name") or None, "last_name": row.get("last_name") or None,
            "email": row.get("email") or None, "external_id": row.get("external_id") or None,
            "lab_started_at": datetime.fromisoformat(started.replace("Z", "+00:00")) if started else None,
        })
    return rows


async def upsert_roster(session: AsyncSession, event: Event, rows: list[dict[str, Any]]) -> tuple[int, int]:
    """Create or update participants by lab account UPN. Returns (added, updated)."""
    existing = {(p.upn or "").lower(): p for p in (await session.execute(
        select(Participant).where(Participant.event_id == event.id))).scalars()}
    by_external = {p.external_id: p for p in existing.values()}
    added = updated = 0
    for r in rows:
        upn = r["upn"].strip()
        p = existing.get(upn.lower()) or (by_external.get(r["external_id"]) if r.get("external_id") else None)
        if p is None:
            p = Participant(event_id=event.id, external_id=r.get("external_id") or upn, upn=upn)
            session.add(p)
            existing[upn.lower()] = p
            added += 1
        else:
            updated += 1
            p.upn = upn
        for f in ("first_name", "last_name", "email"):
            if r.get(f):
                setattr(p, f, r[f])
        if r.get("lab_started_at") and (p.first_lab_started_at is None or r["lab_started_at"] < p.first_lab_started_at):
            p.first_lab_started_at = r["lab_started_at"]
    await session.flush()
    return added, updated


def _graph_user_row(u: dict[str, Any]) -> dict[str, Any]:
    return {"upn": u["userPrincipalName"], "first_name": u.get("givenName"), "last_name": u.get("surname"),
            "email": u.get("mail"), "external_id": None, "lab_started_at": None}


# ---------- run ----------

async def claim_run() -> str | None:
    async with SessionLocal() as session:
        run = (await session.execute(select(SyncRun).where(SyncRun.status == "queued")
                                     .order_by(SyncRun.created_at).limit(1)
                                     .with_for_update(skip_locked=True))).scalar_one_or_none()
        if run is None:
            return None
        run.status, run.started_at = "running", utcnow()
        await session.commit()
        return run.id


async def execute(run_id: str) -> None:
    try:
        await _execute(run_id)
    except Exception as exc:  # never leave a run stuck in "running"
        log.exception("sync %s failed", run_id)
        async with SessionLocal() as session:
            run = await session.get(SyncRun, run_id)
            run.status, run.finished_at, run.error_detail = "failed", utcnow(), f"{type(exc).__name__}: {exc}"[:2000]
            await notifier.publish(session, run.event_id, "sync")
            await session.commit()


async def _execute(run_id: str) -> None:
    source = get_source()
    async with SessionLocal() as session:
        run = await session.get(SyncRun, run_id)
        event = await session.get(Event, run.event_id)
        run.watermark_from = event.last_synced_at
        run.watermark_to = utcnow()

        # 1. Roster: pick up lab accounts from the event's Entra group (or the mock tenant).
        roster = await source.roster(event.roster_group_id)
        if roster:
            added, _ = await upsert_roster(session, event, [_graph_user_row(u) for u in roster
                                                            if u.get("userPrincipalName")])
            run.participants_added = added

        # 2. Delta: only participant/step pairs that are not complete yet.
        steps = [s for _, s in await event_steps(session, event.id) if (s.rubric_json or {}).get("checks")]
        participants = (await session.execute(select(Participant).where(
            Participant.event_id == event.id, Participant.upn.is_not(None)))).scalars().all()
        done = {(pr.participant_id, pr.step_id) for pr in (await session.execute(
            select(StepProgress).where(StepProgress.event_id == event.id, StepProgress.status == "complete"))).scalars()}
        pairs = [(p, s) for p in participants for s in steps if (p.id, s.id) not in done]
        run.participants_total = len(participants)
        run.steps_skipped = len(participants) * len(steps) - len(pairs)
        # Accounts with no lab start of their own (roster/Entra group) are timed from the event start.
        event_start = event.starts_at or event.created_at
        for p in participants:
            if p.first_lab_started_at is None:
                p.first_lab_started_at = event_start
        await notifier.publish(session, event.id, "sync")
        await session.commit()
        p_ids = [p.id for p in participants]
        upns = {p.id: p.upn for p in participants}
        starts = {p.id: p.first_lab_started_at or event_start for p in participants}
        step_list = [(s.id, s.use_case_id, s.rubric_version, Rubric.model_validate(s.rubric_json)) for s in steps]

    pending_by_participant: dict[str, list] = {}
    for p, s in pairs:
        pending_by_participant.setdefault(p.id, []).append(next(x for x in step_list if x[0] == s.id))

    sem = asyncio.Semaphore(get_settings().worker_concurrency)
    counters = {"checked": 0, "completions": 0, "errors": 0, "scanned": 0}

    async def scan(pid: str) -> None:
        async with sem:
            for step_id, use_case_id, version, rubric in pending_by_participant.get(pid, []):
                now = utcnow()
                ev = await evaluate(rubric, source=source, upn=upns[pid], lab_started_at=starts[pid],
                                    received_at=now, attempts=MAX_TRANSIENT_ATTEMPTS, now=now, single_pass=True)
                counters["checked"] += 1
                if ev.status == "error":
                    counters["errors"] += 1
                    continue  # leave it open; the next sync retries
                async with SessionLocal() as session:
                    await _record(session, run_id, pid, step_id, use_case_id, version, starts[pid], ev)
                    if ev.status == "complete":
                        counters["completions"] += 1
                    await session.commit()
            counters["scanned"] += 1

    async def progress() -> None:
        while True:
            await asyncio.sleep(2)
            async with SessionLocal() as session:
                run = await session.get(SyncRun, run_id)
                run.participants_scanned = counters["scanned"]
                run.steps_checked, run.new_completions, run.errors = counters["checked"], counters["completions"], counters["errors"]
                await notifier.publish(session, run.event_id, "sync")
                await session.commit()

    ticker = asyncio.create_task(progress())
    try:
        await asyncio.gather(*(scan(pid) for pid in p_ids))
    finally:
        ticker.cancel()

    async with SessionLocal() as session:
        run = await session.get(SyncRun, run_id)
        event = await session.get(Event, run.event_id)
        run.participants_scanned = len(p_ids)
        run.steps_checked, run.new_completions, run.errors = counters["checked"], counters["completions"], counters["errors"]
        run.status = "completed_with_errors" if counters["errors"] else "completed"
        run.finished_at = utcnow()
        event.last_synced_at = run.watermark_to
        await notifier.publish(session, event.id, "update")
        await session.commit()
    log.info("sync %s: %s", run_id, counters)


async def _record(session: AsyncSession, run_id: str, participant_id: str, step_id: str, use_case_id: str,
                  rubric_version: int, lab_started_at: datetime, ev) -> None:
    """One sync submission per participant/step, updated in place until the step completes."""
    key = f"sync:{participant_id}:{step_id}"
    sub = (await session.execute(select(Submission).where(
        Submission.integration_id.is_(None), Submission.idempotency_key == key))).scalar_one_or_none()
    now = utcnow()
    if sub is None:
        participant = await session.get(Participant, participant_id)
        sub = Submission(event_id=participant.event_id, use_case_id=use_case_id, step_id=step_id,
                         participant_id=participant_id, integration_id=None, idempotency_key=key, source="sync",
                         lab_profile_id="sync", lab_instance_id=run_id, lab_started_at=lab_started_at,
                         submitted_at=now, received_at=now, rubric_version=rubric_version, attempts=0)
        session.add(sub)
    sub.attempts += 1
    sub.status, sub.reasons, sub.check_results = ev.status, ev.reasons, ev.check_results
    sub.evaluated_at, sub.submitted_at, sub.lab_instance_id = now, now, run_id
    sub.evidence_at = ev.evidence_at
    sub.verification_status = ev.verification_status if ev.status == "complete" else "not_required"
    sub.verification_checked_at = now if sub.verification_status == "pending" else None
    sub.next_attempt_at, sub.locked_at = now, None
    await session.flush()
    await recompute_progress(session, participant_id, step_id, sub.event_id)


async def active_run(session: AsyncSession, event_id: str) -> SyncRun | None:
    return (await session.execute(select(SyncRun).where(
        SyncRun.event_id == event_id, SyncRun.status.in_(("queued", "running")))
        .order_by(SyncRun.created_at.desc()).limit(1))).scalar_one_or_none()


async def run_count(session: AsyncSession, event_id: str) -> int:
    return (await session.execute(select(func.count()).where(SyncRun.event_id == event_id))).scalar_one()
