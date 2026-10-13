"""`validate`: read-only checks before any other command. Changes nothing."""
from __future__ import annotations

from datetime import timedelta

from ..api.base import TenantError
from ..config import ConfigError
from ..integrity import scan_datapack
from ..kit import Kit

REQUIRED_ROLES = {
    "User.ReadWrite.All": "personas, seats, profiles, managers, licences",
    "Group.ReadWrite.All": "seat group membership, team groups",
    "Organization.Read.All": "licence SKUs",
    "UserAuthenticationMethod.ReadWrite.All": "Temporary Access Pass for each seat",
    "MailboxSettings.ReadWrite": "seat time zone and locale",
    "Mail.ReadWrite": "seeded mail; scoring and readiness reads",
    "Calendars.ReadWrite": "meetings and acceptance",
    "Teamwork.Migrate.All": "backdated Teams import",
    "TeamMember.ReadWrite.All": "adding the seat to its team",
    "ChannelMessage.Read.All": "readiness check of channel posts",
    "Files.ReadWrite.All": "channel files; scoring reads of OneDrive",
    "Sites.ReadWrite.All": "channel SharePoint folder",
}

ATTESTATIONS = {
    "cowork_enabled_for_group": "Cowork is enabled for the seat group only",
    "credits_policy_linked": "Copilot Credits billing policy linked to an Azure subscription, with a per-seat cap",
    "external_mail_to_sink": "Mail to external addresses is routed to a sink mailbox, not rejected",
    "tap_policy_enabled": "Temporary Access Pass policy is enabled for the seat group, lifetime covers the lab",
}


def run(kit: Kit, args) -> tuple[int, dict]:
    checks: list[dict] = []

    def add(name, status, detail=""):
        checks.append({"check": name, "status": status, "detail": detail})

    # App permissions
    try:
        roles = kit.api.granted_roles()
        missing = sorted(set(REQUIRED_ROLES) - roles)
        add("app permissions", "fail" if missing else "pass",
            ("missing: " + ", ".join(missing)) if missing else f"{len(REQUIRED_ROLES)} application permissions granted")
    except TenantError as e:
        add("app permissions", "fail", str(e))
        roles = set()

    # Data pack
    probs = kit.pack.verify()
    add("data pack checksums", "fail" if probs else "pass",
        "; ".join(probs[:5]) if probs else f"helix-datapack {kit.pack.version}, {len(kit.pack.manifest['sha256'])} entries")
    tl = kit.timeline()
    findings = scan_datapack(kit.pack, kit.scorecard["seed_rules"]["forbidden"],
                             kit.learner_context(f"{kit.cfg.seats['prefix']}0001@{kit.cfg.domain}", tl))
    add("scoring integrity of data pack", "fail" if findings else "pass",
        "; ".join(findings[:5]) if findings else "no seeded item matches a scoring check")
    if kit.scorecard.get("version") != kit.pack.version:
        add("release versions", "warn", f"scorecard {kit.scorecard.get('version')} vs data pack {kit.pack.version}")

    # Licences
    if not roles or "Organization.Read.All" in roles:
        try:
            skus = kit.skus()
            for part in [*kit.cfg.licences["seat_skus"], kit.cfg.licences["persona_sku"]]:
                s = skus.get(part)
                if not s:
                    add(f"licence {part}", "fail", "SKU not found in tenant")
                    continue
                free = s.get("prepaidUnits", {}).get("enabled", 0) - s.get("consumedUnits", 0)
                add(f"licence {part}", "pass" if free > 0 else "fail", f"{free} available")
        except (TenantError, ConfigError) as e:
            add("licences", "fail", str(e))

    # Seat group
    try:
        g = kit.api.find_group(kit.cfg.seats["group"])
        add("seat group", "pass" if g else "fail",
            kit.cfg.seats["group"] if g else f"group {kit.cfg.seats['group']!r} not found")
    except TenantError as e:
        add("seat group", "fail", str(e))

    # Time and hydration window
    add("time zone", "pass", f"{kit.cfg.seats['time_zone']} ({kit.tz.key})")
    earliest = tl.utc(kit.pack.latest_content) + timedelta(minutes=30)
    if kit.cfg.raw["lab_day"] != "auto" and tl.lab_day < kit.now().astimezone(kit.tz).date():
        add("lab day", "fail", f"lab day {tl.lab_day} is in the past")
    elif kit.now() < earliest:
        add("hydration window", "warn",
            f"`seats` for lab day {tl.lab_day} can run from {earliest.astimezone(kit.tz):%Y-%m-%d %H:%M} "
            f"({kit.tz.key}); Teams import cannot write future-dated posts")
    else:
        add("hydration window", "pass", f"lab day {tl.lab_day}; seats can be hydrated now")

    # Tenant personas
    personas = kit.state.tenant.get("personas", {})
    add("personas", "pass" if len(personas) == len(kit.pack.internal) else "info",
        f"{len(personas)}/{len(kit.pack.internal)} created" + ("" if personas else "; run `tenant`"))

    # Manual attestations (not visible to app-only Graph)
    for key, text in ATTESTATIONS.items():
        ok = bool(kit.cfg.raw["attestations"].get(key))
        add(f"attest: {key}", "pass" if ok else "manual", text + ("" if ok else " (confirm, then set attestations." + key + ": true)"))

    failed = [c for c in checks if c["status"] == "fail"]
    return (1 if failed else 0), {"checks": checks, "ok": not failed}
