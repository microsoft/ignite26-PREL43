"""Dependency-free text extraction for content checks: Office Open XML files are zips of XML."""
import html
import io
import re
import zipfile

_TAG = re.compile(r"<[^>]+>")
_PARTS = {
    "docx": re.compile(r"^word/(document|header\d*|footer\d*)\.xml$"),
    "pptx": re.compile(r"^ppt/slides/slide\d+\.xml$"),
    "xlsx": re.compile(r"^xl/(sharedStrings|worksheets/sheet\d+)\.xml$"),
}
TEXT_EXTENSIONS = {"txt", "md", "csv", "json", "html", "htm", "xml", "log"}
SUPPORTED = set(_PARTS) | TEXT_EXTENSIONS


def extract_text(data: bytes, extension: str) -> str | None:
    ext = extension.lower().lstrip(".")
    if ext in TEXT_EXTENSIONS:
        return data.decode("utf-8", errors="ignore")
    part = _PARTS.get(ext)
    if part is None:
        return None
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            chunks = [zf.read(n).decode("utf-8", errors="ignore") for n in zf.namelist() if part.match(n)]
    except zipfile.BadZipFile:
        # Mock evidence and some exports hand back plain text even for Office extensions.
        return data.decode("utf-8", errors="ignore")
    return html.unescape(_TAG.sub(" ", " ".join(chunks)))
