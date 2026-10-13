"""Shared run context for every command."""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from datetime import date, datetime, timezone

from .api.base import TenantAPI, TenantError
from .config import Config, ConfigError
from .datapack import DataPack, DataPackError
from .render import Context
from .state import State
from .timeline import Timeline, iana_zone

log = logging.getLogger("vs_hydrate")

WRITE_METHODS = {
    "create_user", "update_user", "delete_user", "set_manager", "set_photo", "assign_licenses", "create_tap",
    "add_group_member", "delete_group", "set_mailbox_settings", "create_message", "update_message",
    "delete_message", "create_event", "accept_event", "delete_event", "create_migration_team",
    "create_migration_channel", "import_message", "complete_channel_migration", "complete_team_migration",
    "add_team_member", "ensure_folder", "upload_file",
}


class DryRun:
    """Wraps a TenantAPI: reads pass through, writes are recorded and skipped."""

    def __init__(self, api: TenantAPI):
        self._api = api
        self.planned: list[str] = []
        self._n = 0

    def __getattr__(self, name):
        target = getattr(self._api, name)
        if name in WRITE_METHODS:
            def fake(*args, **kwargs):
                self._n += 1
                self.planned.append(f"{name}({', '.join(str(a)[:60] for a in args)})")
                if name == "create_user":
                    return {"id": f"dryrun-{self._n}", **args[0]}
                if name == "create_event":
                    return {"id": f"dryrun-{self._n}", "iCalUId": f"dryrun-{self._n}"}
                if name == "create_tap":
                    return "dry-run"
                return f"dryrun-{self._n}"
            return fake

        def read(*args, **kwargs):
            if any(isinstance(a, str) and a.startswith("dryrun-") for a in args):
                return {"mailbox_ready": True, "user_license_skus": set(), "is_group_member": False,
                        "find_event_by_ical": {"id": "dryrun-ev", "responseStatus": {"response": "accepted"}},
                        "channel_files_folder": {"drive_id": "dryrun-drive", "id": "dryrun-folder"},
                        "team_exists": True, "user_drive": {"id": "dryrun-drive"},
                        "list_channels": []}.get(name, [])
            return target(*args, **kwargs)
        return read


@dataclass
class Kit:
    cfg: Config
    api: TenantAPI
    pack: DataPack
    scorecard: dict
    check_set: dict
    state: State
    dry_run: bool = False
    concurrency: int = 4
    today: date = field(default_factory=lambda: datetime.now().date())
    _skus: dict | None = None

    @classmethod
    def build(cls, cfg: Config, api: TenantAPI, dry_run: bool = False, concurrency: int = 4) -> "Kit":
        try:
            pack = DataPack.load(cfg.datapack_path)
        except DataPackError as e:
            raise ConfigError(str(e)) from e
        for p, what in ((cfg.scorecard_path, "scorecard"), (cfg.check_set_path, "readiness check set")):
            if not p.is_file():
                raise ConfigError(f"{what} not found: {p}")
        scorecard = json.loads(cfg.scorecard_path.read_text())
        check_set = json.loads(cfg.check_set_path.read_text())
        state = State(cfg.out_dir / "state.json")
        if dry_run:  # read real state, never overwrite it
            state.path = cfg.out_dir / "state.dry-run.json"
        kit = cls(cfg=cfg, api=DryRun(api) if dry_run else api, pack=pack, scorecard=scorecard,
                  check_set=check_set, state=state, dry_run=dry_run, concurrency=max(1, concurrency))
        kit.tz  # validate the time zone early
        return kit

    # ---------------------------------------------------------------- time
    @property
    def tz(self):
        s = self.cfg.seats
        try:
            return iana_zone(s["time_zone"], s.get("time_zone_iana"))
        except ValueError as e:
            raise ConfigError(str(e)) from e

    def timeline(self, lab_day: str | date | None = None) -> Timeline:
        if lab_day is None:
            d = self.cfg.lab_day(datetime.now(self.tz).date())
        else:
            d = lab_day if isinstance(lab_day, date) else date.fromisoformat(lab_day)
        return Timeline(d, self.tz, self.cfg.seats["time_zone"])

    def now(self) -> datetime:
        return datetime.now(timezone.utc)

    # ---------------------------------------------------------------- people
    def learner_context(self, seat_upn: str, timeline: Timeline) -> Context:
        s = self.cfg.seats
        return Context(timeline, f"{s['given_name']} {s['surname']}", s["given_name"], seat_upn)

    def persona_id(self, key: str) -> str:
        pid = self.state.tenant.get("personas", {}).get(key)
        if not pid:
            raise TenantError(f"persona {key!r} not created yet; run `tenant` first")
        return pid

    # ---------------------------------------------------------------- licences
    def skus(self) -> dict[str, dict]:
        if self._skus is None:
            self._skus = {s["skuPartNumber"]: s for s in self.api.subscribed_skus()}
        return self._skus

    def sku_id(self, part: str) -> str:
        s = self.skus().get(part)
        if not s:
            raise ConfigError(f"licence SKU {part!r} is not in this tenant")
        return s["skuId"]

    def seat_group(self) -> dict:
        g = self.api.find_group(self.cfg.seats["group"])
        if not g:
            raise ConfigError(f"seat group {self.cfg.seats['group']!r} not found; Skillable creates it and enables Cowork for it")
        return g
