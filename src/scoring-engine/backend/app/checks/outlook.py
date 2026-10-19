from pydantic import Field

from app.checks.base import Check, CheckContext, Outcome, StrictParams, contains_all, latest_at, quote_list


def _addresses(recipients: list[dict]) -> str:
    return " ".join(((r.get("emailAddress") or {}).get("address") or "") for r in recipients or [])


class MailParams(StrictParams):
    subject_contains: list[str] = Field(default_factory=list)
    to_contains: list[str] = Field(default_factory=list)
    body_contains: list[str] = Field(default_factory=list)
    require_attachment: bool = False
    min_count: int = Field(default=1, ge=1)


class MailSent(Check):
    type = "mail_sent"
    title = "Email sent"
    summary = "The lab user sent an email after the lab started, matching subject/recipient/body text."
    Params = MailParams
    example = {"subject_contains": ["Contoso"], "to_contains": ["manager@"], "require_attachment": True}

    async def run(self, ctx: CheckContext, p: MailParams) -> Outcome:
        msgs = await ctx.source.sent_messages(ctx.upn, ctx.lab_started_at)
        matched = []
        for m in msgs:
            if contains_all(m.get("subject") or "", p.subject_contains):
                continue
            if contains_all(_addresses((m.get("toRecipients") or []) + (m.get("ccRecipients") or [])), p.to_contains):
                continue
            if contains_all(m.get("bodyPreview") or "", p.body_contains):
                continue
            if p.require_attachment and not m.get("hasAttachments"):
                continue
            matched.append(m)
        ev = {"sent_since_lab_start": len(msgs), "matched": [m.get("subject") or "(no subject)" for m in matched][:10],
              "at": latest_at(matched, "sentDateTime")}
        if len(matched) >= p.min_count:
            return Outcome(True, f"Sent email '{ev['matched'][0]}'", ev)
        crit = []
        if p.subject_contains:
            crit.append(f"subject containing {quote_list(p.subject_contains)}")
        if p.to_contains:
            crit.append(f"recipient {quote_list(p.to_contains)}")
        if p.require_attachment:
            crit.append("an attachment")
        return Outcome(False, f"No sent email since the lab started with {' and '.join(crit) or 'the expected content'} "
                              f"({len(msgs)} sent email(s) checked).", ev)


class EventParams(StrictParams):
    subject_contains: list[str] = Field(default_factory=list)
    attendees_contains: list[str] = Field(default_factory=list)
    require_online_meeting: bool = False
    min_count: int = Field(default=1, ge=1)


class CalendarEvent(Check):
    type = "calendar_event"
    title = "Calendar event created"
    summary = "A calendar event was created in the lab user's calendar after the lab started."
    Params = EventParams
    example = {"subject_contains": ["Contoso review"], "attendees_contains": ["@"], "require_online_meeting": True}

    async def run(self, ctx: CheckContext, p: EventParams) -> Outcome:
        events = await ctx.source.calendar_events(ctx.upn, ctx.lab_started_at)
        matched = []
        for e in events:
            if contains_all(e.get("subject") or "", p.subject_contains):
                continue
            attendees = " ".join(((a.get("emailAddress") or {}).get("address") or "") for a in e.get("attendees") or [])
            if contains_all(attendees, p.attendees_contains):
                continue
            if p.require_online_meeting and not e.get("isOnlineMeeting"):
                continue
            matched.append(e)
        ev = {"created_since_lab_start": len(events), "matched": [e.get("subject") or "(no subject)" for e in matched][:10],
              "at": latest_at(matched, "createdDateTime")}
        if len(matched) >= p.min_count:
            return Outcome(True, f"Calendar event '{ev['matched'][0]}' created", ev)
        return Outcome(False, f"No calendar event created since the lab started"
                              f"{' with subject ' + quote_list(p.subject_contains) if p.subject_contains else ''} "
                              f"({len(events)} event(s) checked).", ev)
