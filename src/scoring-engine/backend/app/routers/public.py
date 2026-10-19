"""Public, unauthenticated surfaces: a participant's own scorecard (looked up by lab account) and a
realtime signal stream. There is deliberately no public leaderboard: only administrators see everyone's results.
"""
import asyncio
import json
import time

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import SessionLocal, get_session
from app.models import Event, Participant, StepProgress, Submission
from app.notifier import hub
from app.security import issue_local_admin_token
from app.services import display_name, event_steps

router = APIRouter(prefix="/api", tags=["Public"])
settings = get_settings()


@router.get("/config")
async def runtime_config():
    """Bootstraps the SPA, so the same frontend image works in any tenant."""
    return {"app_name": settings.app_name, "auth_mode": settings.auth_mode,
            "entra": {"tenant_id": settings.entra_tenant_id, "client_id": settings.entra_spa_client_id,
                      "api_scope": f"api://{settings.entra_api_client_id}/access_as_admin"
                      if settings.entra_api_client_id else ""},
            "public_base_url": settings.public_base_url, "scorecard_base_url": settings.scorecard_base_url,
            "graph_mode": settings.graph_mode,
            "environment": settings.environment}


class LoginIn(BaseModel):
    username: str
    password: str


@router.post("/auth/login")
async def local_login(body: LoginIn):
    if settings.auth_mode != "local":
        raise HTTPException(400, "Local login is disabled; sign in with Microsoft Entra ID")
    import hmac
    if not (hmac.compare_digest(body.username, settings.admin_username)
            and hmac.compare_digest(body.password, settings.admin_password)):
        raise HTTPException(401, "Invalid username or password")
    return {"access_token": issue_local_admin_token(body.username), "token_type": "Bearer"}


async def _public_event(session: AsyncSession, slug: str) -> Event:
    event = (await session.execute(select(Event).where(Event.slug == slug))).scalar_one_or_none()
    if event is None or not event.public_leaderboard or event.status == "draft":
        raise HTTPException(404, "Scorecards are not available for this event")
    return event


@router.get("/public/events")
async def public_events(session: AsyncSession = Depends(get_session)):
    events = (await session.execute(select(Event).where(Event.public_leaderboard.is_(True), Event.status != "draft")
                                    .order_by(Event.created_at.desc()))).scalars().all()
    return [{"slug": e.slug, "name": e.name, "description": e.description, "status": e.status} for e in events]


@router.get("/public/events/{slug}")
async def public_event(slug: str, session: AsyncSession = Depends(get_session)):
    e = await _public_event(session, slug)
    steps = await event_steps(session, e.id)
    return {"slug": e.slug, "name": e.name, "description": e.description, "status": e.status,
            "starts_at": e.starts_at.isoformat() if e.starts_at else None,
            "ends_at": e.ends_at.isoformat() if e.ends_at else None,
            "steps": [{"code": s.code, "title": s.title, "use_case": u.title} for u, s in steps]}


class _Limiter:
    """Small per-client limit on scorecard lookups so lab accounts can't be enumerated quickly."""

    def __init__(self, per_minute: int) -> None:
        self.per_minute = per_minute
        self.hits: dict[str, list[float]] = {}

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        recent = [t for t in self.hits.get(key, []) if now - t < 60]
        if len(recent) >= self.per_minute:
            self.hits[key] = recent
            return False
        recent.append(now)
        self.hits[key] = recent
        if len(self.hits) > 50_000:
            self.hits.clear()
        return True


_limiter = _Limiter(per_minute=30)


class ScorecardIn(BaseModel):
    upn: str = Field(min_length=3, max_length=320)


@router.post("/public/events/{slug}/scorecard")
async def scorecard(slug: str, body: ScorecardIn, request: Request, session: AsyncSession = Depends(get_session)):
    """A participant's own scorecard, looked up by their lab account. Never returns anyone else's data."""
    client = (request.headers.get("x-forwarded-for", "").split(",")[0].strip()
              or (request.client.host if request.client else ""))
    if not _limiter.allow(client):
        raise HTTPException(429, "Too many lookups. Please wait a minute and try again.")
    e = await _public_event(session, slug)
    upn = body.upn.strip().lower()
    p = (await session.execute(select(Participant).where(
        Participant.event_id == e.id, func.lower(Participant.upn) == upn))).scalars().first()
    if p is None:
        raise HTTPException(404, "We couldn't find results for this lab account yet. Results appear after you "
                                 "complete your first step. Check the account name and try again.")
    progress = {pr.step_id: pr for pr in (await session.execute(
        select(StepProgress).where(StepProgress.participant_id == p.id))).scalars()}
    subs = (await session.execute(select(Submission).where(Submission.participant_id == p.id)
                                  .order_by(Submission.received_at.desc()))).scalars().all()
    steps = []
    for u, s in await event_steps(session, e.id):
        pr = progress.get(s.id)
        mine = [x for x in subs if x.step_id == s.id]
        latest = mine[0] if mine else None
        shown = next((x for x in mine if x.status == "complete"), latest)
        checks = []
        if shown and e.public_show_reasons:
            checks = [{"id": c["id"], "description": c.get("description") or c["id"], "status": c["status"],
                       "mode": c["mode"], "message": c["message"]} for c in shown.check_results or []]
        steps.append({
            "use_case": u.title, "code": s.code, "title": s.title, "description": s.description,
            "status": pr.status if pr else ("evaluating" if latest and latest.status in ("queued", "evaluating")
                                            else "not_started"),
            "attempts": pr.attempts if pr else 0,
            "completed_at": pr.completed_at.isoformat() if pr and pr.completed_at else None,
            "verification_status": pr.verification_status if pr else "not_required",
            "reasons": (shown.reasons if shown and shown.status != "complete" and e.public_show_reasons else []),
            "checks": checks,
        })
    done = [x for x in progress.values() if x.status == "complete"]
    last = max((x.completed_at for x in done if x.completed_at), default=None)
    elapsed = int((last - p.first_lab_started_at).total_seconds()) if last and p.first_lab_started_at else None
    return {"event": {"slug": e.slug, "name": e.name, "status": e.status,
                      "last_synced_at": e.last_synced_at.isoformat() if e.last_synced_at else None},
            "participant": {"name": display_name(p, "full"), "upn": p.upn},
            "completed_steps": len(done), "total_steps": len(steps), "elapsed_seconds": elapsed, "steps": steps}


async def _sse(request: Request, event_id: str):
    q = hub.subscribe(event_id)
    try:
        yield "retry: 3000\n\n"
        yield f"event: hello\ndata: {json.dumps({'event_id': event_id})}\n\n"
        while not await request.is_disconnected():
            try:
                msg = await asyncio.wait_for(q.get(), timeout=20)
                yield f"event: update\ndata: {json.dumps(msg)}\n\n"
            except asyncio.TimeoutError:
                yield ": keep-alive\n\n"
    finally:
        hub.unsubscribe(event_id, q)


_SSE_HEADERS = {"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"}


# SSE endpoints open their own short-lived session so a long-lived stream never pins a pooled connection.
@router.get("/public/events/{slug}/stream")
async def public_stream(slug: str, request: Request):
    async with SessionLocal() as session:
        event_id = (await _public_event(session, slug)).id
    return StreamingResponse(_sse(request, event_id), media_type="text/event-stream", headers=_SSE_HEADERS)


@router.get("/stream/events/{event_id}")
async def admin_stream(event_id: str, request: Request):
    # Signals only ("event X changed"); clients refetch with their own auth, so no data leaks here.
    async with SessionLocal() as session:
        if await session.get(Event, event_id) is None:
            raise HTTPException(404)
    return StreamingResponse(_sse(request, event_id), media_type="text/event-stream", headers=_SSE_HEADERS)
