from app.checks.base import Check
from app.checks.collab import CopilotAudit, CopilotInteraction, TeamsChannelMessage
from app.checks.files import OneDriveFile, SharePointFile
from app.checks.outlook import CalendarEvent, MailSent

REGISTRY: dict[str, Check] = {
    c.type: c()
    for c in (OneDriveFile, SharePointFile, MailSent, CalendarEvent, TeamsChannelMessage,
              CopilotInteraction, CopilotAudit)
}


def catalogue() -> list[dict]:
    return [
        {"type": c.type, "title": c.title, "summary": c.summary, "example": c.example,
         "params": c.Params.model_json_schema()}
        for c in REGISTRY.values()
    ]
