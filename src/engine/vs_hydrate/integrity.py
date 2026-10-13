"""Scoring integrity: seeded data must never satisfy a scoring check.

The forbidden phrases come from scorecard.json (`seed_rules.forbidden`).
`scan_datapack` checks every seeded string and every file in a data pack.
The readiness check runs the same idea against a live seat by scoring it.
"""
from __future__ import annotations

from .datapack import DataPack
from .render import Context, render, render_office
from .textextract import extract_text


def find_forbidden(text: str, forbidden: list[str]) -> list[str]:
    low = text.lower()
    return [f for f in forbidden if f.lower() in low]


def scan_datapack(pack: DataPack, forbidden: list[str], ctx: Context) -> list[str]:
    findings = []
    for where, raw in pack.all_text_items():
        txt = render(raw, ctx)
        for hit in find_forbidden(txt, forbidden):
            findings.append(f"{where}: contains {hit!r}")
    for name, data in pack.files.items():
        txt = extract_text(name, render_office(name, data, ctx))
        for hit in find_forbidden(txt, forbidden):
            findings.append(f"file {name}: contains {hit!r}")
    return findings
