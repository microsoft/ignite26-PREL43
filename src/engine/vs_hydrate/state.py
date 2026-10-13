"""Run state and reports.

`out/state.json` records what the kit has written, so every command is
idempotent and resumable: a re-run skips finished work and continues from the
first unfinished phase of each seat.
`out/seat-inventory.json` lists ready seats for the Skillable seat pool.
`out/report-<command>-<timestamp>.json` is written by every command.
"""
from __future__ import annotations

import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path

SEAT_STATES = ("provisioning", "hydrated", "ready", "failed", "used", "retired")


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


class State:
    def __init__(self, path: Path):
        self.path = path
        self._lock = threading.RLock()
        self.data = {"tenant": {}, "seats": {}}
        if path.exists():
            self.data = json.loads(path.read_text())
            self.data.setdefault("tenant", {})
            self.data.setdefault("seats", {})

    def save(self) -> None:
        with self._lock:
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.data, indent=2, sort_keys=True))
            os.replace(tmp, self.path)

    @property
    def tenant(self) -> dict:
        return self.data["tenant"]

    @property
    def seats(self) -> dict:
        return self.data["seats"]

    def seat(self, upn: str) -> dict:
        with self._lock:
            return self.seats.setdefault(upn, {"upn": upn, "state": "provisioning", "phases": [], "log": []})

    def mark(self, seat: dict, phase: str) -> None:
        with self._lock:
            if phase not in seat["phases"]:
                seat["phases"].append(phase)
            self.save()

    def done(self, seat: dict, phase: str) -> bool:
        return phase in seat.get("phases", [])

    def lock(self):
        return self._lock


def write_inventory(out_dir: Path, state: State) -> Path:
    seats = [{"upn": s["upn"], "tap": s.get("tap"), "state": "ready", "datapack": s.get("datapack"),
              "lab_day": s.get("lab_day"), "checked": s.get("check", {}).get("at")}
             for s in sorted(state.seats.values(), key=lambda s: s["upn"]) if s["state"] == "ready"]
    p = out_dir / "seat-inventory.json"
    p.write_text(json.dumps(seats, indent=2))
    try:
        os.chmod(p, 0o600)  # contains Temporary Access Passes
    except OSError:
        pass
    return p


def write_report(out_dir: Path, command: str, body: dict) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    p = out_dir / f"report-{command}-{stamp}.json"
    p.write_text(json.dumps({"command": command, "at": now_iso(), **body}, indent=2, default=str))
    return p
