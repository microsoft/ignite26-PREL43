"""Step rubrics: a YAML list of evidence checks. All blocking checks must pass for a step to be complete."""
from typing import Any, Literal

import yaml
from pydantic import BaseModel, Field, ValidationError, field_validator


class CheckSpec(BaseModel):
    id: str = Field(pattern=r"^[a-z0-9_\-]{1,64}$")
    type: str
    description: str = ""
    # blocking: decides complete/incomplete now.
    # deferred: slow evidence (e.g. audit-backed Copilot signals); re-verified in the background and
    #           shown as a verification badge, never blocks the participant.
    mode: Literal["blocking", "deferred"] = "blocking"
    # Keep re-checking a failing blocking check for this long before answering "incomplete",
    # to absorb Graph propagation delay. Capped so the Complete button never waits forever.
    retry_window_seconds: int = Field(default=0, ge=0, le=600)
    fail_message: str | None = None
    params: dict[str, Any] = Field(default_factory=dict)


class Rubric(BaseModel):
    checks: list[CheckSpec] = Field(min_length=1)

    @field_validator("checks")
    @classmethod
    def unique_ids(cls, checks: list[CheckSpec]) -> list[CheckSpec]:
        ids = [c.id for c in checks]
        if len(ids) != len(set(ids)):
            raise ValueError("check ids must be unique within a step")
        if not any(c.mode == "blocking" for c in checks):
            raise ValueError("at least one check must be blocking")
        return checks


class RubricError(ValueError):
    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors))
        self.errors = errors


def parse_rubric(text: str) -> Rubric:
    from app.checks import REGISTRY

    try:
        data = yaml.safe_load(text) or {}
    except yaml.YAMLError as exc:
        raise RubricError([f"YAML syntax: {exc}"]) from exc
    if not isinstance(data, dict):
        raise RubricError(["rubric must be a mapping with a 'checks' list"])
    try:
        rubric = Rubric.model_validate(data)
    except ValidationError as exc:
        raise RubricError([f"{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()]) from exc

    errors: list[str] = []
    for check in rubric.checks:
        impl = REGISTRY.get(check.type)
        if impl is None:
            errors.append(f"{check.id}: unknown check type '{check.type}' (known: {', '.join(sorted(REGISTRY))})")
            continue
        try:
            impl.Params.model_validate(check.params)
        except ValidationError as exc:
            errors += [f"{check.id}.params.{'.'.join(map(str, e['loc']))}: {e['msg']}" for e in exc.errors()]
    if errors:
        raise RubricError(errors)
    return rubric
