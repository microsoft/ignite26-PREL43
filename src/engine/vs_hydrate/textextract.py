"""Plain-text extraction used by scoring and the integrity lint.

Handles .docx, .xlsx, .pptx (XML inside the zip), .pdf (pypdf when present),
and text formats. Unknown binaries return an empty string.
"""
from __future__ import annotations

import io
import re
import zipfile

TEXT_EXT = (".md", ".txt", ".csv", ".json", ".yaml", ".yml", ".html", ".htm")
TAG_RE = re.compile(r"<[^>]+>")


def _xml_text(xml: str) -> str:
    xml = re.sub(r"</(w:p|a:p|row|si)>", "\n", xml)
    xml = re.sub(r"<(w:tab|w:br)\s*/>", " ", xml)
    txt = TAG_RE.sub("", xml)
    return (txt.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
               .replace("&quot;", '"').replace("&apos;", "'"))


def extract_text(name: str, data: bytes) -> str:
    low = name.lower()
    try:
        if low.endswith((".docx", ".xlsx", ".pptx")):
            z = zipfile.ZipFile(io.BytesIO(data))
            parts = [n for n in z.namelist()
                     if n.endswith(".xml") and (n.startswith(("word/", "xl/", "ppt/slides/", "ppt/notesSlides/")))]
            return "\n".join(_xml_text(z.read(n).decode("utf-8", "replace")) for n in sorted(parts))
        if low.endswith(".pdf"):
            try:
                from pypdf import PdfReader
            except ImportError:  # pragma: no cover
                return data.decode("latin-1", "replace")
            reader = PdfReader(io.BytesIO(data))
            return "\n".join((p.extract_text() or "") for p in reader.pages)
        if low.endswith(TEXT_EXT) or "." not in low.rsplit("/", 1)[-1]:
            txt = data.decode("utf-8", "replace")
            return TAG_RE.sub(" ", txt) if low.endswith((".html", ".htm")) else txt
    except (zipfile.BadZipFile, ValueError, KeyError):
        return ""
    return ""
