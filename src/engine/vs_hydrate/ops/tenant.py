"""`tenant`: personas, directory profiles, managers, photos and the reviewer.

Run once per tenant, and again after a data-pack release. Idempotent: existing
accounts are updated in place, never duplicated, never deleted.
"""
from __future__ import annotations

import logging
import secrets
import string

from ..api.base import NotReady, TenantError
from ..kit import Kit

log = logging.getLogger("vs_hydrate.tenant")


def random_password() -> str:
    alphabet = string.ascii_letters + string.digits + "!#%+-=?"
    while True:
        p = "".join(secrets.choice(alphabet) for _ in range(24))
        if any(c.isupper() for c in p) and any(c.islower() for c in p) and any(c.isdigit() for c in p):
            return p


def ensure_user(kit: Kit, upn: str, profile: dict, enabled: bool, usage_location: str) -> tuple[str, bool]:
    existing = kit.api.get_user(upn)
    if existing:
        kit.api.update_user(existing["id"], {**profile, "usageLocation": usage_location})
        return existing["id"], False
    body = {"accountEnabled": enabled, "userPrincipalName": upn, "mailNickname": upn.split("@")[0],
            "usageLocation": usage_location, **profile,
            "passwordProfile": {"forceChangePasswordNextSignIn": True, "password": random_password()}}
    return kit.api.create_user(body)["id"], True


def run(kit: Kit, args) -> tuple[int, dict]:
    pack, cfg, st = kit.pack, kit.cfg, kit.state
    sku = kit.sku_id(cfg.licences["persona_sku"])
    enabled = bool(cfg.personas["sign_in_enabled"])
    usage = cfg.personas["usage_location"]
    personas = st.tenant.setdefault("personas", {})
    created, updated, errors, pending_photos = [], [], [], []

    for p in pack.internal:
        upn = pack.upn(p["key"], cfg.domain)
        profile = {"displayName": pack.display(p), "givenName": p["given"], "surname": p["surname"],
                   "jobTitle": p["title"], "department": p["department"], "officeLocation": p["office"],
                   "companyName": pack.company["name"]}
        try:
            uid, new = ensure_user(kit, upn, profile, enabled, usage)
            personas[p["key"]] = uid
            (created if new else updated).append(upn)
            if sku not in kit.api.user_license_skus(uid):
                kit.api.assign_licenses(uid, [sku])
        except TenantError as e:
            errors.append(f"{upn}: {e}")
    st.save()

    # Reviewer account for Milestone 5 skill sharing.
    r = pack.people["reviewer"]
    try:
        rid, new = ensure_user(kit, cfg.reviewer_upn,
                               {"displayName": f"{r['given']} {r['surname']}", "givenName": r["given"],
                                "surname": r["surname"], "jobTitle": r["title"], "department": r["department"],
                                "companyName": pack.company["name"]}, enabled, usage)
        st.tenant["reviewer"] = rid
        if sku not in kit.api.user_license_skus(rid):
            kit.api.assign_licenses(rid, [sku])
        (created if new else updated).append(cfg.reviewer_upn)
    except TenantError as e:
        errors.append(f"{cfg.reviewer_upn}: {e}")

    # Reporting lines.
    for p in pack.internal:
        if p["manager"] and p["key"] in personas and p["manager"] in personas:
            try:
                kit.api.set_manager(personas[p["key"]], personas[p["manager"]])
            except TenantError as e:
                errors.append(f"manager for {p['key']}: {e}")

    # Photos need a mailbox; pending ones are retried on the next run.
    for p in pack.internal:
        uid = personas.get(p["key"])
        if not uid or p["key"] in st.tenant.get("photos", []):
            continue
        png = pack.photos.get(p["key"])
        if not png:
            continue
        try:
            kit.api.set_photo(uid, png)
            st.tenant.setdefault("photos", []).append(p["key"])
        except NotReady:
            pending_photos.append(p["key"])
        except TenantError as e:
            errors.append(f"photo for {p['key']}: {e}")

    mailboxes_pending = [k for k, uid in personas.items() if not kit.api.mailbox_ready(uid)]
    st.tenant["datapack"] = pack.version
    st.tenant["complete"] = not errors and len(personas) == len(pack.internal)
    st.tenant["mailboxes_ready"] = not mailboxes_pending
    st.save()

    body = {"created": len(created), "updated": len(updated), "personas": len(personas),
            "reviewer": cfg.reviewer_upn, "photos_pending": pending_photos,
            "mailboxes_pending": mailboxes_pending, "errors": errors}
    if mailboxes_pending or pending_photos:
        body["next"] = "Persona mailboxes are still provisioning. Re-run `tenant` later; `seats` waits for organiser mailboxes."
    return (2 if errors else 0), body
