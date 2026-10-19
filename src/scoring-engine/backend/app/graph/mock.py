"""File-backed evidence source for local runs and tests.

Shape of the JSON file (all keys optional):
{
  "users": {
    "labuser01@contoso.test": {
      "drive": {"/Cowork": [<driveItem>, ...]},
      "file_contents": {"<itemId>": "plain text content"},
      "sent_messages": [<message>], "calendar_events": [<event>],
      "copilot_interactions": [<aiInteraction>], "copilot_audit": [<auditRecord>]
    }
  },
  "sites": {"<site>|<library>|<folder>": [<driveItem>]},
  "channels": {"<teamId>|<channelId>": [<chatMessage>]}
}
The file is re-read when it changes, so a simulator can add evidence while the stack is running.
"""
import json
import os
from datetime import datetime
from typing import Any

from app.graph.base import TransientEvidenceError


def _after(items: list[dict[str, Any]], field: str, since: datetime) -> list[dict[str, Any]]:
    out = []
    for it in items:
        raw = it.get(field)
        if raw and datetime.fromisoformat(raw.replace("Z", "+00:00")) >= since:
            out.append(it)
    return out


class MockEvidenceSource:
    def __init__(self, path: str) -> None:
        self._path = path
        self._mtime = -1.0
        self._data: dict[str, Any] = {}

    def _load(self) -> dict[str, Any]:
        try:
            mtime = os.path.getmtime(self._path)
        except OSError:
            return {}
        if mtime != self._mtime:
            try:
                with open(self._path, encoding="utf-8") as fh:
                    self._data = json.load(fh)
                self._mtime = mtime
            except (OSError, ValueError) as exc:  # file mid-write; treat as transient
                raise TransientEvidenceError(f"mock file unreadable: {exc}") from exc
        return self._data

    def _user(self, upn: str) -> dict[str, Any]:
        users = self._load().get("users", {})
        return users.get(upn) or users.get(upn.lower()) or {}

    async def user_object_id(self, upn: str) -> str | None:
        return self._user(upn).get("id") or upn.lower()

    async def roster(self, group_id: str | None) -> list[dict[str, Any]]:
        # Mock tenant: every user in the evidence file is a lab account.
        out = []
        for upn, u in self._load().get("users", {}).items():
            prof = u.get("profile", {})
            out.append({"userPrincipalName": upn, "givenName": prof.get("givenName"),
                        "surname": prof.get("surname"), "mail": prof.get("mail")})
        return out

    async def drive_children(self, upn: str, folder: str) -> list[dict[str, Any]]:
        drive = self._user(upn).get("drive", {})
        return drive.get("/" + folder.strip("/"), []) if folder.strip("/") else drive.get("/", [])

    async def site_drive_children(self, site: str, library: str, folder: str) -> list[dict[str, Any]]:
        return self._load().get("sites", {}).get(f"{site}|{library}|/{folder.strip('/')}", [])

    async def drive_item_content(self, item: dict[str, Any], max_bytes: int) -> bytes:
        upn = (item.get("createdBy", {}).get("user", {}) or {}).get("email", "")
        text = self._user(upn).get("file_contents", {}).get(item.get("id"), "")
        return text.encode()[:max_bytes]

    async def sent_messages(self, upn: str, since: datetime) -> list[dict[str, Any]]:
        return _after(self._user(upn).get("sent_messages", []), "sentDateTime", since)

    async def calendar_events(self, upn: str, since: datetime) -> list[dict[str, Any]]:
        return _after(self._user(upn).get("calendar_events", []), "createdDateTime", since)

    async def channel_messages(self, team_id: str, channel_id: str, since: datetime) -> list[dict[str, Any]]:
        return _after(self._load().get("channels", {}).get(f"{team_id}|{channel_id}", []), "createdDateTime", since)

    async def copilot_interactions(self, upn: str, since: datetime, until: datetime) -> list[dict[str, Any]]:
        items = _after(self._user(upn).get("copilot_interactions", []), "createdDateTime", since)
        return [i for i in items if datetime.fromisoformat(i["createdDateTime"].replace("Z", "+00:00")) < until]

    async def copilot_audit_records(self, upn: str, since: datetime) -> list[dict[str, Any]] | None:
        return _after(self._user(upn).get("copilot_audit", []), "createdDateTime", since)

    async def status(self) -> dict[str, Any]:
        data = self._load()
        return {"mode": "mock", "tenant_id": None, "tenant_name": "Mock tenant (local evidence file)",
                "mock_file": self._path, "mock_users": len(data.get("users", {}))}
