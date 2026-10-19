"""Shared persistence logic used by the API and the worker."""
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import notifier
from app.config import get_settings
from app.db import utcnow
from app.engine import Evaluation
from app.models import (AuditLog, Event, Integration, Participant, Step, StepProgress, Submission, UseCase,
                        WebhookDelivery)

VENDOR_STATUS = {"queued": "evaluating", "evaluating": "evaluating", "complete": "complete",
                 "incomplete": "incomplete", "error": "error"}


@dataclass
class Bundle:
    submission: Submission
    event: Event
    use_case: UseCase
    step: Step
    participant: Participant


async def load_bundle(session: AsyncSession, submission_id: str) -> Bundle | None:
    row = (await session.execute(
        select(Submission, Event, UseCase, Step, Participant)
        .join(Event, Event.id == Submission.event_id)
        .join(UseCase, UseCase.id == Submission.use_case_id)
        .join(Step, Step.id == Submission.step_id)
        .join(Participant, Participant.id == Submission.participant_id)
        .where(Submission.id == submission_id)
    )).first()
    return Bundle(*row) if row else None


def vendor_view(b: Bundle) -> dict[str, Any]:
    s = b.submission
    status = VENDOR_STATUS[s.status]
    base = get_settings().public_base_url.rstrip("/")
    return {
        "submission_id": s.id,
        "event_id": b.event.slug,
        "use_case_id": b.use_case.code,
        "step_id": b.step.code,
        "participant_external_id": b.participant.external_id,
        "status": status,
        "completed": None if status == "evaluating" else status == "complete",
        "reasons": s.reasons or [],
        "verification": {"status": s.verification_status},
        "received_at": s.received_at.isoformat(),
        "evaluated_at": s.evaluated_at.isoformat() if s.evaluated_at else None,
        "links": {
            "self": f"{base}/v1/submissions/{s.id}",
            "participant_scorecard": f"{get_settings().scorecard_base_url.rstrip('/')}/{b.event.slug}",
        },
    }


async def audit(session: AsyncSession, actor: str, action: str, target_type: str | None = None,
                target_id: str | None = None, **details: Any) -> None:
    session.add(AuditLog(actor=actor, action=action, target_type=target_type, target_id=target_id, details=details))


async def recompute_progress(session: AsyncSession, participant_id: str, step_id: str, event_id: str) -> None:
    """Rebuild one step_progress row from all of its submissions. Complete is sticky: any complete wins."""
    subs = (await session.execute(
        select(Submission).where(Submission.participant_id == participant_id, Submission.step_id == step_id)
        .order_by(Submission.received_at)
    )).scalars().all()
    final = [s for s in subs if s.status in ("complete", "incomplete", "error")]
    progress = await session.get(StepProgress, (participant_id, step_id))
    if not final:
        if progress:
            await session.delete(progress)
        return
    completes = [s for s in final if s.status == "complete"]
    first_complete = min(completes, key=lambda s: (s.evidence_at if s.source == "sync" and s.evidence_at
                                                   else s.received_at)) if completes else None
    latest = final[-1]
    if progress is None:
        progress = StepProgress(participant_id=participant_id, step_id=step_id, event_id=event_id, status="incomplete")
        session.add(progress)
    progress.status = "complete" if first_complete else latest.status
    progress.attempts = len(final)
    progress.completed_at = None
    if first_complete:
        # A synced completion is timed by when the work was done; a partner click by when it was clicked.
        progress.completed_at = (first_complete.evidence_at if first_complete.source == "sync" and first_complete.evidence_at
                                 else first_complete.received_at)
    progress.last_submission_id = (first_complete or latest).id
    progress.verification_status = first_complete.verification_status if first_complete else "not_required"
    progress.updated_at = utcnow()


async def apply_evaluation(session: AsyncSession, sub: Submission, ev: Evaluation) -> None:
    now = utcnow()
    sub.check_results = ev.check_results
    sub.locked_at = None
    if not ev.final:
        sub.status = "evaluating"
        sub.next_attempt_at = datetime.fromtimestamp(now.timestamp() + ev.retry_in_seconds, tz=now.tzinfo)
        return
    sub.status = ev.status
    sub.reasons = ev.reasons
    sub.evaluated_at = now
    sub.verification_status = ev.verification_status if ev.status == "complete" else "not_required"
    if sub.verification_status == "pending":
        sub.verification_checked_at = now
    await session.flush()
    await recompute_progress(session, sub.participant_id, sub.step_id, sub.event_id)
    await enqueue_webhook(session, sub)
    await notifier.publish(session, sub.event_id)


async def enqueue_webhook(session: AsyncSession, sub: Submission) -> None:
    if not sub.integration_id:
        return
    integration = await session.get(Integration, sub.integration_id)
    if not integration or not integration.webhook_url or integration.status != "active":
        return
    bundle = await load_bundle(session, sub.id)
    payload = {"type": "submission.evaluated", "data": vendor_view(bundle)}
    session.add(WebhookDelivery(integration_id=integration.id, submission_id=sub.id,
                                url=integration.webhook_url, payload=payload))


# ---------- leaderboard ----------

def display_name(p: Participant, fmt: str) -> str:
    first = (p.first_name or "").strip()
    last = (p.last_name or "").strip()
    if not first and not last:
        return f"Participant {p.public_id[:4].upper()}"
    if fmt == "full":
        return f"{first} {last}".strip()
    if fmt == "first_only":
        return first or last
    return f"{first} {last[:1] + '.' if last else ''}".strip()


async def event_steps(session: AsyncSession, event_id: str) -> list[tuple[UseCase, Step]]:
    rows = (await session.execute(
        select(UseCase, Step).join(Step, Step.use_case_id == UseCase.id)
        .where(UseCase.event_id == event_id).order_by(UseCase.sort_order, UseCase.code, Step.sort_order, Step.code)
    )).all()
    return [(u, s) for u, s in rows]


async def leaderboard(session: AsyncSession, event: Event, *, public: bool, query: str | None = None) -> dict[str, Any]:
    steps = await event_steps(session, event.id)
    participants = (await session.execute(select(Participant).where(Participant.event_id == event.id))).scalars().all()
    progress = (await session.execute(select(StepProgress).where(StepProgress.event_id == event.id))).scalars().all()
    by_participant: dict[str, dict[str, StepProgress]] = {}
    for pr in progress:
        by_participant.setdefault(pr.participant_id, {})[pr.step_id] = pr

    rows = []
    for p in participants:
        mine = by_participant.get(p.id, {})
        completed = [pr for pr in mine.values() if pr.status == "complete"]
        last_done = max((pr.completed_at for pr in completed if pr.completed_at), default=None)
        elapsed = (last_done - p.first_lab_started_at).total_seconds() if last_done and p.first_lab_started_at else None
        row = {
            "public_id": p.public_id,
            "name": display_name(p, event.public_name_format if public else "full"),
            "completed_steps": len(completed),
            "total_steps": len(steps),
            "attempts": sum(pr.attempts for pr in mine.values()),
            "last_completed_at": last_done.isoformat() if last_done else None,
            "elapsed_seconds": int(elapsed) if elapsed is not None else None,
            "steps": {s.id: (mine[s.id].status if s.id in mine else "not_started") for _, s in steps},
            "verification": {s.id: mine[s.id].verification_status for _, s in steps if s.id in mine},
        }
        if not public:
            row.update(participant_id=p.id, external_id=p.external_id, email=p.email, upn=p.upn,
                       first_name=p.first_name, last_name=p.last_name,
                       lab_started_at=p.first_lab_started_at.isoformat() if p.first_lab_started_at else None)
        rows.append(row)

    # Fair across staggered lab starts: most steps first, then least time from lab start to last completion.
    big = float("inf")
    rows.sort(key=lambda r: (-r["completed_steps"], r["elapsed_seconds"] if r["elapsed_seconds"] is not None else big,
                             r["last_completed_at"] or "9999", r["attempts"], r["name"].lower()))
    rank, prev = 0, None
    for i, r in enumerate(rows, start=1):
        key = (r["completed_steps"], r["elapsed_seconds"])
        if key != prev:
            rank, prev = i, key
        r["rank"] = rank if r["completed_steps"] else None

    if query:
        q = query.lower().strip()
        rows = [r for r in rows if q in r["name"].lower()
                or (not public and q in " ".join(str(r.get(k) or "") for k in ("email", "upn", "external_id")).lower())]

    step_meta = []
    for u, s in steps:
        done = sum(1 for pr in progress if pr.step_id == s.id and pr.status == "complete")
        step_meta.append({"id": s.id, "code": s.code, "title": s.title, "use_case": u.title,
                          "use_case_code": u.code, "completed_count": done})
    return {
        "event": {"id": event.id, "slug": event.slug, "name": event.name, "status": event.status},
        "steps": step_meta,
        "participants_total": len(participants),
        "finished_total": sum(1 for r in rows if steps and r["completed_steps"] == len(steps)),
        "rows": rows,
        "generated_at": utcnow().isoformat(),
    }


async def overview(session: AsyncSession) -> dict[str, Any]:
    since = datetime.fromtimestamp(utcnow().timestamp() - 3600, tz=utcnow().tzinfo)
    counts = dict((await session.execute(select(Submission.status, func.count()).group_by(Submission.status))).all())
    last_hour = (await session.execute(select(func.count()).where(Submission.received_at >= since))).scalar_one()
    return {
        "events": (await session.execute(select(func.count()).select_from(Event))).scalar_one(),
        "live_events": (await session.execute(select(func.count()).where(Event.status == "live"))).scalar_one(),
        "integrations": (await session.execute(
            select(func.count()).where(Integration.status == "active"))).scalar_one(),
        "participants": (await session.execute(select(func.count()).select_from(Participant))).scalar_one(),
        "submissions": sum(counts.values()),
        "submissions_last_hour": last_hour,
        "by_status": {k: counts.get(k, 0) for k in ("queued", "evaluating", "complete", "incomplete", "error")},
        "pending_verification": (await session.execute(
            select(func.count()).where(Submission.verification_status == "pending"))).scalar_one(),
        "unverified": (await session.execute(
            select(func.count()).where(Submission.verification_status == "unverified"))).scalar_one(),
        "steps_without_rubric": sum(1 for r in (await session.execute(select(Step.rubric_json))).scalars()
                                    if not (r or {}).get("checks")),
        "integrations_never_used": (await session.execute(select(func.count()).where(
            Integration.status == "active", Integration.last_used_at.is_(None)))).scalar_one(),
        "webhooks_failed": (await session.execute(
            select(func.count()).where(WebhookDelivery.status == "failed"))).scalar_one(),
        "live_event_id": (await session.execute(select(Event.id).where(Event.status == "live")
                                                .order_by(Event.created_at.desc()).limit(1))).scalar_one_or_none(),
    }
