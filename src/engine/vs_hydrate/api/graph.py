"""Microsoft Graph implementation of TenantAPI.

App-only authentication with a certificate (no client secrets). Every call
retries on throttling (429) and transient server errors, honouring
Retry-After, so runs are bounded by Graph throttling rather than compute.
"""
from __future__ import annotations

import base64
import json
import logging
import random
import re
import threading
import time
from pathlib import Path
from urllib.parse import quote

import requests

from .base import NotReady, TenantAPI, TenantError

log = logging.getLogger("vs_hydrate.graph")

GRAPH = "https://graph.microsoft.com/v1.0"
TRANSIENT = {429, 500, 502, 503, 504}


def _q(s: str) -> str:
    return s.replace("'", "''")


def load_certificate(path: str) -> tuple[str, str]:
    """Return (private key PEM, SHA-1 thumbprint hex) from a PEM with key and cert."""
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes

    pem = Path(path).read_text()
    key = re.search(r"-----BEGIN (?:RSA |EC )?PRIVATE KEY-----.*?-----END (?:RSA |EC )?PRIVATE KEY-----", pem, re.S)
    cert = re.search(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, re.S)
    if not key or not cert:
        raise TenantError(f"{path} must contain a private key and a certificate (PEM)")
    c = x509.load_pem_x509_certificate(cert.group(0).encode())
    return key.group(0), c.fingerprint(hashes.SHA1()).hex().upper()


class GraphTenant(TenantAPI):
    def __init__(self, tenant_id: str, client_id: str, certificate_path: str,
                 max_retries: int = 8, timeout: int = 60):
        import msal

        key, thumb = load_certificate(certificate_path)
        self._app = msal.ConfidentialClientApplication(
            client_id, authority=f"https://login.microsoftonline.com/{tenant_id}",
            client_credential={"private_key": key, "thumbprint": thumb})
        self._token: str | None = None
        self._lock = threading.Lock()
        self._local = threading.local()
        self.max_retries = max_retries
        self.timeout = timeout

    # ---------------------------------------------------------------- transport
    def _session(self) -> requests.Session:
        s = getattr(self._local, "s", None)
        if s is None:
            s = self._local.s = requests.Session()
        return s

    def _get_token(self, force: bool = False) -> str:
        with self._lock:
            if self._token and not force:
                return self._token
            res = self._app.acquire_token_for_client(scopes=["https://graph.microsoft.com/.default"])
            if "access_token" not in res:
                raise TenantError(f"token request failed: {res.get('error')}: {res.get('error_description')}")
            self._token = res["access_token"]
            return self._token

    def call(self, method: str, path: str, *, json_body=None, data: bytes | None = None,
             params: dict | None = None, headers: dict | None = None, ok404: bool = False,
             raw: bool = False):
        url = path if path.startswith("http") else GRAPH + path
        refreshed = False
        for attempt in range(self.max_retries + 1):
            h = {"Authorization": f"Bearer {self._get_token()}"}
            if headers:
                h.update(headers)
            try:
                r = self._session().request(method, url, json=json_body, data=data, params=params,
                                            headers=h, timeout=self.timeout)
            except requests.RequestException as e:
                if attempt == self.max_retries:
                    raise TenantError(f"{method} {path}: {e}", transient=True) from e
                time.sleep(min(60, 2 ** attempt) + random.random())
                continue
            if r.status_code == 401 and not refreshed:
                self._get_token(force=True)
                refreshed = True
                continue
            if r.status_code in TRANSIENT and attempt < self.max_retries:
                wait = float(r.headers.get("Retry-After", 0)) or min(60, 2 ** attempt)
                log.debug("throttled %s %s -> %s, waiting %.1fs", method, path, r.status_code, wait)
                time.sleep(wait + random.random())
                continue
            if r.status_code == 404 and ok404:
                return None
            if r.status_code >= 400:
                try:
                    err = r.json().get("error", {})
                    msg = f"{err.get('code')}: {err.get('message')}"
                except ValueError:
                    msg = r.text[:300]
                raise TenantError(f"{method} {path} -> {r.status_code} {msg}", status=r.status_code,
                                  transient=r.status_code in TRANSIENT)
            if raw:
                return r
            if r.status_code == 204 or not r.content:
                return {}
            ctype = r.headers.get("Content-Type", "")
            return r.json() if "json" in ctype else r.content
        raise TenantError(f"{method} {path}: retries exhausted", transient=True)

    def get_all(self, path: str, params: dict | None = None, limit: int | None = None,
                headers: dict | None = None) -> list[dict]:
        out: list[dict] = []
        page = self.call("GET", path, params=params, headers=headers)
        while True:
            out.extend(page.get("value", []))
            nxt = page.get("@odata.nextLink")
            if not nxt or (limit and len(out) >= limit):
                break
            page = self.call("GET", nxt, headers=headers)
        return out[:limit] if limit else out

    # ---------------------------------------------------------------- tenant
    def granted_roles(self) -> set[str]:
        tok = self._get_token()
        payload = tok.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        return set(json.loads(base64.urlsafe_b64decode(payload)).get("roles", []))

    def subscribed_skus(self) -> list[dict]:
        return self.get_all("/subscribedSkus")

    # ---------------------------------------------------------------- users
    _USER_SELECT = "id,userPrincipalName,displayName,givenName,surname,accountEnabled,usageLocation"

    def get_user(self, upn: str) -> dict | None:
        return self.call("GET", f"/users/{quote(upn)}", params={"$select": self._USER_SELECT}, ok404=True)

    def list_users_with_prefix(self, prefix: str, domain: str) -> list[dict]:
        users = self.get_all("/users", params={"$filter": f"startswith(userPrincipalName,'{_q(prefix)}')",
                                               "$select": self._USER_SELECT, "$top": "999"})
        return [u for u in users if u["userPrincipalName"].lower().endswith("@" + domain.lower())]

    def create_user(self, body: dict) -> dict:
        return self.call("POST", "/users", json_body=body)

    def update_user(self, user_id: str, body: dict) -> None:
        self.call("PATCH", f"/users/{user_id}", json_body=body)

    def delete_user(self, user_id: str, permanent: bool = False) -> None:
        self.call("DELETE", f"/users/{user_id}", ok404=True)
        if permanent:
            for attempt in range(10):
                if self.call("DELETE", f"/directory/deletedItems/{user_id}", ok404=True) is not None:
                    return
                time.sleep(3 * (attempt + 1))

    def set_manager(self, user_id: str, manager_id: str) -> None:
        self.call("PUT", f"/users/{user_id}/manager/$ref",
                  json_body={"@odata.id": f"{GRAPH}/users/{manager_id}"})

    def set_photo(self, user_id: str, png: bytes) -> None:
        try:
            self.call("PUT", f"/users/{user_id}/photo/$value", data=png, headers={"Content-Type": "image/png"})
        except TenantError as e:
            if e.status in (404, 400):
                raise NotReady(f"photo for {user_id}: mailbox not ready") from e
            raise

    def assign_licenses(self, user_id: str, add: list[str], remove: list[str] | None = None) -> None:
        self.call("POST", f"/users/{user_id}/assignLicense",
                  json_body={"addLicenses": [{"skuId": s, "disabledPlans": []} for s in add],
                             "removeLicenses": remove or []})

    def user_license_skus(self, user_id: str) -> set[str]:
        u = self.call("GET", f"/users/{user_id}", params={"$select": "assignedLicenses"})
        return {lic["skuId"] for lic in u.get("assignedLicenses", [])}

    def create_tap(self, user_id: str, start_iso: str, lifetime_minutes: int) -> str:
        r = self.call("POST", f"/users/{user_id}/authentication/temporaryAccessPassMethods",
                      json_body={"startDateTime": start_iso, "lifetimeInMinutes": lifetime_minutes,
                                 "isUsableOnce": False})
        return r["temporaryAccessPass"]

    # ---------------------------------------------------------------- groups
    def find_group(self, display_name: str) -> dict | None:
        v = self.get_all("/groups", params={"$filter": f"displayName eq '{_q(display_name)}'",
                                            "$select": "id,displayName"})
        return v[0] if v else None

    def add_group_member(self, group_id: str, user_id: str) -> None:
        try:
            self.call("POST", f"/groups/{group_id}/members/$ref",
                      json_body={"@odata.id": f"{GRAPH}/directoryObjects/{user_id}"})
        except TenantError as e:
            if e.status == 400 and "already exist" in str(e):
                return
            raise

    def is_group_member(self, group_id: str, user_id: str) -> bool:
        r = self.call("POST", f"/users/{user_id}/checkMemberGroups", json_body={"groupIds": [group_id]})
        return group_id in r.get("value", [])

    def delete_group(self, group_id: str) -> None:
        self.call("DELETE", f"/groups/{group_id}", ok404=True)

    # ---------------------------------------------------------------- mailbox
    def mailbox_ready(self, user_id: str) -> bool:
        try:
            return self.call("GET", f"/users/{user_id}/mailboxSettings", ok404=True) is not None
        except TenantError as e:
            if e.status in (400, 403) and "Mailbox" in str(e):
                return False
            raise

    def set_mailbox_settings(self, user_id: str, time_zone: str, locale: str | None) -> None:
        body: dict = {"timeZone": time_zone}
        if locale:
            body["language"] = {"locale": locale}
        self.call("PATCH", f"/users/{user_id}/mailboxSettings", json_body=body)

    def create_message(self, user_id: str, folder: str, message: dict) -> str:
        return self.call("POST", f"/users/{user_id}/mailFolders/{folder}/messages", json_body=message)["id"]

    def update_message(self, user_id: str, message_id: str, patch: dict) -> None:
        self.call("PATCH", f"/users/{user_id}/messages/{message_id}", json_body=patch)

    def delete_message(self, user_id: str, message_id: str) -> None:
        self.call("DELETE", f"/users/{user_id}/messages/{message_id}", ok404=True)

    def list_messages(self, user_id: str, folder: str, top: int = 200, with_body: bool = False) -> list[dict]:
        sel = "id,subject,from,receivedDateTime,isRead,isDraft,conversationId,importance,flag,bodyPreview"
        if with_body:
            sel += ",body,uniqueBody"
        return self.get_all(f"/users/{user_id}/mailFolders/{folder}/messages",
                            params={"$select": sel, "$top": str(min(top, 100)),
                                    "$orderby": "receivedDateTime desc"},
                            headers={"Prefer": 'outlook.body-content-type="text"'}, limit=top)

    def search_messages(self, user_id: str, query: str, top: int = 25) -> list[dict]:
        return self.call("GET", f"/users/{user_id}/messages",
                         params={"$search": f'"{query}"', "$top": str(top), "$select": "id,subject"}).get("value", [])

    # ---------------------------------------------------------------- calendar
    def create_event(self, organiser_id: str, event: dict) -> dict:
        r = self.call("POST", f"/users/{organiser_id}/calendar/events", json_body=event)
        return {"id": r["id"], "iCalUId": r["iCalUId"]}

    def find_event_by_ical(self, user_id: str, ical_uid: str) -> dict | None:
        v = self.call("GET", f"/users/{user_id}/events",
                      params={"$filter": f"iCalUId eq '{_q(ical_uid)}'",
                              "$select": "id,subject,responseStatus"}).get("value", [])
        return v[0] if v else None

    def accept_event(self, user_id: str, event_id: str) -> None:
        self.call("POST", f"/users/{user_id}/events/{event_id}/accept", json_body={"sendResponse": False})

    def delete_event(self, user_id: str, event_id: str) -> None:
        self.call("DELETE", f"/users/{user_id}/events/{event_id}", ok404=True)

    def calendar_view(self, user_id: str, start_iso: str, end_iso: str) -> list[dict]:
        return self.get_all(f"/users/{user_id}/calendarView",
                            params={"startDateTime": start_iso, "endDateTime": end_iso, "$top": "200",
                                    "$select": "id,subject,start,end,isCancelled,type,showAs,organizer"},
                            headers={"Prefer": 'outlook.timezone="UTC"'})

    # ---------------------------------------------------------------- teams
    def create_migration_team(self, display_name: str, description: str, created_iso: str) -> str:
        r = self.call("POST", "/teams", raw=True, json_body={
            "@microsoft.graph.teamCreationMode": "migration",
            "template@odata.bind": f"{GRAPH}/teamsTemplates('standard')",
            "displayName": display_name, "description": description,
            "createdDateTime": created_iso})
        loc = r.headers.get("Location") or r.headers.get("Content-Location", "")
        m = re.search(r"teams\('([^']+)'\)", loc)
        if not m:
            raise TenantError(f"team creation returned no team id (Location: {loc!r})")
        team_id = m.group(1)
        op = re.search(r"operations\('([^']+)'\)", loc)
        for attempt in range(30):
            if op:
                st = self.call("GET", f"/teams/{team_id}/operations/{op.group(1)}", ok404=True)
                status = (st or {}).get("status", "")
                if status == "succeeded":
                    return team_id
                if status == "failed":
                    raise TenantError(f"team creation failed: {st.get('error')}")
            elif self.team_exists(team_id):
                return team_id
            time.sleep(min(10, 2 + attempt))
        raise NotReady(f"team {team_id} still provisioning")

    def create_migration_channel(self, team_id: str, name: str, description: str, created_iso: str) -> str:
        return self.call("POST", f"/teams/{team_id}/channels", json_body={
            "@microsoft.graph.channelCreationMode": "migration",
            "displayName": name, "description": description, "membershipType": "standard",
            "createdDateTime": created_iso})["id"]

    def list_channels(self, team_id: str) -> list[dict]:
        return self.get_all(f"/teams/{team_id}/channels", params={"$select": "id,displayName"})

    def import_message(self, team_id: str, channel_id: str, message: dict, reply_to: str | None = None) -> str:
        path = f"/teams/{team_id}/channels/{channel_id}/messages"
        if reply_to:
            path += f"/{reply_to}/replies"
        return self.call("POST", path, json_body=message)["id"]

    def _complete(self, path: str) -> None:
        try:
            self.call("POST", path)
        except TenantError as e:
            if e.status == 400 and "migration" in str(e).lower():
                return  # already completed
            raise

    def complete_channel_migration(self, team_id: str, channel_id: str) -> None:
        self._complete(f"/teams/{team_id}/channels/{channel_id}/completeMigration")

    def complete_team_migration(self, team_id: str) -> None:
        self._complete(f"/teams/{team_id}/completeMigration")

    def add_team_member(self, team_id: str, user_id: str, owner: bool) -> None:
        try:
            self.call("POST", f"/teams/{team_id}/members", json_body={
                "@odata.type": "#microsoft.graph.aadUserConversationMember",
                "roles": ["owner"] if owner else [],
                "user@odata.bind": f"{GRAPH}/users('{user_id}')"})
        except TenantError as e:
            if e.status == 409:
                return
            raise

    def list_channel_messages(self, team_id: str, channel_id: str) -> list[dict]:
        return self.get_all(f"/teams/{team_id}/channels/{channel_id}/messages",
                            params={"$expand": "replies", "$top": "50"})

    def team_exists(self, team_id: str) -> bool:
        return self.call("GET", f"/teams/{team_id}", ok404=True) is not None

    # ---------------------------------------------------------------- files
    def channel_files_folder(self, team_id: str, channel_id: str) -> dict:
        try:
            r = self.call("GET", f"/teams/{team_id}/channels/{channel_id}/filesFolder")
        except TenantError as e:
            if e.status in (404, 400, 403):
                raise NotReady(f"files folder for team {team_id} not ready") from e
            raise
        return {"drive_id": r["parentReference"]["driveId"], "id": r["id"]}

    def ensure_folder(self, drive_id: str, parent_id: str, name: str) -> str:
        found = self.call("GET", f"/drives/{drive_id}/items/{parent_id}:/{quote(name)}", ok404=True)
        if found:
            return found["id"]
        return self.call("POST", f"/drives/{drive_id}/items/{parent_id}/children", json_body={
            "name": name, "folder": {}, "@microsoft.graph.conflictBehavior": "fail"})["id"]

    def upload_file(self, drive_id: str, parent_id: str, name: str, data: bytes) -> str:
        target = f"/drives/{drive_id}/items/{parent_id}:/{quote(name)}"
        if len(data) <= 4 * 1024 * 1024:
            return self.call("PUT", f"{target}:/content", data=data,
                             headers={"Content-Type": "application/octet-stream"})["id"]
        sess = self.call("POST", f"{target}:/createUploadSession",
                         json_body={"item": {"@microsoft.graph.conflictBehavior": "replace"}})
        url, chunk, pos, item = sess["uploadUrl"], 5 * 1024 * 1024, 0, None
        while pos < len(data):
            part = data[pos:pos + chunk]
            r = requests.put(url, data=part, timeout=self.timeout, headers={
                "Content-Range": f"bytes {pos}-{pos + len(part) - 1}/{len(data)}"})
            r.raise_for_status()
            pos += len(part)
            if r.status_code in (200, 201):
                item = r.json()
        return item["id"]

    def list_children(self, drive_id: str, item_id: str) -> list[dict]:
        return self.get_all(f"/drives/{drive_id}/items/{item_id}/children",
                            params={"$select": "id,name,file,folder,size,lastModifiedDateTime"})

    def search_drive(self, drive_id: str, query: str) -> list[dict]:
        return self.get_all(f"/drives/{drive_id}/root/search(q='{_q(query)}')",
                            params={"$select": "id,name,file,folder"}, limit=50)

    def user_drive(self, user_id: str) -> dict | None:
        try:
            return self.call("GET", f"/users/{user_id}/drive", ok404=True)
        except TenantError as e:
            if e.status in (400, 403):
                return None
            raise

    def drive_items(self, drive_id: str) -> list[dict]:
        items = self.get_all(f"/drives/{drive_id}/root/delta",
                             params={"$select": "id,name,file,folder,size,lastModifiedDateTime,parentReference,deleted,root"})
        return [i for i in items if "deleted" not in i and "root" not in i]

    def download(self, drive_id: str, item_id: str) -> bytes:
        return self.call("GET", f"/drives/{drive_id}/items/{item_id}/content", raw=True).content
