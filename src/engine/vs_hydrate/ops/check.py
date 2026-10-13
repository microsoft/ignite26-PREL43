"""`check`: readiness check for each hydrated seat.

Marks every seat `ready`, `pending` (content still indexing; re-run later) or
`failed` (content missing or a scoring check already satisfied; retire it and
hydrate a replacement). Writes out/seat-inventory.json with the ready seats.
"""
from __future__ import annotations

import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

from ..api.base import TenantError
from ..kit import Kit
from ..scoring import evaluate
from ..state import now_iso, write_inventory
from ..textextract import extract_text

log = logging.getLogger("vs_hydrate.check")


class SeatProbe:
    def __init__(self, kit: Kit, seat: dict):
        self.kit, self.s, self.api = kit, seat, kit.api
        self.tl = kit.timeline(seat["lab_day"])
        self._inbox = None
        self._posts = None
        self._files: dict[str, dict] = {}

    # data ----------------------------------------------------------------
    def inbox(self) -> list[dict]:
        if self._inbox is None:
            self._inbox = self.api.list_messages(self.s["id"], "inbox", top=200, with_body=True)
        return self._inbox

    def posts(self) -> list[dict]:
        if self._posts is None:
            self._posts = self.api.list_channel_messages(self.s["team_id"], self.s["channel_id"])
        return self._posts

    def files(self, folder: str | None) -> dict[str, dict]:
        key = folder or ""
        if key not in self._files:
            root = self.api.channel_files_folder(self.s["team_id"], self.s["channel_id"])
            parent = root["id"]
            if folder:
                kids = {c["name"]: c for c in self.api.list_children(root["drive_id"], parent)}
                if folder not in kids:
                    self._files[key] = {}
                    return {}
                parent = kids[folder]["id"]
            self._files[key] = {c["name"]: {**c, "drive_id": root["drive_id"]}
                                for c in self.api.list_children(root["drive_id"], parent)}
        return self._files[key]

    def file_text(self, name: str) -> str:
        for folder in (None, "Recordings"):
            f = self.files(folder).get(name)
            if f:
                return extract_text(name, self.api.download(f["drive_id"], f["id"]))
        return ""

    # day one -------------------------------------------------------------
    def day_one(self, item: dict) -> tuple[bool, str]:
        t, p = item["type"], item.get("params", {})
        if t == "seat_access":
            have = self.api.user_license_skus(self.s["id"])
            need = {self.kit.sku_id(x) for x in self.kit.cfg.licences["seat_skus"]}
            if not need <= have:
                return False, "seat licences missing"
            if not self.api.is_group_member(self.kit.seat_group()["id"], self.s["id"]):
                return False, "seat is not in the Cowork seat group"
            if not self.s.get("tap"):
                return False, "no Temporary Access Pass"
            return True, "licensed, in seat group, TAP issued"
        if t == "mail_thread":
            want = p["subject_contains"].lower()
            thread = [m for m in self.inbox() if want in (m.get("subject") or "").lower()]
            convs = {m.get("conversationId") for m in thread}
            ok = len(thread) == p["count"]
            note = f"{len(thread)} messages" + ("" if len(convs) <= 1 else f" across {len(convs)} conversations")
            return ok, note
        if t == "channel_messages":
            n = sum(1 + len(m.get("replies", [])) for m in self.posts())
            return n == p["count"], f"{n} messages"
        if t == "channel_files":
            names = set(self.files(p.get("folder")))
            missing = [x for x in p["names"] if x not in names]
            return not missing, ("missing: " + ", ".join(missing)) if missing else f"{len(p['names'])} files"
        if t == "calendar_window":
            evs = [e for e in self.api.calendar_view(self.s["id"], self.tl.utc_iso(p["from"]), self.tl.utc_iso(p["to"]))
                   if not e.get("isCancelled")]
            spans = sorted((_ts(e["start"]["dateTime"]), _ts(e["end"]["dateTime"])) for e in evs)
            overlaps = sum(1 for i in range(len(spans) - 1) if spans[i][1] > spans[i + 1][0])
            busy = []
            for slot in p.get("free_slots", []):
                a = self.tl.utc(slot)
                b = a + timedelta(minutes=p.get("slot_minutes", 30))
                if any(s < b and a < e for s, e in spans):
                    busy.append(slot)
            ok = len(evs) == p["count"] and overlaps >= p.get("min_overlaps", 0) and not busy
            return ok, f"{len(evs)} meetings, {overlaps} overlap(s)" + (f", busy: {busy}" if busy else "")
        raise ValueError(f"unknown day-one type {t}")

    # facts ---------------------------------------------------------------
    def anchor(self, a: dict) -> tuple[bool, str]:
        k = a["kind"]
        if k == "mail":
            mid = self.s.get("mail", {}).get(a["id"])
            m = next((x for x in self.inbox() if x["id"] == mid), None)
            if not m:
                return False, f"mail {a['id']} missing"
            body = (m.get("body") or {}).get("content", "")
            miss = [c for c in a["contains"] if c.lower() not in body.lower()]
            return not miss, f"mail {a['id']}" + (f" lacks {miss}" if miss else "")
        if k == "post":
            pid = self.s.get("posts", {}).get(a["id"])
            m = next((x for x in self.posts() if x["id"] == pid), None)
            if not m:
                return False, f"post {a['id']} missing"
            body = m["body"]["content"]
            miss = [c for c in a["contains"] if c.lower() not in body.lower()]
            return not miss, f"post {a['id']}" + (f" lacks {miss}" if miss else "")
        if k == "file":
            txt = self.file_text(a["name"])
            miss = [c for c in a["contains"] if c.lower() not in txt.lower()]
            return not miss, a["name"] + (f" lacks {miss}" if miss else "")
        if k == "event":
            rec = self.s.get("events", {}).get(a["id"], {})
            ev = self.api.find_event_by_ical(self.s["id"], rec.get("ical", "")) if rec else None
            ok = bool(ev) and ev.get("subject", "").lower() == a["subject"].lower()
            return ok, f"event {a['id']}" + ("" if ok else " missing")
        raise ValueError(f"unknown anchor kind {k}")

    # indexing ------------------------------------------------------------
    def indexed(self, item: dict) -> tuple[bool, str]:
        if item["type"] == "mail_search":
            n = len(self.api.search_messages(self.s["id"], item["query"]))
        else:
            root = self.api.channel_files_folder(self.s["team_id"], self.s["channel_id"])
            n = len(self.api.search_drive(root["drive_id"], item["query"]))
        return n >= item["min"], f"{n} hit(s) for {item['query']!r}"


def _ts(iso: str):
    import re
    from datetime import datetime, timezone
    iso = re.sub(r"(\.\d{6})\d+", r"\1", iso.replace("Z", "+00:00"))  # Graph returns 7 fractional digits
    d = datetime.fromisoformat(iso)
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def check_seat(kit: Kit, seat: dict) -> dict:
    cs = kit.check_set
    probe = SeatProbe(kit, seat)
    res = {"at": now_iso(), "day_one": {}, "facts": {}, "indexing": {}, "integrity": {}}
    hard_fail, pending = [], []
    tl = probe.tl

    if tl.lab_day < kit.now().astimezone(kit.tz).date():
        hard_fail.append(f"lab day {tl.lab_day} has passed")

    for item in cs["day_one"]:
        try:
            ok, why = probe.day_one(item)
        except TenantError as e:
            ok, why = False, f"error: {e}"
        res["day_one"][item["id"]] = {"ok": ok, "detail": why}
        if not ok:
            hard_fail.append(f"{item['id']}: {why}")

    for f in cs["facts"]:
        out = []
        for a in f["anchors"]:
            try:
                out.append(probe.anchor(a))
            except TenantError as e:
                out.append((False, f"error: {e}"))
        ok = all(o for o, _ in out)
        res["facts"][f["id"]] = {"ok": ok, "detail": "; ".join(w for _, w in out)}
        if not ok:
            hard_fail.append(f"{f['id']}: " + "; ".join(w for o, w in out if not o))

    for item in cs["indexing"]:
        try:
            ok, why = probe.indexed(item)
        except TenantError as e:
            ok, why = False, f"error: {e}"
        res["indexing"][item["id"]] = {"ok": ok, "detail": why}
        if not ok:
            pending.append(f"{item['id']}: {why}")

    expected = dict(cs["integrity"]["expected"])
    for cid, g in kit.scorecard.get("guards", {}).items():
        if g.get("enabled"):
            expected[cid] = 0  # guarded checks cannot pass on a fresh seat
    sc = evaluate(kit, seat)
    wrong = {k: v for k, v in sc["checks"].items() if v != expected.get(k, 0)}
    res["integrity"] = {"ok": not wrong, "detail": f"baseline score {sc['score']}"
                        + (f"; unexpected: {wrong}" if wrong else "")}
    if wrong:
        hard_fail.append(f"integrity: seat already satisfies {sorted(wrong)}")

    res["state"] = "failed" if hard_fail else ("pending" if pending else "ready")
    res["reasons"] = hard_fail or pending
    return res


def run(kit: Kit, args) -> tuple[int, dict]:
    st = kit.state
    if args.seat:
        if args.seat not in st.seats:
            return 3, {"error": f"unknown seat {args.seat}"}
        targets = [args.seat]
    else:
        states = ("hydrated", "ready") if args.all else ("hydrated",)
        targets = [u for u, s in st.seats.items() if s["state"] in states]
    results = {}

    def work(upn):
        s = st.seats[upn]
        try:
            r = check_seat(kit, s)
        except TenantError as e:
            r = {"state": "pending", "reasons": [f"error: {e}"], "at": now_iso()}
        s["check"] = r
        if r["state"] == "ready":
            s["state"] = "ready"
        elif r["state"] == "failed":
            s["state"] = "failed"
        else:
            s["state"] = "hydrated"  # pending: keep for the next run
        st.save()
        results[upn] = r

    with ThreadPoolExecutor(max_workers=kit.concurrency) as pool:
        list(pool.map(work, targets))
    inv = write_inventory(kit.cfg.out_dir, st)
    counts = {k: sum(1 for r in results.values() if r["state"] == k) for k in ("ready", "pending", "failed")}
    body = {"checked": len(results), **counts,
            "inventory": str(inv), "ready_in_pool": sum(1 for s in st.seats.values() if s["state"] == "ready"),
            "seats": {u: {"state": r["state"], "reasons": r.get("reasons", [])} for u, r in results.items()},
            "copilot_spot_check": [f["copilot_question"] for f in kit.check_set["facts"]]}
    if counts["pending"]:
        body["next"] = "Some seats are still indexing. Wait, then re-run `check`."
    if counts["failed"]:
        body["failed_next"] = "Retire failed seats (`retire --seat <upn>`) and hydrate replacements (`seats --count 1`)."
    return (2 if counts["failed"] else 0), body
