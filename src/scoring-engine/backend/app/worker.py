"""Background worker: evaluates queued submissions, re-verifies deferred evidence, delivers webhooks.

Postgres is the queue (`FOR UPDATE SKIP LOCKED`), so any number of worker replicas can run safely and
nothing is lost if a pod dies mid-evaluation: its lock goes stale and another pod picks the row up.
"""
import asyncio
import json
import logging
import signal
import time
from datetime import timedelta

import httpx
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError

from app import notifier
from app.config import get_settings
from app.db import SessionLocal, utcnow
from app.engine import evaluate, reverify
from app.graph import get_source
from app.models import Integration, Participant, Step, StepProgress, Submission, WebhookDelivery
from app.rubric import Rubric
from app.security import sign_webhook

settings = get_settings()
log = logging.getLogger("worker")
WEBHOOK_MAX_ATTEMPTS = 8


async def claim(batch: int) -> list[str]:
    now = utcnow()
    stale = now - timedelta(seconds=settings.worker_stale_lock_seconds)
    async with SessionLocal() as session:
        rows = (await session.execute(
            select(Submission)
            .where(Submission.status.in_(("queued", "evaluating")), Submission.next_attempt_at <= now,
                   or_(Submission.locked_at.is_(None), Submission.locked_at < stale))
            .order_by(Submission.next_attempt_at).limit(batch)
            .with_for_update(skip_locked=True)
        )).scalars().all()
        for s in rows:
            s.locked_at, s.status = now, "evaluating"
        await session.commit()
        return [s.id for s in rows]


async def process(submission_id: str) -> None:
    from app.services import apply_evaluation

    for attempt in range(2):
        async with SessionLocal() as session:
            sub = await session.get(Submission, submission_id)
            step = await session.get(Step, sub.step_id)
            participant = await session.get(Participant, sub.participant_id)
            sub.attempts += 1
            try:
                ev = await evaluate(Rubric.model_validate(step.rubric_json), source=get_source(), upn=participant.upn,
                                    lab_started_at=sub.lab_started_at, received_at=sub.received_at,
                                    attempts=sub.attempts, now=utcnow())
                await apply_evaluation(session, sub, ev)
                await session.commit()
                if ev.final:
                    log.info("submission %s -> %s", sub.id, ev.status)
                return
            except IntegrityError:  # two workers finalised the same participant/step at once
                await session.rollback()
                if attempt:
                    raise


async def evaluation_loop(stop: asyncio.Event) -> None:
    sem = asyncio.Semaphore(settings.worker_concurrency)
    running: set[asyncio.Task] = set()

    async def run(sid: str) -> None:
        async with sem:
            try:
                await process(sid)
            except Exception:
                log.exception("submission %s failed; lock will expire and it will be retried", sid)

    while not stop.is_set():
        free = settings.worker_concurrency - len(running)
        ids = await claim(free) if free > 0 else []
        for sid in ids:
            t = asyncio.create_task(run(sid))
            running.add(t)
            t.add_done_callback(running.discard)
        if not ids:
            try:
                await asyncio.wait_for(stop.wait(), timeout=settings.worker_poll_interval_seconds)
            except asyncio.TimeoutError:
                pass
    await asyncio.gather(*running, return_exceptions=True)


async def verification_loop(stop: asyncio.Event) -> None:
    interval = timedelta(seconds=settings.deferred_recheck_interval_seconds)
    while not stop.is_set():
        due = utcnow() - interval
        async with SessionLocal() as session:
            subs = (await session.execute(
                select(Submission).where(Submission.verification_status == "pending",
                                         or_(Submission.verification_checked_at.is_(None),
                                             Submission.verification_checked_at < due))
                .limit(50).with_for_update(skip_locked=True)
            )).scalars().all()
            for sub in subs:
                step = await session.get(Step, sub.step_id)
                participant = await session.get(Participant, sub.participant_id)
                try:
                    status, results = await reverify(
                        Rubric.model_validate(step.rubric_json), sub.check_results, source=get_source(),
                        upn=participant.upn, lab_started_at=sub.lab_started_at, received_at=sub.received_at,
                        now=utcnow(), max_age=timedelta(seconds=settings.deferred_max_age_seconds))
                except Exception:
                    log.exception("re-verification of %s failed", sub.id)
                    status, results = "pending", sub.check_results
                sub.verification_status, sub.check_results, sub.verification_checked_at = status, results, utcnow()
                progress = await session.get(StepProgress, (sub.participant_id, sub.step_id))
                if progress and progress.last_submission_id == sub.id:
                    progress.verification_status = status
                if status != "pending":
                    await notifier.publish(session, sub.event_id)
            await session.commit()
        try:
            await asyncio.wait_for(stop.wait(), timeout=30)
        except asyncio.TimeoutError:
            pass


async def webhook_loop(stop: asyncio.Event) -> None:
    async with httpx.AsyncClient(timeout=10) as client:
        while not stop.is_set():
            async with SessionLocal() as session:
                deliveries = (await session.execute(
                    select(WebhookDelivery).where(WebhookDelivery.status == "pending",
                                                  WebhookDelivery.next_attempt_at <= utcnow())
                    .limit(20).with_for_update(skip_locked=True)
                )).scalars().all()
                for d in deliveries:
                    integration = await session.get(Integration, d.integration_id)
                    body = json.dumps(d.payload, separators=(",", ":")).encode()
                    headers = {"Content-Type": "application/json", "User-Agent": "VectorSense-Scoring-Webhook/1.0",
                               "X-VectorSense-Delivery": d.id}
                    if integration and integration.webhook_secret:
                        headers["X-VectorSense-Signature"] = sign_webhook(integration.webhook_secret, body, int(time.time()))
                    d.attempts += 1
                    try:
                        resp = await client.post(d.url, content=body, headers=headers)
                        ok = 200 <= resp.status_code < 300
                        d.last_error = None if ok else f"HTTP {resp.status_code}: {resp.text[:200]}"
                    except httpx.HTTPError as exc:
                        ok, d.last_error = False, str(exc)[:500]
                    if ok:
                        d.status, d.delivered_at = "delivered", utcnow()
                    elif d.attempts >= WEBHOOK_MAX_ATTEMPTS:
                        d.status = "failed"
                    else:
                        d.next_attempt_at = utcnow() + timedelta(seconds=min(2 ** d.attempts * 5, 900))
                await session.commit()
            try:
                await asyncio.wait_for(stop.wait(), timeout=2)
            except asyncio.TimeoutError:
                pass


async def sync_loop(stop: asyncio.Event) -> None:
    from app import sync

    while not stop.is_set():
        run_id = await sync.claim_run()
        if run_id:
            log.info("sync run %s started", run_id)
            await sync.execute(run_id)
            continue
        try:
            await asyncio.wait_for(stop.wait(), timeout=2)
        except asyncio.TimeoutError:
            pass


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    log.info("worker started (graph mode: %s, concurrency: %s)", settings.graph_mode, settings.worker_concurrency)
    await asyncio.gather(evaluation_loop(stop), verification_loop(stop), webhook_loop(stop), sync_loop(stop))
    log.info("worker stopped")


if __name__ == "__main__":
    asyncio.run(main())
