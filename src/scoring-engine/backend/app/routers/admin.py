"""Admin portal API (Entra ID or local auth)."""
import csv
import io
import re
import secrets
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import StreamingResponse
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app import notifier, sync
from app.checks import catalogue
from app.db import get_session, utcnow
from app.graph import get_source
from app.models import (AuditLog, Event, Integration, Participant, Step, Submission, SyncRun, UseCase,
                        WebhookDelivery)
from app.rubric import RubricError, parse_rubric
from app.security import Admin, generate_client_id, generate_client_secret, hash_secret, require_admin
from app.services import audit, leaderboard, load_bundle, overview, recompute_progress, vendor_view

router = APIRouter(prefix="/api/admin", tags=["Admin"])
SLUG = re.compile(r"^[a-z0-9][a-z0-9\-]{1,78}$")
CODE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_\-\.]{0,79}$")


@router.get("/me")
async def me(admin: Admin = Depends(require_admin)):
    return {"username": admin.username, "name": admin.name}


@router.get("/overview")
async def get_overview(_: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    data = await overview(session)
    recent = (await session.execute(select(Submission.id).order_by(Submission.received_at.desc()).limit(8))).scalars().all()
    data["recent"] = [_submission_row(await load_bundle(session, sid)) for sid in recent]
    return data


# ---------- integrations ----------

def _integration_out(i: Integration) -> dict:
    return {"id": i.id, "name": i.name, "vendor": i.vendor, "client_id": i.client_id,
            "secret_hint": i.secret_hint, "status": i.status, "webhook_url": i.webhook_url,
            "has_webhook_secret": bool(i.webhook_secret), "created_at": i.created_at.isoformat(),
            "secret_rotated_at": i.secret_rotated_at.isoformat(),
            "last_used_at": i.last_used_at.isoformat() if i.last_used_at else None}


class IntegrationIn(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    vendor: str = Field(min_length=2, max_length=200)
    webhook_url: str | None = None


class IntegrationPatch(BaseModel):
    name: str | None = None
    vendor: str | None = None
    webhook_url: str | None = None


def _check_webhook(url: str | None) -> None:
    if url and not url.startswith(("https://", "http://localhost", "http://host.docker.internal")):
        raise HTTPException(422, "webhook_url must be https")


@router.get("/integrations")
async def list_integrations(_: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(Integration).order_by(Integration.created_at.desc()))).scalars().all()
    usage = dict((await session.execute(
        select(Submission.integration_id, func.count()).group_by(Submission.integration_id))).all())
    return [{**_integration_out(i), "submissions": usage.get(i.id, 0)} for i in rows]


@router.post("/integrations", status_code=201)
async def create_integration(body: IntegrationIn, admin: Admin = Depends(require_admin),
                             session: AsyncSession = Depends(get_session)):
    _check_webhook(body.webhook_url)
    secret = generate_client_secret()
    webhook_secret = "whsec_" + secrets.token_urlsafe(24)
    i = Integration(name=body.name, vendor=body.vendor, client_id=generate_client_id(), secret_hash=hash_secret(secret),
                    secret_hint=secret[-4:], webhook_url=body.webhook_url, webhook_secret=webhook_secret)
    session.add(i)
    await session.flush()
    await audit(session, admin.username, "integration.created", "integration", i.id, name=i.name)
    await session.commit()
    return {**_integration_out(i), "client_secret": secret, "webhook_secret": webhook_secret}


@router.patch("/integrations/{integration_id}")
async def update_integration(integration_id: str, body: IntegrationPatch, admin: Admin = Depends(require_admin),
                             session: AsyncSession = Depends(get_session)):
    i = await _get(session, Integration, integration_id)
    _check_webhook(body.webhook_url)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(i, k, (v or None) if k == "webhook_url" else v)
    await audit(session, admin.username, "integration.updated", "integration", i.id, **body.model_dump(exclude_unset=True))
    await session.commit()
    return _integration_out(i)


@router.post("/integrations/{integration_id}/rotate-secret")
async def rotate_secret(integration_id: str, admin: Admin = Depends(require_admin),
                        session: AsyncSession = Depends(get_session)):
    i = await _get(session, Integration, integration_id)
    secret = generate_client_secret()
    i.secret_hash, i.secret_hint, i.secret_rotated_at = hash_secret(secret), secret[-4:], utcnow()
    await audit(session, admin.username, "integration.secret_rotated", "integration", i.id)
    await session.commit()
    return {**_integration_out(i), "client_secret": secret}


@router.post("/integrations/{integration_id}/rotate-webhook-secret")
async def rotate_webhook_secret(integration_id: str, admin: Admin = Depends(require_admin),
                                session: AsyncSession = Depends(get_session)):
    i = await _get(session, Integration, integration_id)
    i.webhook_secret = "whsec_" + secrets.token_urlsafe(24)
    await audit(session, admin.username, "integration.webhook_secret_rotated", "integration", i.id)
    await session.commit()
    return {**_integration_out(i), "webhook_secret": i.webhook_secret}


@router.post("/integrations/{integration_id}/status")
async def set_integration_status(integration_id: str, status: Literal["active", "revoked"] = Query(...),
                                 admin: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    i = await _get(session, Integration, integration_id)
    i.status = status
    if status == "active":
        i.secret_rotated_at = utcnow()  # tokens minted before a revoke never come back to life
    await audit(session, admin.username, f"integration.{status}", "integration", i.id)
    await session.commit()
    return _integration_out(i)


@router.get("/integrations/{integration_id}/webhooks")
async def list_webhooks(integration_id: str, _: Admin = Depends(require_admin),
                        session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(WebhookDelivery).where(WebhookDelivery.integration_id == integration_id)
                                  .order_by(WebhookDelivery.created_at.desc()).limit(50))).scalars().all()
    return [{"id": w.id, "submission_id": w.submission_id, "status": w.status, "attempts": w.attempts,
             "last_error": w.last_error, "created_at": w.created_at.isoformat(),
             "delivered_at": w.delivered_at.isoformat() if w.delivered_at else None} for w in rows]


# ---------- events / use cases / steps ----------

class EventIn(BaseModel):
    slug: str
    name: str = Field(min_length=2, max_length=200)
    description: str | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    status: Literal["draft", "live", "closed"] = "draft"
    public_leaderboard: bool = True
    public_name_format: Literal["full", "first_last_initial", "first_only"] = "first_last_initial"
    public_show_reasons: bool = True


class EventPatch(BaseModel):
    name: str | None = None
    description: str | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    status: Literal["draft", "live", "closed"] | None = None
    public_leaderboard: bool | None = None
    public_name_format: Literal["full", "first_last_initial", "first_only"] | None = None
    public_show_reasons: bool | None = None
    roster_group_id: str | None = None


def _event_out(e: Event, **extra) -> dict:
    return {"id": e.id, "slug": e.slug, "name": e.name, "description": e.description,
            "starts_at": e.starts_at.isoformat() if e.starts_at else None,
            "ends_at": e.ends_at.isoformat() if e.ends_at else None, "status": e.status,
            "public_leaderboard": e.public_leaderboard, "public_name_format": e.public_name_format,
            "public_show_reasons": e.public_show_reasons, "roster_group_id": e.roster_group_id,
            "last_synced_at": e.last_synced_at.isoformat() if e.last_synced_at else None,
            "created_at": e.created_at.isoformat(), **extra}


def _step_out(s: Step) -> dict:
    return {"id": s.id, "use_case_id": s.use_case_id, "code": s.code, "title": s.title, "description": s.description,
            "sort_order": s.sort_order, "rubric_yaml": s.rubric_yaml, "rubric_version": s.rubric_version,
            "check_count": len(s.rubric_json.get("checks", [])), "updated_at": s.updated_at.isoformat()}


@router.get("/events")
async def list_events(_: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    events = (await session.execute(select(Event).order_by(Event.created_at.desc()))).scalars().all()
    pcount = dict((await session.execute(select(Participant.event_id, func.count()).group_by(Participant.event_id))).all())
    scount = dict((await session.execute(select(Submission.event_id, func.count()).group_by(Submission.event_id))).all())
    return [_event_out(e, participants=pcount.get(e.id, 0), submissions=scount.get(e.id, 0)) for e in events]


@router.post("/events", status_code=201)
async def create_event(body: EventIn, admin: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    if not SLUG.match(body.slug):
        raise HTTPException(422, "slug: lowercase letters, digits and dashes only")
    e = Event(**body.model_dump())
    session.add(e)
    try:
        await session.flush()
    except IntegrityError:
        raise HTTPException(409, f"An event with slug '{body.slug}' already exists")
    await audit(session, admin.username, "event.created", "event", e.id, slug=e.slug)
    await session.commit()
    return _event_out(e)


@router.get("/events/{event_id}")
async def get_event(event_id: str, _: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    e = await _get(session, Event, event_id)
    ucs = (await session.execute(select(UseCase).where(UseCase.event_id == e.id)
                                 .order_by(UseCase.sort_order, UseCase.code))).scalars().all()
    steps = (await session.execute(select(Step).where(Step.use_case_id.in_([u.id for u in ucs]))
                                   .order_by(Step.sort_order, Step.code))).scalars().all() if ucs else []
    return _event_out(e, use_cases=[
        {"id": u.id, "code": u.code, "title": u.title, "description": u.description, "sort_order": u.sort_order,
         "steps": [_step_out(s) for s in steps if s.use_case_id == u.id]} for u in ucs])


@router.patch("/events/{event_id}")
async def update_event(event_id: str, body: EventPatch, admin: Admin = Depends(require_admin),
                       session: AsyncSession = Depends(get_session)):
    e = await _get(session, Event, event_id)
    changes = body.model_dump(exclude_unset=True)
    for k, v in changes.items():
        setattr(e, k, v)
    await audit(session, admin.username, "event.updated", "event", e.id, **{k: str(v) for k, v in changes.items()})
    await notifier.publish(session, e.id)
    await session.commit()
    return _event_out(e)


@router.delete("/events/{event_id}", status_code=204)
async def delete_event(event_id: str, admin: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    e = await _get(session, Event, event_id)
    await session.delete(e)
    await audit(session, admin.username, "event.deleted", "event", event_id, slug=e.slug)
    await session.commit()


class UseCaseIn(BaseModel):
    code: str
    title: str = Field(min_length=2, max_length=200)
    description: str | None = None
    sort_order: int = 0


@router.post("/events/{event_id}/use-cases", status_code=201)
async def create_use_case(event_id: str, body: UseCaseIn, admin: Admin = Depends(require_admin),
                          session: AsyncSession = Depends(get_session)):
    await _get(session, Event, event_id)
    if not CODE.match(body.code):
        raise HTTPException(422, "code: letters, digits, dash, underscore, dot")
    u = UseCase(event_id=event_id, **body.model_dump())
    session.add(u)
    try:
        await session.flush()
    except IntegrityError:
        raise HTTPException(409, f"Use case '{body.code}' already exists in this event")
    await audit(session, admin.username, "use_case.created", "use_case", u.id, code=u.code)
    await session.commit()
    return {"id": u.id, "code": u.code, "title": u.title, "description": u.description, "sort_order": u.sort_order}


@router.patch("/use-cases/{use_case_id}")
async def update_use_case(use_case_id: str, body: UseCaseIn, admin: Admin = Depends(require_admin),
                          session: AsyncSession = Depends(get_session)):
    u = await _get(session, UseCase, use_case_id)
    u.title, u.description, u.sort_order = body.title, body.description, body.sort_order
    await audit(session, admin.username, "use_case.updated", "use_case", u.id)
    await session.commit()
    return {"id": u.id, "code": u.code, "title": u.title, "description": u.description, "sort_order": u.sort_order}


@router.delete("/use-cases/{use_case_id}", status_code=204)
async def delete_use_case(use_case_id: str, admin: Admin = Depends(require_admin),
                          session: AsyncSession = Depends(get_session)):
    u = await _get(session, UseCase, use_case_id)
    await session.delete(u)
    await audit(session, admin.username, "use_case.deleted", "use_case", use_case_id)
    await session.commit()


class StepIn(BaseModel):
    code: str
    title: str = Field(min_length=2, max_length=200)
    description: str | None = None
    sort_order: int = 0
    rubric_yaml: str = ""


class StepPatch(BaseModel):
    title: str | None = None
    description: str | None = None
    sort_order: int | None = None
    rubric_yaml: str | None = None


def _validated(yaml_text: str) -> dict:
    try:
        return parse_rubric(yaml_text).model_dump()
    except RubricError as exc:
        raise HTTPException(422, {"message": "Rubric is invalid", "errors": exc.errors})


@router.post("/use-cases/{use_case_id}/steps", status_code=201)
async def create_step(use_case_id: str, body: StepIn, admin: Admin = Depends(require_admin),
                      session: AsyncSession = Depends(get_session)):
    await _get(session, UseCase, use_case_id)
    if not CODE.match(body.code):
        raise HTTPException(422, "code: letters, digits, dash, underscore, dot")
    rubric = _validated(body.rubric_yaml) if body.rubric_yaml.strip() else {"checks": []}
    s = Step(use_case_id=use_case_id, code=body.code, title=body.title, description=body.description,
             sort_order=body.sort_order, rubric_yaml=body.rubric_yaml, rubric_json=rubric)
    session.add(s)
    try:
        await session.flush()
    except IntegrityError:
        raise HTTPException(409, f"Step '{body.code}' already exists in this use case")
    await audit(session, admin.username, "step.created", "step", s.id, code=s.code)
    await session.commit()
    return _step_out(s)


@router.patch("/steps/{step_id}")
async def update_step(step_id: str, body: StepPatch, admin: Admin = Depends(require_admin),
                      session: AsyncSession = Depends(get_session)):
    s = await _get(session, Step, step_id)
    changes = body.model_dump(exclude_unset=True)
    if "rubric_yaml" in changes and changes["rubric_yaml"] != s.rubric_yaml:
        s.rubric_json = _validated(changes["rubric_yaml"])
        s.rubric_version += 1
    for k, v in changes.items():
        setattr(s, k, v)
    await audit(session, admin.username, "step.updated", "step", s.id, version=s.rubric_version)
    await session.commit()
    return _step_out(s)


@router.delete("/steps/{step_id}", status_code=204)
async def delete_step(step_id: str, admin: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    s = await _get(session, Step, step_id)
    await session.delete(s)
    await audit(session, admin.username, "step.deleted", "step", step_id)
    await session.commit()


class RubricIn(BaseModel):
    rubric_yaml: str


@router.post("/rubrics/validate")
async def validate_rubric(body: RubricIn, _: Admin = Depends(require_admin)):
    try:
        rubric = parse_rubric(body.rubric_yaml)
    except RubricError as exc:
        return {"valid": False, "errors": exc.errors}
    return {"valid": True, "errors": [], "checks": [c.model_dump() for c in rubric.checks]}


@router.get("/check-types")
async def check_types(_: Admin = Depends(require_admin)):
    return catalogue()


# ---------- submissions ----------

def _submission_row(b) -> dict:
    s = b.submission
    return {"id": s.id, "status": s.status, "event_id": b.event.id, "event_slug": b.event.slug,
            "use_case": b.use_case.code, "step": b.step.code, "step_title": b.step.title,
            "participant": f"{b.participant.first_name or ''} {b.participant.last_name or ''}".strip()
            or b.participant.external_id, "participant_id": b.participant.id,
            "external_id": b.participant.external_id, "upn": b.participant.upn,
            "received_at": s.received_at.isoformat(), "evaluated_at": s.evaluated_at.isoformat() if s.evaluated_at else None,
            "reasons": s.reasons, "attempts": s.attempts, "verification_status": s.verification_status,
            "override_by": s.override_by, "source": s.source,
            "evidence_at": s.evidence_at.isoformat() if s.evidence_at else None}


@router.get("/events/{event_id}/submissions")
async def list_submissions(event_id: str, status: str | None = None, q: str | None = None,
                           participant_id: str | None = None,
                           limit: int = Query(50, le=500), offset: int = 0, _: Admin = Depends(require_admin),
                           session: AsyncSession = Depends(get_session)):
    stmt = select(Submission.id).join(Participant, Participant.id == Submission.participant_id).where(
        Submission.event_id == event_id)
    if participant_id:
        stmt = stmt.where(Submission.participant_id == participant_id)
    if status:
        stmt = stmt.where(Submission.status == status)
    if q:
        like = f"%{q.lower()}%"
        stmt = stmt.where(or_(func.lower(Participant.first_name).like(like), func.lower(Participant.last_name).like(like),
                              func.lower(Participant.upn).like(like), func.lower(Participant.external_id).like(like)))
    total = (await session.execute(select(func.count()).select_from(stmt.subquery()))).scalar_one()
    ids = (await session.execute(stmt.order_by(Submission.received_at.desc()).limit(limit).offset(offset))).scalars().all()
    return {"total": total, "items": [_submission_row(await load_bundle(session, i)) for i in ids]}


@router.get("/submissions/{submission_id}")
async def get_submission(submission_id: str, _: Admin = Depends(require_admin),
                         session: AsyncSession = Depends(get_session)):
    b = await load_bundle(session, submission_id)
    if b is None:
        raise HTTPException(404)
    s = b.submission
    return {**_submission_row(b), "check_results": s.check_results, "lab_profile_id": s.lab_profile_id,
            "lab_instance_id": s.lab_instance_id, "lab_started_at": s.lab_started_at.isoformat(),
            "submitted_at": s.submitted_at.isoformat(), "rubric_version": s.rubric_version,
            "override_note": s.override_note, "vendor_view": vendor_view(b)}


@router.post("/submissions/{submission_id}/reevaluate")
async def reevaluate(submission_id: str, admin: Admin = Depends(require_admin),
                     session: AsyncSession = Depends(get_session)):
    s = await _get(session, Submission, submission_id)
    s.status, s.attempts, s.next_attempt_at, s.locked_at = "queued", 0, utcnow(), None
    s.received_at = utcnow()  # restart any retry window from now
    s.override_by = s.override_note = None
    await audit(session, admin.username, "submission.reevaluated", "submission", s.id)
    await session.commit()
    return {"ok": True}


class OverrideIn(BaseModel):
    status: Literal["complete", "incomplete"]
    note: str = Field(min_length=3, max_length=1000)


@router.post("/submissions/{submission_id}/override")
async def override(submission_id: str, body: OverrideIn, admin: Admin = Depends(require_admin),
                   session: AsyncSession = Depends(get_session)):
    s = await _get(session, Submission, submission_id)
    s.status, s.override_by, s.override_note, s.evaluated_at = body.status, admin.username, body.note, utcnow()
    s.reasons = [] if body.status == "complete" else [{"check": "manual_review", "message": body.note}]
    s.verification_status = "not_required"
    await session.flush()
    await recompute_progress(session, s.participant_id, s.step_id, s.event_id)
    await audit(session, admin.username, "submission.override", "submission", s.id, status=body.status, note=body.note)
    await notifier.publish(session, s.event_id)
    await session.commit()
    return {"ok": True}


# ---------- leaderboard + export ----------

@router.get("/events/{event_id}/leaderboard")
async def admin_leaderboard(event_id: str, q: str | None = None, _: Admin = Depends(require_admin),
                            session: AsyncSession = Depends(get_session)):
    return await leaderboard(session, await _get(session, Event, event_id), public=False, query=q)


@router.get("/events/{event_id}/leaderboard/export")
async def export_leaderboard(event_id: str, format: Literal["csv", "xlsx"] = "csv",
                             admin: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    event = await _get(session, Event, event_id)
    board = await leaderboard(session, event, public=False)
    step_cols = [(s["id"], f"{s['use_case_code']}/{s['code']}") for s in board["steps"]]
    header = ["Rank", "First name", "Last name", "Email", "Lab account (UPN)", "External ID", "Completed steps",
              "Total steps", "Attempts", "Elapsed (min)", "Last completed (UTC)"] + [c for _, c in step_cols]
    rows = [[r["rank"] or "", r["first_name"] or "", r["last_name"] or "", r["email"] or "", r["upn"] or "",
             r["external_id"], r["completed_steps"], r["total_steps"], r["attempts"],
             round(r["elapsed_seconds"] / 60, 1) if r["elapsed_seconds"] is not None else "",
             r["last_completed_at"] or ""] + [r["steps"][sid] for sid, _ in step_cols] for r in board["rows"]]
    await audit(session, admin.username, "leaderboard.exported", "event", event.id, format=format)
    await session.commit()
    stamp = utcnow().strftime("%Y%m%d-%H%M")
    filename = f"{event.slug}-leaderboard-{stamp}.{format}"
    headers = {"Content-Disposition": f'attachment; filename="{filename}"'}
    if format == "csv":
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(header)
        writer.writerows(rows)
        return StreamingResponse(iter([buf.getvalue().encode("utf-8-sig")]), media_type="text/csv", headers=headers)
    wb = Workbook()
    ws = wb.active
    ws.title = "Leaderboard"
    ws.append(header)
    for cell in ws[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="1F2A44")
    for row in rows:
        ws.append(row)
    for col in ws.columns:
        ws.column_dimensions[col[0].column_letter].width = min(max(len(str(c.value or "")) for c in col) + 2, 40)
    ws.freeze_panes = "A2"
    buf = io.BytesIO()
    wb.save(buf)
    return StreamingResponse(iter([buf.getvalue()]), headers=headers,
                             media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")


# ---------- Microsoft 365 sync + roster ----------

def _run_out(r: SyncRun) -> dict:
    iso = lambda d: d.isoformat() if d else None  # noqa: E731
    return {"id": r.id, "status": r.status, "triggered_by": r.triggered_by, "watermark_from": iso(r.watermark_from),
            "watermark_to": iso(r.watermark_to), "participants_total": r.participants_total,
            "participants_scanned": r.participants_scanned, "participants_added": r.participants_added,
            "steps_checked": r.steps_checked, "steps_skipped": r.steps_skipped, "new_completions": r.new_completions,
            "errors": r.errors, "error_detail": r.error_detail, "created_at": iso(r.created_at),
            "started_at": iso(r.started_at), "finished_at": iso(r.finished_at)}


@router.post("/events/{event_id}/sync", status_code=202)
async def start_sync(event_id: str, admin: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    event = await _get(session, Event, event_id)
    if await sync.active_run(session, event.id):
        raise HTTPException(409, "A sync is already running for this event")
    run = SyncRun(event_id=event.id, triggered_by=admin.username)
    session.add(run)
    await session.flush()
    await audit(session, admin.username, "event.sync_started", "event", event.id, run_id=run.id)
    await notifier.publish(session, event.id, "sync")
    await session.commit()
    return _run_out(run)


@router.get("/events/{event_id}/sync-runs")
async def list_sync_runs(event_id: str, _: Admin = Depends(require_admin), session: AsyncSession = Depends(get_session)):
    event = await _get(session, Event, event_id)
    runs = (await session.execute(select(SyncRun).where(SyncRun.event_id == event_id)
                                  .order_by(SyncRun.created_at.desc()).limit(10))).scalars().all()
    return {"last_synced_at": event.last_synced_at.isoformat() if event.last_synced_at else None,
            "runs": [_run_out(r) for r in runs]}


class RosterIn(BaseModel):
    csv: str = Field(min_length=5)


@router.post("/events/{event_id}/roster")
async def import_roster(event_id: str, body: RosterIn, admin: Admin = Depends(require_admin),
                        session: AsyncSession = Depends(get_session)):
    event = await _get(session, Event, event_id)
    try:
        rows = sync.parse_roster_csv(body.csv)
    except (ValueError, KeyError) as exc:
        raise HTTPException(422, f"Could not read the CSV: {exc}")
    if not rows:
        raise HTTPException(422, "No rows with a valid upn column were found")
    added, updated = await sync.upsert_roster(session, event, rows)
    await audit(session, admin.username, "event.roster_imported", "event", event.id, added=added, updated=updated)
    await notifier.publish(session, event.id)
    await session.commit()
    return {"added": added, "updated": updated, "rows": len(rows)}


# ---------- system ----------

@router.get("/graph/status")
async def graph_status(_: Admin = Depends(require_admin)):
    try:
        return {"ok": True, **(await get_source().status())}
    except Exception as exc:
        return {"ok": False, "error": str(exc)}


@router.get("/audit")
async def audit_log(limit: int = Query(100, le=500), _: Admin = Depends(require_admin),
                    session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(AuditLog).order_by(AuditLog.created_at.desc()).limit(limit))).scalars().all()
    return [{"id": a.id, "actor": a.actor, "action": a.action, "target_type": a.target_type, "target_id": a.target_id,
             "details": a.details, "created_at": a.created_at.isoformat()} for a in rows]


async def _get(session: AsyncSession, model, obj_id: str):
    obj = await session.get(model, obj_id)
    if obj is None:
        raise HTTPException(404, f"{model.__name__} not found")
    return obj
