from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, ClassVar

from pydantic import BaseModel, ConfigDict

from app.graph.base import EvidenceSource


@dataclass
class CheckContext:
    upn: str
    lab_started_at: datetime
    received_at: datetime
    now: datetime
    source: EvidenceSource


@dataclass
class Outcome:
    passed: bool
    message: str
    evidence: dict[str, Any] = field(default_factory=dict)
    pending: bool = False  # deferred evidence not available yet (e.g. audit query still running)


class StrictParams(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Check:
    type: ClassVar[str]
    title: ClassVar[str]
    summary: ClassVar[str]
    Params: ClassVar[type[StrictParams]]
    example: ClassVar[dict[str, Any]]

    async def run(self, ctx: CheckContext, params: Any) -> Outcome:  # pragma: no cover - interface
        raise NotImplementedError


def contains_all(haystack: str, needles: list[str]) -> list[str]:
    """Return the needles that are missing (case-insensitive)."""
    low = haystack.lower()
    return [n for n in needles if n.lower() not in low]


def parse_dt(raw: str | None) -> datetime | None:
    if not raw:
        return None
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def latest_at(items: list[dict], field: str) -> str | None:
    """ISO time of the most recent item, recorded as evidence["at"] so completions can be timed."""
    times = [t for t in (parse_dt(i.get(field)) for i in items) if t]
    return max(times).isoformat() if times else None


def quote_list(items: list[str]) -> str:
    return ", ".join(f"'{i}'" for i in items)
