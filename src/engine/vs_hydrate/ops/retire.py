"""`retire --seat <upn>` | `retire --used` | `retire --failed`

Removes a seat: its team (and the channel files with it), the meetings the
personas organised for it, its licences and the account. Personas are never
touched. Seats are single-use, so a retired seat is never reused.
"""
from __future__ import annotations

import logging

from ..api.base import TenantError
from ..kit import Kit
from ..state import now_iso, write_inventory

log = logging.getLogger("vs_hydrate.retire")


def looks_used(kit: Kit, seat: dict) -> bool:
    """A seat counts as used once it was scored or the learner produced anything."""
    if seat["state"] == "used" or seat.get("scores"):
        return True
    if seat["state"] not in ("ready", "hydrated") or not seat.get("id"):
        return False
    try:
        for folder in ("drafts", "sentitems"):
            if kit.api.list_messages(seat["id"], folder, top=1):
                return True
        d = kit.api.user_drive(seat["id"])
        if d and any(i["name"] == "Cowork" for i in kit.api.drive_items(d["id"])):
            return True
    except TenantError as e:
        log.warning("could not inspect %s: %s", seat["upn"], e)
    return False


def retire_seat(kit: Kit, seat: dict) -> list[str]:
    api, errs = kit.api, []
    if seat.get("team_id"):
        try:
            api.delete_group(seat["team_id"])
        except TenantError as e:
            errs.append(f"team: {e}")
    for ev_id, rec in seat.get("events", {}).items():
        try:
            api.delete_event(rec["organiser_id"], rec["id"])
        except TenantError as e:
            errs.append(f"event {ev_id}: {e}")
    if seat.get("id"):
        try:
            skus = list(api.user_license_skus(seat["id"]))
            if skus:
                api.assign_licenses(seat["id"], [], skus)
        except TenantError as e:
            if e.status != 404:
                errs.append(f"licences: {e}")
        try:
            api.delete_user(seat["id"], permanent=bool(kit.cfg.raw["retire"]["permanent_delete"]))
        except TenantError as e:
            errs.append(f"user: {e}")
    return errs


def run(kit: Kit, args) -> tuple[int, dict]:
    st = kit.state
    if args.seat:
        seat = st.seats.get(args.seat)
        if not seat:
            u = kit.api.get_user(args.seat)
            if not u:
                return 3, {"error": f"unknown seat {args.seat}"}
            seat = st.seat(args.seat)
            seat["id"] = u["id"]
        targets = [seat]
    elif args.used:
        targets = [s for s in st.seats.values() if s["state"] != "retired" and looks_used(kit, s)]
    elif args.failed:
        targets = [s for s in st.seats.values() if s["state"] == "failed"]
    else:
        return 3, {"error": "retire needs --seat <upn>, --used or --failed"}

    done, errors = [], {}
    for s in targets:
        errs = retire_seat(kit, s)
        if errs:
            errors[s["upn"]] = errs
        else:
            s["state"] = "retired"
            s["retired_at"] = now_iso()
            s.pop("tap", None)
            done.append(s["upn"])
        st.save()
    write_inventory(kit.cfg.out_dir, st)
    body = {"retired": done, "errors": errors,
            "ready_in_pool": sum(1 for s in st.seats.values() if s["state"] == "ready")}
    if kit.dry_run:
        body["planned_writes"] = kit.api.planned
    return (2 if errors else 0), body
