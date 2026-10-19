from datetime import datetime
from typing import Any, Protocol


class TransientEvidenceError(Exception):
    """Evidence source temporarily unavailable (throttling, 5xx, network). The worker retries."""


class EvidenceSource(Protocol):
    """Read-only view of a user's Microsoft 365 footprint. All items are raw Graph JSON shapes."""

    async def user_object_id(self, upn: str) -> str | None: ...

    async def roster(self, group_id: str | None) -> list[dict[str, Any]]:
        """Lab accounts for an event: members of an Entra group (live) as Graph user objects
        (userPrincipalName, givenName, surname, mail)."""
        ...

    async def drive_children(self, upn: str, folder: str) -> list[dict[str, Any]]: ...

    async def site_drive_children(self, site: str, library: str, folder: str) -> list[dict[str, Any]]: ...

    async def drive_item_content(self, item: dict[str, Any], max_bytes: int) -> bytes: ...

    async def sent_messages(self, upn: str, since: datetime) -> list[dict[str, Any]]: ...

    async def calendar_events(self, upn: str, since: datetime) -> list[dict[str, Any]]: ...

    async def channel_messages(self, team_id: str, channel_id: str, since: datetime) -> list[dict[str, Any]]: ...

    async def copilot_interactions(self, upn: str, since: datetime, until: datetime) -> list[dict[str, Any]]: ...

    async def copilot_audit_records(self, upn: str, since: datetime) -> list[dict[str, Any]] | None:
        """Purview CopilotInteraction audit records, or None while the batched audit query is still running."""
        ...

    async def status(self) -> dict[str, Any]: ...
