import fnmatch
from typing import Any, Literal

from pydantic import Field

from app.checks.base import Check, CheckContext, Outcome, StrictParams, contains_all, parse_dt, quote_list
from app.checks.office_text import SUPPORTED, extract_text

MAX_CONTENT_BYTES = 15 * 1024 * 1024


class FileParams(StrictParams):
    folder: str = "/"
    name_pattern: str = "*"
    extensions: list[str] = Field(default_factory=list)
    content_contains: list[str] = Field(default_factory=list)
    match_on: Literal["created", "modified"] = "created"
    require_user_authored: bool = True
    # Calibration hook: e.g. the Copilot app name seen in createdBy.application once verified in-tenant.
    created_by_application_contains: str | None = None
    min_count: int = Field(default=1, ge=1)


async def _evaluate_files(ctx: CheckContext, p: FileParams, items: list[dict[str, Any]], where: str) -> Outcome:
    exts = {e.lower().lstrip(".") for e in p.extensions}
    ts_field = "createdDateTime" if p.match_on == "created" else "lastModifiedDateTime"
    by_field = "createdBy" if p.match_on == "created" else "lastModifiedBy"
    candidates, rejected = [], []
    for it in items:
        if "file" not in it:
            continue
        name = it.get("name", "")
        ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
        if not fnmatch.fnmatch(name.lower(), p.name_pattern.lower()) or (exts and ext not in exts):
            continue
        ts = parse_dt(it.get(ts_field))
        if ts is None or ts < ctx.lab_started_at:
            rejected.append(f"{name} ({p.match_on} before the lab started)")
            continue
        actor = it.get(by_field, {}) or {}
        email = ((actor.get("user") or {}).get("email") or "").lower()
        if p.require_user_authored and email and email != ctx.upn.lower():
            rejected.append(f"{name} ({p.match_on} by {email})")
            continue
        if p.created_by_application_contains:
            app_name = ((actor.get("application") or {}).get("displayName") or "")
            if p.created_by_application_contains.lower() not in app_name.lower():
                rejected.append(f"{name} (not produced by {p.created_by_application_contains})")
                continue
        candidates.append((it, ext, ts))

    matched = []
    latest = None
    for it, ext, ts in candidates:
        if p.content_contains:
            if ext not in SUPPORTED:
                rejected.append(f"{it['name']} (content of .{ext} files cannot be inspected)")
                continue
            text = extract_text(await ctx.source.drive_item_content(it, MAX_CONTENT_BYTES), ext) or ""
            missing = contains_all(text, p.content_contains)
            if missing:
                rejected.append(f"{it['name']} (missing {quote_list(missing)})")
                continue
        matched.append(it)
        latest = ts if latest is None or ts > latest else latest

    evidence = {"location": where, "matched": [m.get("name") for m in matched][:10], "rejected": rejected[:10]}
    if latest:
        evidence["at"] = latest.isoformat()
    if len(matched) >= p.min_count:
        return Outcome(True, f"Found {', '.join(evidence['matched'])} in {where}", evidence)
    what = f"'{p.name_pattern}'" + (f" ({', '.join(sorted(exts))})" if exts else "")
    msg = f"Expected {p.min_count} file(s) matching {what} in {where} {p.match_on} after the lab started"
    if p.content_contains:
        msg += f" containing {quote_list(p.content_contains)}"
    msg += "; " + (f"rejected: {'; '.join(rejected[:3])}" if rejected else "none found") + "."
    return Outcome(False, msg, evidence)


class OneDriveFile(Check):
    type = "onedrive_file"
    title = "OneDrive file"
    summary = ("A file exists in the lab user's OneDrive folder, created (or modified) after the lab started, "
               "optionally containing given text. Cowork saves new outputs to the user's OneDrive Cowork folder.")
    Params = FileParams
    example = {"folder": "/Cowork", "name_pattern": "*brief*", "extensions": ["docx"],
               "content_contains": ["Contoso"]}

    async def run(self, ctx: CheckContext, p: FileParams) -> Outcome:
        items = await ctx.source.drive_children(ctx.upn, p.folder)
        return await _evaluate_files(ctx, p, items, f"OneDrive {p.folder}")


class SharePointParams(FileParams):
    site: str = Field(description="hostname:/sites/path, e.g. contoso.sharepoint.com:/sites/ignite")
    library: str = "Documents"


class SharePointFile(Check):
    type = "sharepoint_file"
    title = "SharePoint file"
    summary = "A file exists in a SharePoint document library folder, authored by the lab user after the lab started."
    Params = SharePointParams
    example = {"site": "contoso.sharepoint.com:/sites/ignite", "library": "Documents", "folder": "/Proposals",
               "name_pattern": "*proposal*", "extensions": ["pptx"]}

    async def run(self, ctx: CheckContext, p: SharePointParams) -> Outcome:
        items = await ctx.source.site_drive_children(p.site, p.library, p.folder)
        return await _evaluate_files(ctx, p, items, f"SharePoint {p.library}{p.folder}")
