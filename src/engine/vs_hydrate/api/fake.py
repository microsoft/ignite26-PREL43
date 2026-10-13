"""In-memory tenant for tests and offline rehearsals.

Behaves like the parts of Microsoft 365 the kit touches, including the rules
that bite in real tenants: Teams import only accepts past timestamps after the
channel was created and only before migration completes; invitations land in
attendee calendars with the organiser's iCalUId; a licensed user gets a
mailbox and a OneDrive. State can be saved to JSON so separate CLI runs
(`tenant`, `seats`, `check`, `score`) share one fake tenant.
"""
from __future__ import annotations

import base64
import json
import re
import uuid
from datetime import datetime, timezone
from pathlib import Path

from .base import NotReady, TenantAPI, TenantError

ALL_ROLES = {
    "User.ReadWrite.All", "Group.ReadWrite.All", "Mail.ReadWrite", "Calendars.ReadWrite",
    "Files.ReadWrite.All", "Sites.ReadWrite.All", "Teamwork.Migrate.All", "TeamMember.ReadWrite.All",
    "ChannelMessage.Read.All", "MailboxSettings.ReadWrite", "UserAuthenticationMethod.ReadWrite.All",
    "Organization.Read.All",
}
SKUS = [
    {"skuId": "sku-e5", "skuPartNumber": "SPE_E5", "prepaidUnits": {"enabled": 500}, "consumedUnits": 0},
    {"skuId": "sku-e3", "skuPartNumber": "SPE_E3", "prepaidUnits": {"enabled": 500}, "consumedUnits": 0},
    {"skuId": "sku-copilot", "skuPartNumber": "Microsoft_365_Copilot", "prepaidUnits": {"enabled": 500}, "consumedUnits": 0},
]


def _id() -> str:
    return str(uuid.uuid4())


def _parse(iso: str) -> datetime:
    return datetime.fromisoformat(iso.replace("Z", "+00:00"))


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _norm_subject(s: str) -> str:
    return re.sub(r"^((re|fw|fwd):\s*)+", "", s or "", flags=re.I).strip().lower()


class FakeTenant(TenantAPI):
    def __init__(self, groups: list[str] | None = None, roles: set[str] | None = None,
                 path: str | Path | None = None):
        self.path = Path(path) if path else None
        self.roles = set(roles if roles is not None else ALL_ROLES)
        self.skus = json.loads(json.dumps(SKUS))
        self.users: dict[str, dict] = {}
        self.groups: dict[str, dict] = {}
        self.mail: dict[str, list[dict]] = {}
        self.events: dict[str, list[dict]] = {}
        self.teams: dict[str, dict] = {}
        self.drives: dict[str, dict] = {}
        for g in groups or []:
            gid = _id()
            self.groups[gid] = {"id": gid, "displayName": g, "members": []}

    # ---------------------------------------------------------------- persistence
    @classmethod
    def open(cls, path: str | Path, groups: list[str]) -> "FakeTenant":
        p = Path(path)
        t = cls(groups=[] if p.exists() else groups, path=p)
        if p.exists():
            d = json.loads(p.read_text())
            for k in ("users", "groups", "mail", "events", "teams", "skus"):
                setattr(t, k, d[k])
            t.roles = set(d["roles"])
            t.drives = {k: {**v, "items": {i: {**it, "data": base64.b64decode(it["data"]) if it.get("data") is not None else None}
                                           for i, it in v["items"].items()}} for k, v in d["drives"].items()}
            for g in groups:
                if not any(x["displayName"] == g for x in t.groups.values()):
                    gid = _id()
                    t.groups[gid] = {"id": gid, "displayName": g, "members": []}
        return t

    def save(self) -> None:
        if not self.path:
            return
        drives = {k: {**v, "items": {i: {**it, "data": base64.b64encode(it["data"]).decode() if it.get("data") is not None else None}
                                     for i, it in v["items"].items()}} for k, v in self.drives.items()}
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps({"users": self.users, "groups": self.groups, "mail": self.mail,
                                         "events": self.events, "teams": self.teams, "skus": self.skus,
                                         "roles": sorted(self.roles), "drives": drives}))

    # ---------------------------------------------------------------- helpers
    def _user(self, user_id: str) -> dict:
        u = self.users.get(user_id)
        if not u:
            raise TenantError(f"user {user_id} not found", status=404)
        return u

    def _by_address(self, address: str) -> dict | None:
        a = address.lower()
        return next((u for u in self.users.values() if u["userPrincipalName"].lower() == a), None)

    def _licensed(self, user_id: str) -> bool:
        return bool(self._user(user_id)["licenses"])

    # ---------------------------------------------------------------- tenant
    def granted_roles(self) -> set[str]:
        return set(self.roles)

    def subscribed_skus(self) -> list[dict]:
        for s in self.skus:
            s["consumedUnits"] = sum(1 for u in self.users.values() if s["skuId"] in u["licenses"])
        return self.skus

    # ---------------------------------------------------------------- users
    def get_user(self, upn: str) -> dict | None:
        u = self._by_address(upn)
        return {k: v for k, v in u.items() if k not in ("photo",)} if u else None

    def list_users_with_prefix(self, prefix: str, domain: str) -> list[dict]:
        return [u for u in self.users.values()
                if u["userPrincipalName"].lower().startswith(prefix.lower())
                and u["userPrincipalName"].lower().endswith("@" + domain.lower())]

    def create_user(self, body: dict) -> dict:
        if self._by_address(body["userPrincipalName"]):
            raise TenantError("userPrincipalName already exists", status=400)
        uid = _id()
        self.users[uid] = {"id": uid, **{k: v for k, v in body.items() if k != "passwordProfile"},
                           "licenses": [], "manager": None, "photo": False, "taps": [],
                           "mailboxSettings": {}, "createdDateTime": _now().isoformat()}
        return self.users[uid]

    def update_user(self, user_id: str, body: dict) -> None:
        self._user(user_id).update(body)

    def delete_user(self, user_id: str, permanent: bool = False) -> None:
        if user_id not in self.users:
            return
        for g in self.groups.values():
            if user_id in g["members"]:
                g["members"].remove(user_id)
        drive = self.users[user_id].get("drive")
        self.drives.pop(drive, None)
        self.users.pop(user_id)
        self.mail.pop(user_id, None)
        self.events.pop(user_id, None)

    def set_manager(self, user_id: str, manager_id: str) -> None:
        self._user(manager_id)
        self._user(user_id)["manager"] = manager_id

    def set_photo(self, user_id: str, png: bytes) -> None:
        if not self.mailbox_ready(user_id):
            raise NotReady("mailbox not ready")
        self._user(user_id)["photo"] = True

    def assign_licenses(self, user_id: str, add: list[str], remove: list[str] | None = None) -> None:
        u = self._user(user_id)
        if add and not u.get("usageLocation"):
            raise TenantError("License assignment failed because of invalid usage location", status=400)
        known = {s["skuId"] for s in self.skus}
        for s in add:
            if s not in known:
                raise TenantError(f"unknown sku {s}", status=400)
            if s not in u["licenses"]:
                u["licenses"].append(s)
        for s in remove or []:
            if s in u["licenses"]:
                u["licenses"].remove(s)

    def user_license_skus(self, user_id: str) -> set[str]:
        return set(self._user(user_id)["licenses"])

    def create_tap(self, user_id: str, start_iso: str, lifetime_minutes: int) -> str:
        u = self._user(user_id)
        if u["taps"]:
            raise TenantError("user already has a Temporary Access Pass", status=400)
        tap = "TAP-" + uuid.uuid4().hex[:10]
        u["taps"].append({"start": start_iso, "lifetime": lifetime_minutes})
        return tap

    # ---------------------------------------------------------------- groups
    def find_group(self, display_name: str) -> dict | None:
        g = next((g for g in self.groups.values() if g["displayName"] == display_name), None)
        return {"id": g["id"], "displayName": g["displayName"]} if g else None

    def add_group_member(self, group_id: str, user_id: str) -> None:
        g = self.groups[group_id]
        if user_id not in g["members"]:
            g["members"].append(user_id)

    def is_group_member(self, group_id: str, user_id: str) -> bool:
        return user_id in self.groups.get(group_id, {}).get("members", [])

    def delete_group(self, group_id: str) -> None:
        t = self.teams.pop(group_id, None)
        if t:
            self.drives.pop(t.get("drive"), None)
        self.groups.pop(group_id, None)

    # ---------------------------------------------------------------- mailbox
    def mailbox_ready(self, user_id: str) -> bool:
        return self._licensed(user_id)

    def set_mailbox_settings(self, user_id: str, time_zone: str, locale: str | None) -> None:
        if not self.mailbox_ready(user_id):
            raise NotReady("mailbox not ready")
        self._user(user_id)["mailboxSettings"] = {"timeZone": time_zone, "locale": locale}

    def create_message(self, user_id: str, folder: str, message: dict) -> str:
        if not self.mailbox_ready(user_id):
            raise NotReady("mailbox not ready")
        props = {p["id"]: p["value"] for p in message.get("singleValueExtendedProperties", [])}
        received = props.get("SystemTime 0x0E06") or _now().isoformat()
        mid = _id()
        topic = props.get("String 0x0070") or _norm_subject(message.get("subject", ""))
        self.mail.setdefault(user_id, []).append({
            "id": mid, "folder": folder, "subject": message.get("subject", ""),
            "body": message.get("body", {}).get("content", ""),
            "from": message.get("from"), "receivedDateTime": received,
            "isRead": props.get("Integer 0x0E07") == "1",
            "isDraft": "Integer 0x0E07" not in props,
            "conversationId": "conv-" + str(uuid.uuid5(uuid.NAMESPACE_URL, user_id + topic.lower())),
            "importance": message.get("importance", "normal"), "flag": message.get("flag", {}),
            "@odata.type": message.get("@odata.type", "#microsoft.graph.message")})
        return mid

    def _msg(self, user_id: str, message_id: str) -> dict:
        for m in self.mail.get(user_id, []):
            if m["id"] == message_id:
                return m
        raise TenantError("message not found", status=404)

    def update_message(self, user_id: str, message_id: str, patch: dict) -> None:
        self._msg(user_id, message_id).update(patch)

    def delete_message(self, user_id: str, message_id: str) -> None:
        self.mail[user_id] = [m for m in self.mail.get(user_id, []) if m["id"] != message_id]

    def list_messages(self, user_id: str, folder: str, top: int = 200, with_body: bool = False) -> list[dict]:
        ms = [m for m in self.mail.get(user_id, []) if m["folder"] == folder]
        ms.sort(key=lambda m: m["receivedDateTime"], reverse=True)
        out = []
        for m in ms[:top]:
            d = dict(m)
            if with_body:
                d["body"] = {"contentType": "text", "content": re.sub(r"<[^>]+>", " ", m["body"])}
            else:
                d.pop("body", None)
            out.append(d)
        return out

    def search_messages(self, user_id: str, query: str, top: int = 25) -> list[dict]:
        q = query.lower()
        return [{"id": m["id"], "subject": m["subject"]} for m in self.mail.get(user_id, [])
                if q in m["subject"].lower() or q in m["body"].lower()][:top]

    # ---------------------------------------------------------------- calendar
    def create_event(self, organiser_id: str, event: dict) -> dict:
        if not self.mailbox_ready(organiser_id):
            raise NotReady("organiser mailbox not ready")
        cal = self.events.setdefault(organiser_id, [])
        tx = event.get("transactionId")
        for e in cal:
            if tx and e.get("transactionId") == tx:
                return {"id": e["id"], "iCalUId": e["iCalUId"]}
        ical = "ical-" + uuid.uuid4().hex
        base = {"subject": event["subject"], "start": event["start"], "end": event["end"],
                "isCancelled": False, "type": "singleInstance", "iCalUId": ical,
                "organizer": {"emailAddress": self._user(organiser_id)["userPrincipalName"]}}
        ev = {**base, "id": _id(), "transactionId": tx, "responseStatus": {"response": "organizer"}}
        cal.append(ev)
        for a in event.get("attendees", []):
            u = self._by_address(a["emailAddress"]["address"])
            if u and self.mailbox_ready(u["id"]):
                self.events.setdefault(u["id"], []).append({**base, "id": _id(), "responseStatus": {"response": "notResponded"}})
                self.mail.setdefault(u["id"], []).append({
                    "id": _id(), "folder": "inbox", "subject": event["subject"], "body": "",
                    "from": {"emailAddress": {"address": self._user(organiser_id)["userPrincipalName"]}},
                    "receivedDateTime": _now().isoformat(), "isRead": False, "isDraft": False,
                    "conversationId": "conv-" + uuid.uuid4().hex, "importance": "normal", "flag": {},
                    "@odata.type": "#microsoft.graph.eventMessageRequest"})
        return {"id": ev["id"], "iCalUId": ical}

    def find_event_by_ical(self, user_id: str, ical_uid: str) -> dict | None:
        return next((e for e in self.events.get(user_id, []) if e["iCalUId"] == ical_uid), None)

    def accept_event(self, user_id: str, event_id: str) -> None:
        for e in self.events.get(user_id, []):
            if e["id"] == event_id:
                e["responseStatus"] = {"response": "accepted"}
                return
        raise TenantError("event not found", status=404)

    def delete_event(self, user_id: str, event_id: str) -> None:
        cal = self.events.get(user_id, [])
        ev = next((e for e in cal if e["id"] == event_id), None)
        if not ev:
            return
        cal.remove(ev)
        if ev["responseStatus"]["response"] == "organizer":
            for uid, other in self.events.items():
                for e in other:
                    if e["iCalUId"] == ev["iCalUId"]:
                        e["isCancelled"] = True

    def calendar_view(self, user_id: str, start_iso: str, end_iso: str) -> list[dict]:
        from zoneinfo import ZoneInfo

        from ..timeline import WINDOWS_TO_IANA
        s, e = _parse(start_iso), _parse(end_iso)
        out = []
        for ev in self.events.get(user_id, []):
            tz = ZoneInfo(WINDOWS_TO_IANA.get(ev["start"]["timeZone"], ev["start"]["timeZone"]))
            es = datetime.fromisoformat(ev["start"]["dateTime"]).replace(tzinfo=tz)
            ee = datetime.fromisoformat(ev["end"]["dateTime"]).replace(tzinfo=tz)
            if es < e and ee > s:
                out.append({**ev, "start": {"dateTime": es.astimezone(timezone.utc).isoformat(), "timeZone": "UTC"},
                            "end": {"dateTime": ee.astimezone(timezone.utc).isoformat(), "timeZone": "UTC"}})
        return out

    # ---------------------------------------------------------------- teams
    def create_migration_team(self, display_name: str, description: str, created_iso: str) -> str:
        if _parse(created_iso) > _now():
            raise TenantError("createdDateTime cannot be in the future", status=400)
        tid = _id()
        self.groups[tid] = {"id": tid, "displayName": display_name, "members": []}
        gen = _id()
        self.teams[tid] = {"id": tid, "name": display_name, "migration": True, "created": created_iso,
                           "members": [], "drive": None,
                           "channels": {gen: {"id": gen, "displayName": "General", "migration": True,
                                              "created": created_iso, "messages": []}}}
        return tid

    def _team(self, team_id: str) -> dict:
        t = self.teams.get(team_id)
        if not t:
            raise TenantError("team not found", status=404)
        return t

    def create_migration_channel(self, team_id: str, name: str, description: str, created_iso: str) -> str:
        t = self._team(team_id)
        if not t["migration"]:
            raise TenantError("team is not in migration mode", status=400)
        if _parse(created_iso) < _parse(t["created"]):
            raise TenantError("channel createdDateTime is before the team", status=400)
        cid = _id()
        t["channels"][cid] = {"id": cid, "displayName": name, "migration": True, "created": created_iso, "messages": []}
        return cid

    def list_channels(self, team_id: str) -> list[dict]:
        return [{"id": c["id"], "displayName": c["displayName"]} for c in self._team(team_id)["channels"].values()]

    def import_message(self, team_id: str, channel_id: str, message: dict, reply_to: str | None = None) -> str:
        ch = self._team(team_id)["channels"][channel_id]
        if not ch["migration"]:
            raise TenantError("channel is not in migration mode", status=400)
        created = _parse(message["createdDateTime"])
        if created > _now():
            raise TenantError("createdDateTime cannot be in the future", status=400)
        if created < _parse(ch["created"]):
            raise TenantError("message predates the channel", status=400)
        if not self.users.get(message["from"]["user"]["id"]):
            raise TenantError("from user not found", status=400)
        mid = _id()
        rec = {"id": mid, "createdDateTime": message["createdDateTime"], "from": message["from"],
               "body": message["body"], "mentions": message.get("mentions", []), "replies": []}
        if reply_to:
            parent = next(m for m in ch["messages"] if m["id"] == reply_to)
            parent["replies"].append(rec)
        else:
            ch["messages"].append(rec)
        return mid

    def complete_channel_migration(self, team_id: str, channel_id: str) -> None:
        self._team(team_id)["channels"][channel_id]["migration"] = False

    def complete_team_migration(self, team_id: str) -> None:
        t = self._team(team_id)
        if any(c["migration"] for c in t["channels"].values()):
            raise TenantError("complete every channel first", status=400)
        t["migration"] = False

    def add_team_member(self, team_id: str, user_id: str, owner: bool) -> None:
        t = self._team(team_id)
        if t["migration"]:
            raise TenantError("team is in migration mode", status=400)
        if user_id not in t["members"]:
            t["members"].append(user_id)
            self.groups[team_id]["members"].append(user_id)

    def list_channel_messages(self, team_id: str, channel_id: str) -> list[dict]:
        return json.loads(json.dumps(self._team(team_id)["channels"][channel_id]["messages"]))

    def team_exists(self, team_id: str) -> bool:
        return team_id in self.teams

    # ---------------------------------------------------------------- files
    def _new_drive(self) -> str:
        did = _id()
        root = _id()
        self.drives[did] = {"id": did, "root": root,
                            "items": {root: {"id": root, "name": "root", "parent": None, "folder": True, "data": None}}}
        return did

    def channel_files_folder(self, team_id: str, channel_id: str) -> dict:
        t = self._team(team_id)
        if t["migration"]:
            raise NotReady("files folder appears after migration completes")
        if not t["drive"]:
            t["drive"] = self._new_drive()
        d = self.drives[t["drive"]]
        ch = t["channels"][channel_id]
        fid = self.ensure_folder(t["drive"], d["root"], ch["displayName"])
        return {"drive_id": t["drive"], "id": fid}

    def ensure_folder(self, drive_id: str, parent_id: str, name: str) -> str:
        d = self.drives[drive_id]
        for it in d["items"].values():
            if it["parent"] == parent_id and it["name"] == name and it["folder"]:
                return it["id"]
        iid = _id()
        d["items"][iid] = {"id": iid, "name": name, "parent": parent_id, "folder": True, "data": None,
                           "lastModifiedDateTime": _now().isoformat()}
        return iid

    def upload_file(self, drive_id: str, parent_id: str, name: str, data: bytes) -> str:
        d = self.drives[drive_id]
        for it in d["items"].values():
            if it["parent"] == parent_id and it["name"] == name and not it["folder"]:
                it["data"] = data
                it["lastModifiedDateTime"] = _now().isoformat()
                return it["id"]
        iid = _id()
        d["items"][iid] = {"id": iid, "name": name, "parent": parent_id, "folder": False, "data": data,
                           "lastModifiedDateTime": _now().isoformat()}
        return iid

    @staticmethod
    def _public(it: dict) -> dict:
        out = {"id": it["id"], "name": it["name"], "lastModifiedDateTime": it.get("lastModifiedDateTime")}
        if it["folder"]:
            out["folder"] = {}
        else:
            out["file"] = {}
            out["size"] = len(it["data"] or b"")
        return out

    def list_children(self, drive_id: str, item_id: str) -> list[dict]:
        return [self._public(it) for it in self.drives[drive_id]["items"].values() if it["parent"] == item_id]

    def search_drive(self, drive_id: str, query: str) -> list[dict]:
        q = query.lower()
        return [self._public(it) for it in self.drives[drive_id]["items"].values()
                if it["parent"] and q in it["name"].lower()]

    def user_drive(self, user_id: str) -> dict | None:
        u = self._user(user_id)
        if not self._licensed(user_id):
            return None
        if not u.get("drive"):
            u["drive"] = self._new_drive()
        return {"id": u["drive"]}

    def drive_items(self, drive_id: str) -> list[dict]:
        return [self._public(it) for it in self.drives[drive_id]["items"].values() if it["parent"]]

    def download(self, drive_id: str, item_id: str) -> bytes:
        return self.drives[drive_id]["items"][item_id]["data"] or b""

    # ---------------------------------------------------------------- learner simulation (tests)
    def simulate_drive_file(self, user_id: str, path: str, data: bytes) -> None:
        drive = self.user_drive(user_id)["id"]
        parent = self.drives[drive]["root"]
        *folders, name = path.strip("/").split("/")
        for f in folders:
            parent = self.ensure_folder(drive, parent, f)
        self.upload_file(drive, parent, name, data)

    def simulate_event(self, user_id: str, subject: str, start_local: str, end_local: str, tz: str) -> None:
        self.events.setdefault(user_id, []).append({
            "id": _id(), "subject": subject, "iCalUId": "ical-" + uuid.uuid4().hex, "isCancelled": False,
            "type": "singleInstance", "start": {"dateTime": start_local, "timeZone": tz},
            "end": {"dateTime": end_local, "timeZone": tz}, "responseStatus": {"response": "organizer"}})

    def simulate_mail(self, user_id: str, folder: str, subject: str, body: str) -> None:
        self.mail.setdefault(user_id, []).append({
            "id": _id(), "folder": folder, "subject": subject, "body": body, "from": None,
            "receivedDateTime": _now().isoformat(), "isRead": False, "isDraft": folder == "drafts",
            "conversationId": "conv-" + uuid.uuid4().hex, "importance": "normal", "flag": {},
            "@odata.type": "#microsoft.graph.message"})
