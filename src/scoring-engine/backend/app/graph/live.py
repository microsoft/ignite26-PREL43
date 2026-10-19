"""Microsoft Graph evidence source (app-only).

Credentials come from azure-identity's DefaultAzureCredential: AKS workload identity in Ignite-tenant,
or AZURE_TENANT_ID / AZURE_CLIENT_ID / AZURE_CLIENT_SECRET for a client-secret test setup.

Required application permissions (admin consent): Files.Read.All, Mail.ReadBasic.All (Mail.Read if
body checks are used), Calendars.ReadBasic.All, ChannelMessage.Read.All, User.Read.All,
AiEnterpriseInteraction.Read.All, AuditLogsQuery.Read.All, GroupMember.Read.All (roster sync).
"""
import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Any
from urllib.parse import quote

import httpx
from azure.identity.aio import DefaultAzureCredential

from app.config import Settings
from app.graph.base import TransientEvidenceError

GRAPH = "https://graph.microsoft.com/v1.0"
SCOPE = "https://graph.microsoft.com/.default"
log = logging.getLogger("graph")


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _path(folder: str) -> str:
    folder = "/" + folder.strip("/")
    return "root" if folder == "/" else f"root:{quote(folder)}:"


class GraphEvidenceSource:
    def __init__(self, settings: Settings) -> None:
        self._credential = DefaultAzureCredential()
        self._client = httpx.AsyncClient(timeout=httpx.Timeout(20.0))
        self._sem = asyncio.Semaphore(settings.graph_max_concurrency)
        self._token: tuple[str, float] | None = None
        self._audit = _AuditBatcher(self)

    async def _auth_header(self) -> dict[str, str]:
        loop = asyncio.get_running_loop()
        if self._token is None or self._token[1] - 120 < loop.time():
            tok = await self._credential.get_token(SCOPE)
            self._token = (tok.token, loop.time() + (tok.expires_on - datetime.now().timestamp()))
        return {"Authorization": f"Bearer {self._token[0]}"}

    async def request(self, method: str, url: str, *, json: Any = None, params: dict | None = None,
                      raw: bool = False, allow_404: bool = False) -> Any:
        if not url.startswith("http"):
            url = GRAPH + url
        for attempt in range(5):
            async with self._sem:
                try:
                    resp = await self._client.request(method, url, json=json, params=params,
                                                      headers=await self._auth_header(), follow_redirects=True)
                except httpx.HTTPError as exc:
                    if attempt == 4:
                        raise TransientEvidenceError(f"Graph unreachable: {exc}") from exc
                    await asyncio.sleep(2 ** attempt)
                    continue
            if resp.status_code in (429, 502, 503, 504):
                wait = float(resp.headers.get("Retry-After", 2 ** attempt))
                log.warning("graph throttled %s %s, retry in %ss", resp.status_code, url, wait)
                if attempt == 4:
                    raise TransientEvidenceError(f"Graph throttled ({resp.status_code})")
                await asyncio.sleep(min(wait, 30))
                continue
            if resp.status_code == 404 and allow_404:
                return None
            if resp.status_code >= 400:
                raise TransientEvidenceError(f"Graph {resp.status_code}: {resp.text[:300]}")
            return resp.content if raw else (resp.json() if resp.content else {})
        raise TransientEvidenceError("Graph retries exhausted")

    async def _paged(self, url: str, params: dict | None = None, max_pages: int = 5,
                     allow_404: bool = False) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        data = await self.request("GET", url, params=params, allow_404=allow_404)
        pages = 1
        while data:
            items += data.get("value", [])
            nxt = data.get("@odata.nextLink")
            if not nxt or pages >= max_pages:
                break
            data = await self.request("GET", nxt)
            pages += 1
        return items

    async def user_object_id(self, upn: str) -> str | None:
        user = await self.request("GET", f"/users/{quote(upn)}", params={"$select": "id"}, allow_404=True)
        return user["id"] if user else None

    async def roster(self, group_id: str | None) -> list[dict[str, Any]]:
        if not group_id:
            return []
        return await self._paged(f"/groups/{group_id}/members/microsoft.graph.user",
                                 {"$select": "id,userPrincipalName,givenName,surname,mail", "$top": "999"},
                                 max_pages=50)

    # ---- files ----
    _FILE_SELECT = "id,name,file,folder,size,createdDateTime,lastModifiedDateTime,createdBy,lastModifiedBy,parentReference,webUrl"

    async def drive_children(self, upn: str, folder: str) -> list[dict[str, Any]]:
        url = f"/users/{quote(upn)}/drive/{_path(folder)}/children"
        return await self._paged(url, {"$select": self._FILE_SELECT, "$top": "200"}, allow_404=True)

    async def site_drive_children(self, site: str, library: str, folder: str) -> list[dict[str, Any]]:
        site_obj = await self.request("GET", f"/sites/{site}", allow_404=True)
        if not site_obj:
            return []
        drives = await self._paged(f"/sites/{site_obj['id']}/drives", {"$select": "id,name"})
        drive = next((d for d in drives if d["name"].lower() == library.lower()), None)
        if drive is None:
            return []
        url = f"/drives/{drive['id']}/{_path(folder)}/children"
        return await self._paged(url, {"$select": self._FILE_SELECT, "$top": "200"}, allow_404=True)

    async def drive_item_content(self, item: dict[str, Any], max_bytes: int) -> bytes:
        drive_id = item.get("parentReference", {}).get("driveId")
        if (item.get("size") or 0) > max_bytes or not drive_id:
            return b""
        return await self.request("GET", f"/drives/{drive_id}/items/{item['id']}/content", raw=True) or b""

    # ---- outlook ----
    async def sent_messages(self, upn: str, since: datetime) -> list[dict[str, Any]]:
        return await self._paged(
            f"/users/{quote(upn)}/mailFolders/sentitems/messages",
            {"$filter": f"sentDateTime ge {_iso(since)}", "$top": "50",
             "$select": "id,subject,toRecipients,ccRecipients,sentDateTime,bodyPreview,hasAttachments"},
        )

    async def calendar_events(self, upn: str, since: datetime) -> list[dict[str, Any]]:
        return await self._paged(
            f"/users/{quote(upn)}/events",
            {"$filter": f"createdDateTime ge {_iso(since)}", "$top": "50",
             "$select": "id,subject,attendees,start,end,createdDateTime,bodyPreview,isOnlineMeeting"},
        )

    # ---- teams ----
    async def channel_messages(self, team_id: str, channel_id: str, since: datetime) -> list[dict[str, Any]]:
        msgs = await self._paged(f"/teams/{team_id}/channels/{channel_id}/messages", {"$top": "50"}, max_pages=3)
        return [m for m in msgs if (m.get("createdDateTime") or "") >= _iso(since)]

    # ---- copilot ----
    async def copilot_interactions(self, upn: str, since: datetime, until: datetime) -> list[dict[str, Any]]:
        user_id = await self.user_object_id(upn)
        if not user_id:
            return []
        # The interaction export requires both bounds on createdDateTime.
        flt = f"createdDateTime gt {_iso(since)} and createdDateTime lt {_iso(until)}"
        return await self._paged(
            f"/copilot/users/{user_id}/interactionHistory/getAllEnterpriseInteractions",
            {"$filter": flt, "$top": "100"}, max_pages=5,
        )

    async def copilot_audit_records(self, upn: str, since: datetime) -> list[dict[str, Any]] | None:
        return await self._audit.records_for(upn, since)

    async def status(self) -> dict[str, Any]:
        org = await self.request("GET", "/organization", params={"$select": "id,displayName,verifiedDomains"})
        org = (org.get("value") or [{}])[0]
        return {"mode": "live", "tenant_id": org.get("id"), "tenant_name": org.get("displayName"),
                "domains": [d["name"] for d in org.get("verifiedDomains", [])]}


class _AuditBatcher:
    """One tenant-wide Purview audit query per window instead of one per participant.

    The audit query API is limited to a few hundred submissions per day per tenant, so deferred
    checks share a single CopilotInteraction query that is refreshed at most every `refresh` interval.
    Purview typically lags 60-90+ minutes, which is why audit checks are always `deferred`.
    """

    def __init__(self, source: GraphEvidenceSource, refresh: timedelta = timedelta(minutes=30)) -> None:
        self._source = source
        self._refresh = refresh
        self._lock = asyncio.Lock()
        self._query_id: str | None = None
        self._query_started: datetime | None = None
        self._window_start: datetime | None = None
        self._records: dict[str, list[dict[str, Any]]] | None = None
        self._records_at: datetime | None = None

    async def records_for(self, upn: str, since: datetime) -> list[dict[str, Any]] | None:
        async with self._lock:
            now = datetime.now(timezone.utc)
            fresh = self._records_at and now - self._records_at < self._refresh
            covers = self._window_start and self._window_start <= since
            if self._query_id is None and not (fresh and covers):
                start = min(since, self._window_start or since) - timedelta(minutes=5)
                body = {"displayName": f"vectorsense-copilot-{now:%Y%m%d%H%M}",
                        "filterStartDateTime": _iso(start), "filterEndDateTime": _iso(now),
                        "operationFilters": ["CopilotInteraction"]}
                q = await self._source.request("POST", "/security/auditLog/queries", json=body)
                self._query_id, self._query_started, self._window_start = q["id"], now, start
            if self._query_id is not None:
                q = await self._source.request("GET", f"/security/auditLog/queries/{self._query_id}")
                if q.get("status") in ("notStarted", "running"):
                    return None if self._records is None else self._records.get(upn.lower(), [])
                records = await self._source._paged(f"/security/auditLog/queries/{self._query_id}/records",
                                                    {"$top": "1000"}, max_pages=50)
                grouped: dict[str, list[dict[str, Any]]] = {}
                for r in records:
                    grouped.setdefault((r.get("userPrincipalName") or "").lower(), []).append(r)
                self._records, self._records_at, self._query_id = grouped, now, None
            return (self._records or {}).get(upn.lower(), [])
