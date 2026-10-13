"""`score --seat <upn>`: run the 12 scoring checks for one seat."""
from __future__ import annotations

from ..kit import Kit
from ..scoring import evaluate
from ..state import now_iso


def run(kit: Kit, args) -> tuple[int, dict]:
    st = kit.state
    seat = st.seats.get(args.seat)
    if not seat:
        user = kit.api.get_user(args.seat)
        if not user:
            return 3, {"error": f"seat {args.seat} not found"}
        # Scored from a host without this seat's state: use today's lab day window.
        seat = {"upn": args.seat, "id": user["id"], "lab_day": kit.timeline().lab_day.isoformat(),
                "state": "used", "phases": []}
    result = evaluate(kit, seat)
    if args.seat in st.seats:
        s = st.seats[args.seat]
        s.setdefault("scores", []).append({"at": now_iso(), "score": result["score"], "passed": result["passed"]})
        if s["state"] in ("ready", "hydrated"):
            s["state"] = "used"
        st.save()
    if not args.details:
        result.pop("details", None)
    return 0, result
