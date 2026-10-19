"""Lab partner API: the contract lab platforms integrate against."""
import asyncio
import base64
import hashlib
from datetime import datetime

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, EmailStr, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionLocal, get_session, utcnow
from app.models import Event, Integration, Participant, Step, StepProgress, Submission, UseCase
from app.security import authenticate_client, issue_vendor_token, require_vendor
from app.services import event_steps, load_bundle, vendor_view

router = APIRouter(tags=["Vendor API"])


# ---------- OAuth2 client credentials ----------

@router.post("/oauth/token", summary="Exchange client credentials for an access token")
async def token(request: Request, session: AsyncSession = Depends(get_session)):
    ctype = request.headers.get("content-type", "")
    data = dict(await request.form()) if "form" in ctype else (await request.json() if "json" in ctype else {})
    client_id, client_secret = data.get("client_id"), data.get("client_secret")
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("basic "):
        try:
            client_id, client_secret = base64.b64decode(auth[6:]).decode().split(":", 1)
        except (ValueError, UnicodeDecodeError):
            pass
    if data.get("grant_type", "client_credentials") != "client_credentials":
        raise HTTPException(400, {"error": "unsupported_grant_type"})
    if not client_id or not client_secret:
        raise HTTPException(400, {"error": "invalid_request", "error_description": "client_id and client_secret required"})
    integration = await authenticate_client(session, str(client_id), str(client_secret))
    if integration is None:
        raise HTTPException(401, {"error": "invalid_client"})
    access_token, ttl = issue_vendor_token(integration)
    return {"access_token": access_token, "token_type": "Bearer", "expires_in": ttl}


# ---------- Complete button ----------

class LabIn(BaseModel):
    lab_profile_id: str | None = None
    lab_instance_id: str | None = None
    lab_started_at: datetime


class ParticipantIn(BaseModel):
    external_id: str = Field(min_length=1, max_length=200)
    first_name: str | None = Field(default=None, max_length=120)
    last_name: str | None = Field(default=None, max_length=120)
    email: EmailStr | None = None


class LabAccountIn(BaseModel):
    upn: str = Field(min_length=3, max_length=320)

    @field_validator("upn")
    @classmethod
    def looks_like_upn(cls, v: str) -> str:
        if "@" not in v:
            raise ValueError("upn must look like user@domain")
        return v.strip()


class CompleteIn(BaseModel):
    event_id: str
    use_case_id: str
    step_id: str
    lab: LabIn
    participant: ParticipantIn
    lab_account: LabAccountIn
    submitted_at: datetime | None = None


async def _resolve_step(session: AsyncSession, body: CompleteIn) -> tuple[Event, UseCase, Step]:
    event = (await session.execute(select(Event).where(Event.slug == body.event_id))).scalar_one_or_none()
    if event is None:
        raise HTTPException(404, {"error": "unknown_event", "message": f"event_id '{body.event_id}' not found"})
    if event.status == "closed":
        raise HTTPException(409, {"error": "event_closed", "message": "This event is closed for submissions"})
    use_case = (await session.execute(select(UseCase).where(
        UseCase.event_id == event.id, UseCase.code == body.use_case_id))).scalar_one_or_none()
    if use_case is None:
        raise HTTPException(404, {"error": "unknown_use_case", "message": f"use_case_id '{body.use_case_id}' not found"})
    step = (await session.execute(select(Step).where(
        Step.use_case_id == use_case.id, Step.code == body.step_id))).scalar_one_or_none()
    if step is None:
        raise HTTPException(404, {"error": "unknown_step", "message": f"step_id '{body.step_id}' not found"})
    if not step.rubric_json.get("checks"):
        raise HTTPException(409, {"error": "step_not_configured", "message": "This step has no scoring rubric yet"})
    return event, use_case, step


async def _upsert_participant(session: AsyncSession, event: Event, integration: Integration, body: CompleteIn) -> Participant:
    p = (await session.execute(select(Participant).where(
        Participant.event_id == event.id, Participant.external_id == body.participant.external_id))).scalar_one_or_none()
    if p is None:
        # A participant imported by roster or found by a sync is keyed by UPN; adopt it rather than duplicate.
        p = (await session.execute(select(Participant).where(
            Participant.event_id == event.id,
            func.lower(Participant.upn) == body.lab_account.upn.lower()))).scalars().first()
        if p is not None:
            p.external_id, p.integration_id = body.participant.external_id, integration.id
    if p is None:
        p = Participant(event_id=event.id, external_id=body.participant.external_id, integration_id=integration.id)
        session.add(p)
    for field in ("first_name", "last_name", "email"):
        value = getattr(body.participant, field)
        if value:
            setattr(p, field, str(value))
    p.upn = body.lab_account.upn
    if p.first_lab_started_at is None or body.lab.lab_started_at < p.first_lab_started_at:
        p.first_lab_started_at = body.lab.lab_started_at
    return p


async def _wait_for_result(submission_id: str, wait_seconds: int) -> None:
    deadline = asyncio.get_running_loop().time() + wait_seconds
    while asyncio.get_running_loop().time() < deadline:
        await asyncio.sleep(0.5)
        async with SessionLocal() as s:
            sub = await s.get(Submission, submission_id)
            if sub and sub.status in ("complete", "incomplete", "error"):
                return


@router.post("/v1/steps/complete", status_code=202, summary="Participant clicked Complete on a step")
async def complete_step(
    body: CompleteIn,
    response: Response,
    integration: Integration = Depends(require_vendor),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
    wait_seconds: int = Query(default=0, ge=0, le=25,
                              description="Hold the request up to N seconds for the result (returns 200 if done)"),
    session: AsyncSession = Depends(get_session),
):
    key = idempotency_key or hashlib.sha256(
        f"{body.participant.external_id}|{body.event_id}|{body.use_case_id}|{body.step_id}|"
        f"{body.lab.lab_instance_id}|{body.submitted_at}".encode()).hexdigest()

    existing = (await session.execute(select(Submission.id).where(
        Submission.integration_id == integration.id, Submission.idempotency_key == key))).scalar_one_or_none()
    if existing is None:
        event, use_case, step = await _resolve_step(session, body)
        participant = await _upsert_participant(session, event, integration, body)
        await session.flush()
        sub = Submission(event_id=event.id, use_case_id=use_case.id, step_id=step.id, participant_id=participant.id,
                         integration_id=integration.id, idempotency_key=key,
                         lab_profile_id=body.lab.lab_profile_id, lab_instance_id=body.lab.lab_instance_id,
                         lab_started_at=body.lab.lab_started_at, submitted_at=body.submitted_at or utcnow(),
                         rubric_version=step.rubric_version, status="queued", next_attempt_at=utcnow())
        session.add(sub)
        try:
            await session.commit()
            submission_id = sub.id
        except IntegrityError:  # same key raced in from a double click
            await session.rollback()
            submission_id = (await session.execute(select(Submission.id).where(
                Submission.integration_id == integration.id, Submission.idempotency_key == key))).scalar_one()
            response.headers["Idempotent-Replayed"] = "true"
    else:
        submission_id = existing
        response.headers["Idempotent-Replayed"] = "true"

    if wait_seconds:
        await _wait_for_result(submission_id, wait_seconds)
    session.expire_all()
    view = vendor_view(await load_bundle(session, submission_id))
    if view["status"] == "evaluating":
        view["poll_after_seconds"] = 3
        response.status_code = status.HTTP_202_ACCEPTED
    else:
        response.status_code = status.HTTP_200_OK
    return view


@router.get("/v1/submissions/{submission_id}", summary="Get the result of a Complete click")
async def get_submission(submission_id: str, integration: Integration = Depends(require_vendor),
                         session: AsyncSession = Depends(get_session)):
    bundle = await load_bundle(session, submission_id)
    if bundle is None or bundle.submission.integration_id != integration.id:
        raise HTTPException(404, {"error": "not_found"})
    view = vendor_view(bundle)
    if view["status"] == "evaluating":
        view["poll_after_seconds"] = 3
    return view


@router.get("/v1/events/{event_id}/participants/{external_id}/progress",
            summary="Per-step status for one participant")
async def participant_progress(event_id: str, external_id: str, integration: Integration = Depends(require_vendor),
                               session: AsyncSession = Depends(get_session)):
    event = (await session.execute(select(Event).where(Event.slug == event_id))).scalar_one_or_none()
    if event is None:
        raise HTTPException(404, {"error": "unknown_event"})
    p = (await session.execute(select(Participant).where(
        Participant.event_id == event.id, Participant.external_id == external_id))).scalar_one_or_none()
    if p is None:
        raise HTTPException(404, {"error": "unknown_participant"})
    progress = {pr.step_id: pr for pr in (await session.execute(
        select(StepProgress).where(StepProgress.participant_id == p.id))).scalars()}
    steps = []
    for u, s in await event_steps(session, event.id):
        pr = progress.get(s.id)
        steps.append({"use_case_id": u.code, "step_id": s.code, "title": s.title,
                      "status": pr.status if pr else "not_started", "attempts": pr.attempts if pr else 0,
                      "completed_at": pr.completed_at.isoformat() if pr and pr.completed_at else None})
    return {"event_id": event.slug, "participant_external_id": external_id,
            "completed_steps": sum(1 for s in steps if s["status"] == "complete"),
            "total_steps": len(steps), "steps": steps}
