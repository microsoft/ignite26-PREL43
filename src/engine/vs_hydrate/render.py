"""Placeholder rendering for data pack text and Office files.

Placeholders:
  {{learner}}          seat persona's full name
  {{learner_first}}    seat persona's first name
  {{learner_email}}    seat UPN
  {{date:D+2}}         "Thursday 15 October 2026"
  {{weekday:D+2}}      "Thursday"
  {{mention:learner}}  Teams @mention (handled by the Teams writer)
"""
from __future__ import annotations

import html
import io
import re
import zipfile
from dataclasses import dataclass

from .timeline import Timeline

PH_RE = re.compile(r"\{\{\s*([a-z_]+)(?::([^}]+))?\s*\}\}")


@dataclass
class Context:
    timeline: Timeline
    learner: str
    learner_first: str
    learner_email: str

    def value(self, name: str, arg: str | None) -> str:
        if name == "learner":
            return self.learner
        if name == "learner_first":
            return self.learner_first
        if name == "learner_email":
            return self.learner_email
        if name == "date":
            return self.timeline.date_text(arg.strip())
        if name == "weekday":
            return self.timeline.weekday_text(arg.strip())
        if name == "mention":
            return self.learner  # plain-text fallback; Teams writer replaces first
        raise KeyError(f"unknown placeholder {{{{{name}}}}}")


def render(text: str, ctx: Context, escape: bool = False) -> str:
    def sub(m: re.Match) -> str:
        v = ctx.value(m.group(1), m.group(2))
        return html.escape(v, quote=False) if escape else v

    return PH_RE.sub(sub, text)


def placeholders(text: str) -> list[str]:
    return [m.group(0) for m in PH_RE.finditer(text)]


def text_to_html(text: str) -> str:
    """Plain text with blank-line paragraphs -> simple HTML."""
    paras = [p.strip() for p in text.strip().split("\n\n") if p.strip()]
    out = []
    for p in paras:
        lines = [html.escape(line) for line in p.split("\n")]
        out.append("<p>" + "<br>".join(lines) + "</p>")
    return "\n".join(out)


OFFICE_EXT = (".docx", ".xlsx", ".pptx")


def render_office(name: str, data: bytes, ctx: Context) -> bytes:
    """Render placeholders inside the XML parts of an Office file."""
    if not name.lower().endswith(OFFICE_EXT):
        return data
    src = zipfile.ZipFile(io.BytesIO(data))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            raw = src.read(info.filename)
            if info.filename.endswith(".xml"):
                txt = raw.decode("utf-8")
                if "{{" in txt:
                    txt = render(txt, ctx, escape=True)
                    raw = txt.encode("utf-8")
            dst.writestr(info, raw)
    return buf.getvalue()
