"""Turns a step rubric plus a participant's lab context into complete / incomplete (+ reasons)."""
import asyncio
import logging
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any

from app.checks import REGISTRY
from app.checks.base import CheckContext, Outcome
from app.graph.base import EvidenceSource, TransientEvidenceError
from app.rubric import CheckSpec, Rubric

MAX_TRANSIENT_ATTEMPTS = 5
RETRY_WINDOW_POLL_SECONDS = 8
log = logging.getLogger("engine")


@dataclass
class Evaluation:
    final: bool
    status: str  # complete | incomplete | error  (or evaluating when not final)
    reasons: list[dict[str, str]] = field(default_factory=list)
    check_results: list[dict[str, Any]] = field(default_factory=list)
    verification_status: str = "not_required"
    retry_in_seconds: float = 0
    evidence_at: datetime | None = None  # latest blocking evidence: when the work was actually done


async def _run_one(spec: CheckSpec, ctx: CheckContext) -> dict[str, Any]:
    impl = REGISTRY[spec.type]
    base = {"id": spec.id, "type": spec.type, "mode": spec.mode, "description": spec.description}
    try:
        outcome: Outcome = await impl.run(ctx, impl.Params.model_validate(spec.params))
    except TransientEvidenceError as exc:
        return {**base, "status": "error", "transient": True, "message": str(exc), "evidence": {}}
    except Exception as exc:  # a broken check must never leave a participant unscored
        log.exception("check %s crashed", spec.id)
        return {**base, "status": "error", "transient": False, "message": f"{type(exc).__name__}: {exc}", "evidence": {}}
    status = "pending" if outcome.pending else ("passed" if outcome.passed else "failed")
    message = outcome.message
    if status == "failed" and spec.fail_message:
        message = spec.fail_message
    return {**base, "status": status, "message": message, "evidence": outcome.evidence}


def _ctx(source: EvidenceSource, upn: str, lab_started_at: datetime, received_at: datetime, now: datetime) -> CheckContext:
    return CheckContext(upn=upn, lab_started_at=lab_started_at, received_at=received_at, now=now, source=source)


async def evaluate(rubric: Rubric, *, source: EvidenceSource, upn: str, lab_started_at: datetime,
                   received_at: datetime, attempts: int, now: datetime, single_pass: bool = False) -> Evaluation:
    """single_pass: organiser sync. No retry windows and no transient retries; the next sync picks it up."""
    ctx = _ctx(source, upn, lab_started_at, received_at, now)
    results = await asyncio.gather(*(_run_one(c, ctx) for c in rubric.checks))
    by_id = {c.id: c for c in rubric.checks}
    blocking = [r for r in results if r["mode"] == "blocking"]
    deferred = [r for r in results if r["mode"] == "deferred"]

    transient = [r for r in blocking if r["status"] == "error" and r.get("transient")]
    if transient and attempts < MAX_TRANSIENT_ATTEMPTS and not single_pass:
        return Evaluation(False, "evaluating", check_results=results, retry_in_seconds=min(2 ** attempts * 2, 60))

    failed = [r for r in blocking if r["status"] == "failed"]
    still_waiting = [r for r in failed
                     if received_at + timedelta(seconds=by_id[r["id"]].retry_window_seconds) > now]
    if still_waiting and not single_pass:
        return Evaluation(False, "evaluating", check_results=results, retry_in_seconds=RETRY_WINDOW_POLL_SECONDS)

    errors = [r for r in blocking if r["status"] == "error"]
    if errors:
        reasons = [{"check": r["id"], "message": f"Could not evaluate: {r['message']}"} for r in errors]
        return Evaluation(True, "error", reasons=reasons, check_results=results)
    if failed:
        return Evaluation(True, "incomplete", check_results=results,
                          reasons=[{"check": r["id"], "message": r["message"]} for r in failed])

    verification = "not_required"
    if deferred:
        verification = "verified" if all(r["status"] == "passed" for r in deferred) else "pending"
    times = [datetime.fromisoformat(r["evidence"]["at"]) for r in blocking if (r.get("evidence") or {}).get("at")]
    return Evaluation(True, "complete", check_results=results, verification_status=verification,
                      evidence_at=max(times) if times else None)


async def reverify(rubric: Rubric, previous: list[dict[str, Any]], *, source: EvidenceSource, upn: str,
                   lab_started_at: datetime, received_at: datetime, now: datetime,
                   max_age: timedelta) -> tuple[str, list[dict[str, Any]]]:
    """Re-run only deferred checks for an already-complete submission."""
    ctx = _ctx(source, upn, lab_started_at, received_at, now)
    deferred_specs = [c for c in rubric.checks if c.mode == "deferred"]
    fresh = {r["id"]: r for r in await asyncio.gather(*(_run_one(c, ctx) for c in deferred_specs))}
    merged = [fresh.get(r["id"], r) for r in previous]
    if all(fresh[c.id]["status"] == "passed" for c in deferred_specs):
        return "verified", merged
    if now - received_at > max_age:
        return "unverified", merged
    return "pending", merged
