import json

from pydantic import Field

from app.checks.base import Check, CheckContext, Outcome, StrictParams, contains_all, latest_at, quote_list


class ChannelParams(StrictParams):
    team_id: str
    channel_id: str
    content_contains: list[str] = Field(default_factory=list)


class TeamsChannelMessage(Check):
    type = "teams_channel_message"
    title = "Teams channel post"
    summary = "The lab user posted in a given Teams channel after the lab started."
    Params = ChannelParams
    example = {"team_id": "<team-guid>", "channel_id": "19:abc@thread.tacv2", "content_contains": ["summary"]}

    async def run(self, ctx: CheckContext, p: ChannelParams) -> Outcome:
        msgs = await ctx.source.channel_messages(p.team_id, p.channel_id, ctx.lab_started_at)
        user_id = await ctx.source.user_object_id(ctx.upn)
        mine = [m for m in msgs if user_id and ((m.get("from") or {}).get("user") or {}).get("id") == user_id]
        hits = [m for m in mine if not contains_all((m.get("body") or {}).get("content") or "", p.content_contains)]
        if hits:
            return Outcome(True, "Posted the expected message in the Teams channel",
                           {"matched": len(hits), "at": latest_at(hits, "createdDateTime")})
        return Outcome(False, "No post by this user in the Teams channel since the lab started"
                              f"{' containing ' + quote_list(p.content_contains) if p.content_contains else ''}.",
                       {"messages_checked": len(msgs)})


class CopilotParams(StrictParams):
    # Calibrate against a real Cowork run; Microsoft has not documented a Cowork appClass yet.
    app_class_contains: list[str] = Field(default_factory=list)
    prompt_contains: list[str] = Field(default_factory=list)
    min_count: int = Field(default=1, ge=1)


class CopilotInteraction(Check):
    type = "copilot_interaction"
    title = "Copilot interaction (Graph export)"
    summary = ("The user prompted Microsoft 365 Copilot after the lab started (Graph interaction export, "
               "AiEnterpriseInteraction.Read.All). Use as blocking with a retry window, or deferred if latency is high.")
    Params = CopilotParams
    example = {"app_class_contains": ["Cowork"], "prompt_contains": ["brief"]}

    async def run(self, ctx: CheckContext, p: CopilotParams) -> Outcome:
        items = await ctx.source.copilot_interactions(ctx.upn, ctx.lab_started_at, ctx.now)
        prompts = [i for i in items if i.get("interactionType") == "userPrompt"]
        hits = []
        for i in prompts:
            app_class = i.get("appClass") or ""
            if p.app_class_contains and not any(a.lower() in app_class.lower() for a in p.app_class_contains):
                continue
            if contains_all((i.get("body") or {}).get("content") or "", p.prompt_contains):
                continue
            hits.append(i)
        ev = {"prompts_since_lab_start": len(prompts), "app_classes": sorted({i.get("appClass") or "" for i in prompts})[:10],
              "at": latest_at(hits, "createdDateTime")}
        if len(hits) >= p.min_count:
            return Outcome(True, f"{len(hits)} matching Copilot prompt(s) found ({hits[0].get('appClass')})", ev)
        where = f" in {quote_list(p.app_class_contains)}" if p.app_class_contains else ""
        return Outcome(False, f"No Copilot prompt{where} found for this account since the lab started"
                              f"{' mentioning ' + quote_list(p.prompt_contains) if p.prompt_contains else ''}.", ev)


class AuditParams(StrictParams):
    app_identity_contains: list[str] = Field(default_factory=lambda: ["Copilot"])
    agent_name_contains: list[str] = Field(default_factory=list)
    resource_action: str | None = Field(default=None, description="e.g. create or modify")


class CopilotAudit(Check):
    type = "copilot_audit"
    title = "Copilot audit record (Purview)"
    summary = ("A Purview CopilotInteraction audit record exists for the user since the lab started. "
               "Audit data lags 60-90+ minutes, so this check must be deferred.")
    Params = AuditParams
    example = {"app_identity_contains": ["Copilot"], "agent_name_contains": ["Cowork"], "resource_action": "create"}

    async def run(self, ctx: CheckContext, p: AuditParams) -> Outcome:
        records = await ctx.source.copilot_audit_records(ctx.upn, ctx.lab_started_at)
        if records is None:
            return Outcome(False, "Audit query still running", pending=True)
        hits = []
        for r in records:
            blob = json.dumps(r.get("auditData") or r).lower()
            if p.app_identity_contains and not any(a.lower() in blob for a in p.app_identity_contains):
                continue
            if p.agent_name_contains and not any(a.lower() in blob for a in p.agent_name_contains):
                continue
            if p.resource_action and f'"action": "{p.resource_action.lower()}"' not in blob:
                continue
            hits.append(r)
        if hits:
            return Outcome(True, f"{len(hits)} Copilot audit record(s) confirm the activity", {"records": len(hits)})
        return Outcome(False, "No matching Copilot audit record yet for this account.", {"records_checked": len(records)})
