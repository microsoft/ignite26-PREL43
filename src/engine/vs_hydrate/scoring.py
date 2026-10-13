"""Scorecard evaluation against one seat's mailbox, calendar and OneDrive.

Checks read the seat's data directly through Microsoft Graph (message bodies,
calendar view, OneDrive items and file contents). They do not depend on the
search index, so a result is available as soon as Microsoft 365 has stored
the item.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from .api.base import TenantError
from .kit import Kit
from .textextract import extract_text

log = logging.getLogger("vs_hydrate.scoring")
MAX_DOWNLOAD = 15 * 1024 * 1024
MAX_FILES = 60


class SeatData:
    """Lazily loaded view of a seat's data, shared by all checks in one run."""

    def __init__(self, kit: Kit, seat: dict):
        self.kit, self.seat, self.api = kit, seat, kit.api
        self.uid = seat["id"]
        self.tl = kit.timeline(seat["lab_day"])
        self._mail: dict[str, list[dict]] = {}
        self._events: list[dict] | None = None
        self._drive: dict | None | bool = False
        self._items: list[dict] | None = None
        self._text: dict[str, str] = {}

    def mail(self, folder: str) -> list[dict]:
        if folder not in self._mail:
            try:
                self._mail[folder] = self.api.list_messages(self.uid, folder, top=200, with_body=True)
            except TenantError as e:
                log.warning("cannot read %s for %s: %s", folder, self.seat["upn"], e)
                self._mail[folder] = []
        return self._mail[folder]

    def events(self) -> list[dict]:
        if self._events is None:
            w = self.kit.scorecard.get("window", {"start": "D-1", "end": "D+14"})
            self._events = self.api.calendar_view(self.uid, self.tl.utc_iso(w["start"]), self.tl.utc_iso(w["end"]))
        return self._events

    def drive(self) -> dict | None:
        if self._drive is False:
            self._drive = self.api.user_drive(self.uid)
        return self._drive

    def items(self) -> list[dict]:
        if self._items is None:
            d = self.drive()
            self._items = self.api.drive_items(d["id"]) if d else []
        return self._items

    def text(self, item: dict) -> str:
        if item["id"] not in self._text:
            if item.get("size", 0) > MAX_DOWNLOAD:
                self._text[item["id"]] = ""
            else:
                data = self.api.download(self.drive()["id"], item["id"])
                self._text[item["id"]] = extract_text(item["name"], data)
        return self._text[item["id"]]

    def recently_modified(self, minutes: int = 20) -> bool:
        cut = datetime.now(timezone.utc) - timedelta(minutes=minutes)
        for i in self.items():
            ts = i.get("lastModifiedDateTime")
            if ts and datetime.fromisoformat(ts.replace("Z", "+00:00")) > cut:
                return True
        return False


def _body(m: dict) -> str:
    b = m.get("body") or {}
    return (b.get("content") or "") + "\n" + (m.get("bodyPreview") or "")


def _check(data: SeatData, c: dict) -> tuple[bool, str]:
    t, p = c["type"], c.get("params", {})
    if t == "mail_contains":
        phrase = p["phrase"].lower()
        for f in p.get("folders", ["drafts", "sentitems", "inbox"]):
            for m in data.mail(f):
                if phrase in _body(m).lower():
                    return True, f"found in {f}: {m.get('subject', '')[:60]}"
        return False, "no message contains the phrase"
    if t == "mail_subject":
        pre = p["subject_prefix"].lower()
        for f in p.get("folders", ["inbox"]):
            for m in data.mail(f):
                if (m.get("subject") or "").strip().lower().startswith(pre):
                    return True, f"{f}: {m['subject'][:80]}"
        return False, "no message with that subject"
    if t in ("event_exists", "event_absent"):
        want = p["subject"].strip().lower()
        hits = [e for e in data.events() if (e.get("subject") or "").strip().lower() == want
                and not e.get("isCancelled")]
        if t == "event_exists":
            return (bool(hits), f"{len(hits)} event(s)" if hits else "no such event")
        return (not hits, "no such event" if not hits else f"{len(hits)} event(s) present")
    if t == "drive_item_name":
        if not data.drive():
            return False, "OneDrive not provisioned"
        pat = p["pattern"].lower()
        for i in data.items():
            if pat in i["name"].lower() and (not p.get("files_only") or "file" in i):
                return True, i["name"]
        return False, "no matching OneDrive item"
    if t == "drive_file_contains":
        if not data.drive():
            return False, "OneDrive not provisioned"
        exts = tuple(x.lower() for x in p.get("extensions", []))
        excl = [x.lower() for x in p.get("exclude_name_patterns", [])]
        phrase = p["phrase"]
        cands = [i for i in data.items() if "file" in i and (not exts or i["name"].lower().endswith(exts))
                 and not any(x in i["name"].lower() for x in excl)]
        cands.sort(key=lambda i: i.get("lastModifiedDateTime") or "", reverse=True)
        for i in cands[:MAX_FILES]:
            txt = data.text(i)
            if (phrase in txt) if p.get("case_sensitive") else (phrase.lower() in txt.lower()):
                return True, i["name"]
        return False, f"no file contains {phrase!r} ({len(cands)} checked)"
    raise ValueError(f"unknown check type {t}")


def evaluate(kit: Kit, seat: dict) -> dict:
    sc = kit.scorecard
    data = SeatData(kit, seat)
    points, details, passed_ids = {}, {}, set()
    for c in sc["checks"]:
        try:
            ok, why = _check(data, c)
        except TenantError as e:
            ok, why = False, f"error: {e}"
        points[c["id"]] = c["points"] if ok else 0
        details[c["id"]] = why
        if ok:
            passed_ids.add(c["id"])

    for cid, g in sc.get("guards", {}).items():
        if g.get("enabled") and cid in passed_ids and not passed_ids & set(g["requires_any"]):
            points[cid] = 0
            passed_ids.discard(cid)
            details[cid] += "; guard: no focus block was created"

    total = sum(points.values())
    failed = [c for c in sc["checks"] if c["id"] not in passed_ids]
    recheck = []
    if failed and data.drive() and data.recently_modified():
        recheck = [c["id"] for c in failed if c.get("recheck_on_fail")]
    return {
        "seat": seat["upn"], "score": total, "max": sc["max"], "pass_mark": sc["pass_mark"],
        "passed": total >= sc["pass_mark"], "checks": points, "recheck": recheck,
        "feedback": feedback(sc, passed_ids, recheck), "details": details,
    }


def feedback(sc: dict, passed: set, recheck: list) -> str:
    by_m: dict[str, list[dict]] = {}
    for c in sc["checks"]:
        by_m.setdefault(c["milestone"], []).append(c)
    required = [m for m in by_m if m != "M5"]
    missing_req = [c for m in required for c in by_m[m] if c["id"] not in passed]
    lines = []
    if not missing_req:
        lines.append(f"{required[0]}–{required[-1]} complete.")
    else:
        done = [m for m in required if all(c["id"] in passed for c in by_m[m])]
        if done:
            lines.append("Complete: " + ", ".join(done) + ".")
        for c in missing_req:
            tag = " (will be re-checked after indexing)" if c["id"] in recheck else ""
            lines.append(f"{c['milestone']} {c['id']}: {c.get('hint', 'not found')}{tag}")
    m5 = by_m.get("M5", [])
    got = [c for c in m5 if c["id"] in passed]
    if got:
        lines.append(f"Optional M5: {len(got)}/{len(m5)} checks passed.")
    return " ".join(lines)
