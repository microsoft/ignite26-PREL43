"""`seats --count N`: create, license and hydrate N new learner seats.

Each seat gets its own copy of the Helix launch: mail in its Inbox, its own
"Zava Product Launches" team with the Launch - Helix channel and files, and
four upcoming meetings (plus four past ones) organised by personas.

Seats are created in batches. If a batch is interrupted (exit code 2), running
`seats` again resumes that batch instead of starting a new one. Every phase of
every seat is recorded in out/state.json, so nothing is written twice.
"""
from __future__ import annotations

import base64
import hashlib
import html
import logging
import os
import re
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from ..api.base import NotReady, TenantError
from ..config import ConfigError
from ..kit import Kit
from ..render import Context, render, render_office, text_to_html
from ..state import now_iso
from ..timeline import Timeline

log = logging.getLogger("vs_hydrate.seats")

PHASES = ["user", "licence", "group", "mailbox", "profile", "team", "posts", "complete", "members",
          "files", "mail", "calendar", "invites", "tap"]


# --------------------------------------------------------------------------- conversation threading
def _filetime(dt: datetime) -> int:
    return int((dt - datetime(1601, 1, 1, tzinfo=timezone.utc)).total_seconds() * 10_000_000)


def conversation_index(parent: bytes | None, first: datetime, this: datetime, seed: str, seq: int) -> bytes:
    """PidTagConversationIndex (MS-OXOMSG 2.2.1.3).

    A thread starter gets a 22-byte header (reserved byte, 5 bytes of FILETIME,
    a GUID). Each reply appends one 5-byte block to its parent's index holding
    the time since the header.
    """
    ft0 = _filetime(first)
    if parent is None:
        return b"\x01" + ft0.to_bytes(8, "big")[:5] + uuid.uuid5(uuid.NAMESPACE_URL, seed).bytes
    base = int.from_bytes(parent[1:6] + b"\x00\x00\x00", "big")
    delta = max(0, _filetime(this) - base)
    if delta < (1 << 49):
        val, code = (delta >> 18) & 0x7FFFFFFF, 0
    else:
        val, code = (delta >> 23) & 0x7FFFFFFF, 1
    return parent + ((code << 31) | val).to_bytes(4, "big") + bytes([((seq * 7) % 16) << 4 | (seq % 16)])


# --------------------------------------------------------------------------- builders
class SeatWriter:
    def __init__(self, kit: Kit, seat: dict, tl: Timeline, delay: float):
        self.kit, self.s, self.tl, self.delay = kit, seat, tl, delay
        self.api, self.pack, self.cfg = kit.api, kit.pack, kit.cfg
        self.ctx: Context = kit.learner_context(seat["upn"], tl)

    # people ---------------------------------------------------------------
    def addr(self, key: str) -> dict:
        if key == "learner":
            return {"name": self.ctx.learner, "address": self.s["upn"]}
        return self.pack.address(key, self.cfg.domain)

    def recip(self, keys: list[str]) -> list[dict]:
        return [{"emailAddress": self.addr(k)} for k in keys]

    def user_ref(self, key: str) -> dict:
        uid = self.s["id"] if key == "learner" else self.kit.persona_id(key)
        name = self.ctx.learner if key == "learner" else self.pack.display(self.pack.person(key))
        return {"user": {"id": uid, "displayName": name, "userIdentityType": "aadUser"}}

    def wait(self, what: str, probe, attempts: int) -> None:
        for i in range(attempts):
            if probe():
                return
            if i < attempts - 1:
                time.sleep(self.delay * min(6, i + 1))
        raise NotReady(f"{what} not ready yet")

    # phases ---------------------------------------------------------------
    def p_user(self):
        st, seat = self.cfg.seats, self.pack.people["seat"]
        existing = self.api.get_user(self.s["upn"])
        if existing:
            self.s["id"] = existing["id"]
            return
        from .tenant import random_password
        u = self.api.create_user({
            "accountEnabled": True, "userPrincipalName": self.s["upn"], "mailNickname": self.s["upn"].split("@")[0],
            "displayName": self.ctx.learner, "givenName": st["given_name"], "surname": st["surname"],
            "jobTitle": seat["title"], "department": seat["department"], "officeLocation": seat["office"],
            "companyName": self.pack.company["name"], "usageLocation": st["usage_location"],
            "passwordProfile": {"forceChangePasswordNextSignIn": True, "password": random_password()}})
        self.s["id"] = u["id"]

    def p_licence(self):
        have = self.api.user_license_skus(self.s["id"])
        add = [self.kit.sku_id(p) for p in self.cfg.licences["seat_skus"]]
        add = [a for a in add if a not in have]
        if add:
            self.api.assign_licenses(self.s["id"], add)

    def p_group(self):
        self.api.add_group_member(self.kit.seat_group()["id"], self.s["id"])

    def p_mailbox(self):
        attempts = max(1, int(self.cfg.seats["provisioning_timeout_minutes"] * 60 / max(self.delay * 6, 1)))
        self.wait("seat mailbox", lambda: self.api.mailbox_ready(self.s["id"]), attempts if self.delay else 1)

    def p_profile(self):
        self.api.set_mailbox_settings(self.s["id"], self.cfg.seats["time_zone"], self.cfg.seats.get("locale"))
        mgr = self.pack.people["seat"].get("manager")
        if mgr:
            self.api.set_manager(self.s["id"], self.kit.persona_id(mgr))

    def p_team(self):
        team = self.pack.team
        if not self.s.get("team_id"):
            self.s["team_id"] = self.api.create_migration_team(
                team["display_name"], team["description"], self.tl.utc_iso(team["created"]))
            self.kit.state.save()
        if not self.s.get("channel_id"):
            ch = self.pack.channel
            self.s["channel_id"] = self.api.create_migration_channel(
                self.s["team_id"], ch["name"], ch["description"], self.tl.utc_iso(ch["created"]))
            self.kit.state.save()

    def teams_body(self, text: str) -> tuple[str, list]:
        parts = re.split(r"\{\{\s*mention:learner\s*\}\}", text.strip())
        mentions = []
        out = html.escape(render(parts[0], self.ctx))
        for i, rest in enumerate(parts[1:]):
            out += f'<at id="{i}">{html.escape(self.ctx.learner)}</at>' + html.escape(render(rest, self.ctx))
            mentions.append({"id": i, "mentionText": self.ctx.learner, "mentioned": self.user_ref("learner")})
        return out.replace("\n", "<br>"), mentions

    def p_posts(self):
        posted = self.s.setdefault("posts", {})
        for p in self.pack.posts:
            if p["id"] not in posted:
                content, mentions = self.teams_body(p["body"])
                msg = {"createdDateTime": self.tl.utc_iso(p["sent"]), "from": self.user_ref(p["from"]),
                       "body": {"contentType": "html", "content": content}}
                if mentions:
                    msg["mentions"] = mentions
                posted[p["id"]] = self.api.import_message(self.s["team_id"], self.s["channel_id"], msg)
                self.kit.state.save()
            for i, r in enumerate(p.get("replies", []), 1):
                rid = f"{p['id']}#{i}"
                if rid in posted:
                    continue
                content, _ = self.teams_body(r["body"])
                posted[rid] = self.api.import_message(
                    self.s["team_id"], self.s["channel_id"],
                    {"createdDateTime": self.tl.utc_iso(r["sent"]), "from": self.user_ref(r["from"]),
                     "body": {"contentType": "html", "content": content}}, reply_to=posted[p["id"]])
                self.kit.state.save()

    def p_complete(self):
        for ch in self.api.list_channels(self.s["team_id"]):
            self.api.complete_channel_migration(self.s["team_id"], ch["id"])
        self.api.complete_team_migration(self.s["team_id"])

    def p_members(self):
        self.api.add_team_member(self.s["team_id"], self.s["id"], owner=True)
        if self.cfg.seats.get("team_add_personas"):
            keys = {p["from"] for p in self.pack.posts}
            for k in sorted(keys):
                self.api.add_team_member(self.s["team_id"], self.kit.persona_id(k), owner=False)

    def p_files(self):
        folder = {}

        def probe():
            try:
                folder.update(self.api.channel_files_folder(self.s["team_id"], self.s["channel_id"]))
                return True
            except NotReady:
                return False
        self.wait("channel files folder", probe, 20 if self.delay else 1)
        uploaded = self.s.setdefault("files", {})
        parents = {None: folder["id"]}
        for sub, name in self.pack.file_layout():
            if name in uploaded:
                continue
            if sub not in parents:
                parents[sub] = self.api.ensure_folder(folder["drive_id"], folder["id"], sub)
            data = render_office(name, self.pack.files[name], self.ctx)
            uploaded[name] = self.api.upload_file(folder["drive_id"], parents[sub], name, data)
            self.kit.state.save()
        self.s["channel_drive"] = folder["drive_id"]

    def p_mail(self):
        created = self.s.setdefault("mail", {})
        local = self.s["upn"].split("@")[0]
        msgs = sorted(self.pack.messages, key=lambda m: self.tl.utc(m["sent"]))
        threads: dict[str, list[dict]] = {}
        for m in msgs:
            conv = m.get("conversation")
            chain = threads.setdefault(conv, []) if conv else []
            msgid = f"<{m['id']}.{local}.{hashlib.sha1(self.s['upn'].encode()).hexdigest()[:8]}@helix.zava.example>"
            sent = self.tl.utc(m["sent"])
            props = [
                {"id": "Integer 0x0E07", "value": "1"},                          # not a draft
                {"id": "SystemTime 0x0039", "value": self.tl.utc_iso(m["sent"])},  # sent
                {"id": "SystemTime 0x0E06", "value": self.tl.utc_iso(m["sent"])},  # received
                {"id": "String 0x1035", "value": msgid},                          # Message-ID
            ]
            if conv:
                topic = re.sub(r"^(RE|FW):\s*", "", m["subject"], flags=re.I)
                first = self.tl.utc(chain[0]["sent"]) if chain else sent
                idx = conversation_index(chain[-1]["index"] if chain else None, first, sent,
                                         f"{self.s['upn']}/{conv}", len(chain))
                props += [{"id": "String 0x0070", "value": topic},
                          {"id": "Binary 0x0071", "value": base64.b64encode(idx).decode()}]
                if chain:
                    props += [{"id": "String 0x1042", "value": chain[-1]["msgid"]},
                              {"id": "String 0x1039", "value": " ".join(c["msgid"] for c in chain)}]
                chain.append({"sent": m["sent"], "msgid": msgid, "index": idx})
            if m["id"] in created:
                continue
            body = {
                "subject": render(m["subject"], self.ctx),
                "body": {"contentType": "HTML", "content": text_to_html(render(m["body"], self.ctx))},
                "from": {"emailAddress": self.addr(m["from"])},
                "sender": {"emailAddress": self.addr(m["from"])},
                "toRecipients": self.recip(m.get("to", [])),
                "ccRecipients": self.recip(m.get("cc", [])),
                "importance": m.get("importance", "normal"),
                "singleValueExtendedProperties": props,
            }
            if m.get("flag"):
                body["flag"] = {"flagStatus": "flagged"}
            mid = self.api.create_message(self.s["id"], "inbox", body)
            if not m.get("read", True):
                self.api.update_message(self.s["id"], mid, {"isRead": False})
            created[m["id"]] = mid
            self.kit.state.save()

    def p_calendar(self):
        evs = self.s.setdefault("events", {})
        tz = self.cfg.seats["time_zone"]
        for e in self.pack.events:
            rec = evs.get(e["id"])
            if not rec:
                org = self.kit.persona_id(e["organiser"])
                r = self.api.create_event(org, {
                    "subject": e["subject"], "body": {"contentType": "text", "content": e.get("body", "")},
                    "start": {"dateTime": self.tl.local_iso(e["start"]), "timeZone": tz},
                    "end": {"dateTime": self.tl.local_iso(e["end"]), "timeZone": tz},
                    "attendees": [{"emailAddress": self.addr(k), "type": "required"} for k in e["attendees"]],
                    "allowNewTimeProposals": False, "isReminderOn": False,
                    "transactionId": f"vs-{self.s['upn']}-{e['id']}"})
                rec = evs[e["id"]] = {"organiser_id": org, "id": r["id"], "ical": r["iCalUId"]}
                self.kit.state.save()
            if not rec.get("seat_event_id"):
                found = {}

                def probe(rec=rec):
                    ev = self.api.find_event_by_ical(self.s["id"], rec["ical"])
                    if ev:
                        found["ev"] = ev
                    return bool(ev)
                self.wait(f"invitation {e['id']}", probe, 15 if self.delay else 1)
                self.api.accept_event(self.s["id"], found["ev"]["id"])
                rec["seat_event_id"] = found["ev"]["id"]
                self.kit.state.save()

    def p_invites(self):
        """Remove the meeting-request messages the invitations left in the Inbox."""
        for m in self.api.list_messages(self.s["id"], "inbox", top=60):
            if "eventMessage" in m.get("@odata.type", ""):
                self.api.delete_message(self.s["id"], m["id"])

    def p_tap(self):
        if self.s.get("tap"):
            return
        start = max(self.tl.utc("D 00:00") - timedelta(hours=2), datetime.now(timezone.utc) + timedelta(minutes=1))
        self.s["tap"] = self.api.create_tap(self.s["id"], start.strftime("%Y-%m-%dT%H:%M:%SZ"),
                                            int(self.cfg.seats["tap_lifetime_minutes"]))

    def run(self) -> str:
        for phase in PHASES:
            if self.kit.state.done(self.s, phase):
                continue
            getattr(self, f"p_{phase}")()
            self.kit.state.mark(self.s, phase)
        self.s["state"] = "hydrated"
        self.s["hydrated_at"] = now_iso()
        self.kit.state.save()
        return "hydrated"


# --------------------------------------------------------------------------- command
def next_indexes(kit: Kit, n: int) -> list[int]:
    prefix, dom = kit.cfg.seats["prefix"], kit.cfg.domain
    used = set()
    for upn in kit.state.seats:
        m = re.match(rf"^{prefix}(\d+)@", upn)
        if m:
            used.add(int(m.group(1)))
    for u in kit.api.list_users_with_prefix(prefix, dom):
        m = re.match(rf"^{prefix}(\d+)@", u["userPrincipalName"].lower())
        if m:
            used.add(int(m.group(1)))
    start = max(used, default=0) + 1
    return list(range(start, start + n))


def run(kit: Kit, args) -> tuple[int, dict]:
    st = kit.state
    batches = st.data.setdefault("batches", [])
    last = batches[-1] if batches else None
    resuming = bool(last and not last.get("complete"))
    if resuming:
        batch = last
        if args.count and args.count != batch["target"]:
            log.warning("resuming unfinished batch %s (target %d); --count %d ignored",
                        batch["id"], batch["target"], args.count)
    else:
        if not args.count or args.count < 1:
            raise ConfigError("seats needs --count N (N >= 1)")
        tl = kit.timeline()
        batch = {"id": datetime.now(timezone.utc).strftime("b%Y%m%d%H%M%S"), "target": args.count,
                 "lab_day": tl.lab_day.isoformat(), "seats": [], "complete": False}
        batches.append(batch)
    tl = kit.timeline(batch["lab_day"])

    # Teams import refuses future timestamps: all seeded content must be in the past.
    earliest = tl.utc(kit.pack.latest_content) + timedelta(minutes=30)
    if kit.now() < earliest and not kit.dry_run:
        if not resuming:
            batches.pop()
        raise ConfigError(
            f"too early to hydrate for lab day {tl.lab_day}: seeded content runs to {kit.pack.latest_content}. "
            f"Run `seats` after {earliest.astimezone(kit.tz):%Y-%m-%d %H:%M} ({kit.tz.key}).")

    if not kit.state.tenant.get("personas"):
        raise ConfigError("personas not found; run `tenant` first")
    organisers = {e["organiser"] for e in kit.pack.events}
    not_ready = [k for k in sorted(organisers) if not kit.api.mailbox_ready(kit.persona_id(k))]
    if not_ready:
        st.save()
        return 2, {"batch": batch["id"], "waiting": f"persona mailboxes still provisioning: {', '.join(not_ready)}",
                   "next": "Wait a few minutes, then re-run `seats`."}

    missing = batch["target"] - len(batch["seats"])
    if missing > 0:
        for i in next_indexes(kit, missing):
            upn = f"{kit.cfg.seats['prefix']}{i:04d}@{kit.cfg.domain}"
            s = st.seat(upn)
            s.update({"index": i, "lab_day": batch["lab_day"], "datapack": kit.pack.version,
                      "batch": batch["id"], "created_at": now_iso()})
            batch["seats"].append(upn)
        st.save()

    delay = 0.0 if kit.cfg.offline else float(os.environ.get("VS_POLL_SECONDS", "10"))
    results: dict[str, str] = {}
    errors: dict[str, str] = {}
    lock = threading.Lock()

    def work(upn: str):
        s = st.seats[upn]
        if s["state"] != "provisioning":
            with lock:
                results[upn] = f"{s['state']} (earlier run)"
            return
        try:
            outcome = SeatWriter(kit, s, tl, delay).run()
        except NotReady as e:
            outcome = "waiting"
            s.setdefault("log", []).append(f"{now_iso()} waiting: {e}")
        except TenantError as e:
            outcome = "error"
            s.setdefault("log", []).append(f"{now_iso()} error: {e}")
            with lock:
                errors[upn] = str(e)
        st.save()
        with lock:
            results[upn] = outcome

    with ThreadPoolExecutor(max_workers=kit.concurrency) as pool:
        list(pool.map(work, list(batch["seats"])))

    pending = [u for u, r in results.items() if r in ("waiting", "error")]
    batch["complete"] = not pending and len(batch["seats"]) == batch["target"]
    st.save()
    hydrated = [u for u, r in results.items() if r == "hydrated"]
    body = {"batch": batch["id"], "resumed": resuming, "lab_day": batch["lab_day"], "target": batch["target"],
            "hydrated": len(hydrated), "pending": pending, "errors": errors,
            "seats": [{"upn": u, "result": results.get(u)} for u in batch["seats"]]}
    if kit.dry_run:
        body["planned_writes"] = kit.api.planned[:200]
        body["planned_write_count"] = len(kit.api.planned)
    if pending:
        body["next"] = "Re-run `seats` to resume this batch."
    else:
        body["next"] = "Wait for indexing, then run `check`."
    return (2 if pending else 0), body
