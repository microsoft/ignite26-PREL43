#!/usr/bin/env python3
"""Build the Helix data pack: data/helix/*.yaml -> helix-datapack-<version>.zip

Steps
  1. Validate the sources (references, counts, time limits, placeholders).
  2. Generate channel files: Word (spec, plan, sync notes), Excel (pricing),
     PDF (competitors), and persona photos.
  3. Recalculate the workbook with LibreOffice when available, so search and
     Copilot see computed values.
  4. Write manifest.json with counts and SHA-256 for every entry.
  5. Run the scoring-integrity lint against data/scoring/scorecard.json.
  6. Write the zip to data/release/ (committed, so a fresh clone can run).

Usage
  python src/tools/build_datapack.py [--no-recalc] [--out data/release]
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import date, datetime
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src" / "engine"))

from vs_hydrate.datapack import DataPack  # noqa: E402
from vs_hydrate.integrity import scan_datapack  # noqa: E402
from vs_hydrate.render import PH_RE, Context  # noqa: E402
from vs_hydrate.timeline import Timeline, parse_offset  # noqa: E402

from vs_hydrate import __version__ as VERSION  # noqa: E402

SRC = ROOT / "data" / "helix"
FIXED_TIME = (2026, 10, 1, 0, 0, 0)
NAVY = (0x06, 0x18, 0x5B)

# Exact counts the track's day-one check depends on.
EXPECT = {"thread": 6, "channel_messages": 20, "upcoming_events": 4,
          "shared_files": 6, "recordings": 2, "internal": 32, "external": 4}
LATEST = "D-1 09:00"
KNOWN_PH = {"learner", "learner_first", "learner_email", "date", "weekday", "mention"}


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    raise SystemExit(1)


# --------------------------------------------------------------------------- validation
def minutes(offset: str) -> int:
    d, t = parse_offset(offset)
    return d * 1440 + (t.hour * 60 + t.minute if t else 0)


def validate(src: dict) -> dict:
    people = src["people"]
    keys = {p["key"] for p in people["internal"]} | {p["key"] for p in people["external"]} | {"learner"}
    if len(people["internal"]) != EXPECT["internal"]:
        fail(f"expected {EXPECT['internal']} internal personas, found {len(people['internal'])}")
    if len(people["external"]) != EXPECT["external"]:
        fail(f"expected {EXPECT['external']} external contacts")
    for p in people["internal"]:
        if p["manager"] and p["manager"] not in keys:
            fail(f"{p['key']}: unknown manager {p['manager']}")

    def check_people(where, ks):
        for k in ks:
            if k not in keys:
                fail(f"{where}: unknown person {k!r}")

    def check_text(where, text):
        for m in PH_RE.finditer(text):
            if m.group(1) not in KNOWN_PH:
                fail(f"{where}: unknown placeholder {m.group(0)}")
            if m.group(1) in ("date", "weekday"):
                parse_offset(m.group(2))

    limit = minutes(LATEST)
    msgs = src["mail"]["messages"]
    ids = [m["id"] for m in msgs]
    if len(ids) != len(set(ids)):
        fail("duplicate mail ids")
    for m in msgs:
        check_people(m["id"], [m["from"], *m.get("to", []), *m.get("cc", [])])
        check_text(m["id"], m["subject"] + m["body"])
        if minutes(m["sent"]) > limit:
            fail(f"{m['id']}: {m['sent']} is later than {LATEST}")
    thread = [m for m in msgs if m.get("conversation") == "supplier"]
    if len(thread) != EXPECT["thread"]:
        fail(f"supplier thread must have {EXPECT['thread']} messages, has {len(thread)}")

    posts = src["teams"]["posts"]
    total = 0
    for p in posts:
        check_people(p["id"], [p["from"], *p.get("mentions", [])])
        check_text(p["id"], p["body"])
        if minutes(p["sent"]) > limit:
            fail(f"{p['id']}: {p['sent']} is later than {LATEST}")
        total += 1
        for r in p.get("replies", []):
            check_people(p["id"], [r["from"]])
            check_text(p["id"], r["body"])
            if not minutes(p["sent"]) < minutes(r["sent"]) <= limit:
                fail(f"{p['id']}: reply time {r['sent']} out of order or too late")
            total += 1
    if total != EXPECT["channel_messages"]:
        fail(f"channel must have {EXPECT['channel_messages']} messages, has {total}")
    team_created = minutes(src["teams"]["team"]["created"])
    if any(minutes(p["sent"]) <= team_created for p in posts):
        fail("a post predates the team")

    evs = src["calendar"]["events"]
    upcoming = []
    for e in evs:
        check_people(e["id"], [e["organiser"], *e["attendees"]])
        if "learner" not in e["attendees"]:
            fail(f"{e['id']}: seat must be an attendee")
        if e["organiser"] in {p["key"] for p in people["external"]}:
            fail(f"{e['id']}: organiser must be internal")
        s, en = minutes(e["start"]), minutes(e["end"])
        if s >= en:
            fail(f"{e['id']}: ends before it starts")
        if 0 <= s < 6 * 1440:
            upcoming.append((s, en))
    if len(upcoming) != EXPECT["upcoming_events"]:
        fail(f"need exactly {EXPECT['upcoming_events']} events in D0..D+5, found {len(upcoming)}")
    upcoming.sort()
    if not any(upcoming[i][1] > upcoming[i + 1][0] for i in range(len(upcoming) - 1)):
        fail("no two upcoming events overlap")
    for slot in ("D+1 10:00", "D+1 14:00", "D+1 16:00"):
        a = minutes(slot)
        if any(s < a + 30 and a < en for s, en in upcoming):
            fail(f"focus slot {slot} is not free")

    layout = src["teams"]["team"]["channels"][0]["files_folder"]
    if len(layout["shared"]) != EXPECT["shared_files"] or len(layout.get("Recordings", [])) != EXPECT["recordings"]:
        fail("channel files must be 6 shared plus 2 in Recordings")
    return {"messages": len(msgs), "supplier_thread": len(thread), "channel_posts": len(posts),
            "channel_messages": total, "events": len(evs), "upcoming_events": len(upcoming),
            "files": len(layout["shared"]) + len(layout["Recordings"]),
            "personas": len(people["internal"]), "external_contacts": len(people["external"])}



# --------------------------------------------------------------------------- metadata scrub
def scrub_office(data: bytes) -> bytes:
    """Remove the template thumbnail and generator names from an Office file's properties."""
    import re as _re
    src = zipfile.ZipFile(io.BytesIO(data))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            if info.filename == "docProps/thumbnail.jpeg":
                continue
            raw = src.read(info.filename)
            if info.filename == "_rels/.rels":
                raw = _re.sub(rb'<Relationship [^>]*thumbnail\.jpeg"[^>]*/>', b"", raw)
            if info.filename == "docProps/app.xml":
                raw = _re.sub(rb"<Application>.*?</Application>", b"<Application></Application>", raw)
                raw = _re.sub(rb"<AppVersion>.*?</AppVersion>", b"", raw)
            zi = zipfile.ZipInfo(info.filename, FIXED_TIME)
            zi.compress_type = zipfile.ZIP_DEFLATED
            dst.writestr(zi, raw)
    return buf.getvalue()

def scrub_pdf(data: bytes, title: str, author: str) -> bytes:
    """Set PDF properties to the persona and remove the generator's name."""
    from pypdf import PdfReader, PdfWriter
    w = PdfWriter(clone_from=PdfReader(io.BytesIO(data)))
    w.metadata = None
    w.add_metadata({"/Title": title, "/Author": author, "/Creator": "", "/Producer": ""})
    out = io.BytesIO()
    w.write(out)
    return out.getvalue()


# --------------------------------------------------------------------------- documents
def build_docx(spec: dict) -> bytes:
    from docx import Document
    from docx.shared import Pt, RGBColor

    doc = Document()
    st = doc.styles["Normal"]
    st.font.name = "Calibri"
    st.font.size = Pt(11)
    cp = doc.core_properties
    cp.author = spec["author"]
    cp.last_modified_by = spec["author"]
    cp.title = spec["title"]
    cp.created = cp.modified = datetime(*FIXED_TIME)
    doc.add_heading(spec["title"], 0)
    sub = doc.add_paragraph(spec["subtitle"])
    sub.runs[0].font.color.rgb = RGBColor(*NAVY)
    for b in spec["blocks"]:
        if "h" in b:
            doc.add_heading(b["h"], 1)
        elif "h2" in b:
            doc.add_heading(b["h2"], 2)
        elif "p" in b:
            doc.add_paragraph(b["p"])
        elif "bullets" in b:
            for item in b["bullets"]:
                doc.add_paragraph(item, style="List Bullet")
        elif "table" in b:
            rows = b["table"]
            t = doc.add_table(rows=len(rows), cols=len(rows[0]))
            t.style = "Light Grid Accent 1"
            for i, row in enumerate(rows):
                for j, val in enumerate(row):
                    t.cell(i, j).text = str(val)
            doc.add_paragraph("")
    buf = io.BytesIO()
    doc.save(buf)
    return scrub_office(buf.getvalue())


def build_pricing(spec: dict, recalc: bool) -> bytes:
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill

    wb = Workbook()
    ws = wb.active
    ws.title = "Scenarios"
    head = ["Scenario", "List price", "Unit cost", "Gross margin per unit", "Gross margin %",
            "Launch volume", "Revenue", "Gross profit"]
    ws.append(["Zava Helix: launch price scenarios"])
    ws["A1"].font = Font(bold=True, size=14, color="06185B")
    ws.append(["Owner: " + spec["author"] + ". Unit cost from the Corvane module quote plus assembly."])
    ws.append([])
    ws.append(head)
    for c in ws[4]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="06185B")
        c.alignment = Alignment(wrap_text=True, vertical="center")
    for i, s in enumerate(spec["scenarios"]):
        r = 5 + i
        ws.append([s["name"], s["price"], "=Assumptions!B3", f"=B{r}-C{r}", f"=D{r}/B{r}",
                   "=Assumptions!B4", f"=B{r}*F{r}", f"=D{r}*F{r}"])
        for col in "BCDGH":
            ws[f"{col}{r}"].number_format = '#,##0'
        ws[f"E{r}"].number_format = "0.0%"
        ws[f"F{r}"].number_format = "#,##0"
    ws.append([])
    ws.append(["Decision", "Not yet decided. Both scenarios remain open."])
    for col, w in zip("ABCDEFGH", (16, 12, 11, 14, 14, 14, 14, 14)):
        ws.column_dimensions[col].width = w
    a = wb.create_sheet("Assumptions")
    a.append(["Assumption", "Value", "Source"])
    for c in a[1]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="06185B")
    a.append(["Currency", "USD", "Finance policy"])
    a.append(["Unit cost", spec["unit_cost"], "Corvane module quote plus assembly"])
    a.append(["Launch volume (units)", spec["volume"], "Helix launch plan, section 2"])
    a.column_dimensions["A"].width = 24
    a.column_dimensions["B"].width = 12
    a.column_dimensions["C"].width = 40
    wb.properties.creator = spec["author"]
    wb.properties.lastModifiedBy = spec["author"]
    wb.properties.created = wb.properties.modified = datetime(*FIXED_TIME)
    buf = io.BytesIO()
    wb.save(buf)
    data = buf.getvalue()
    if recalc and shutil.which("soffice"):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / spec["file"]
            p.write_bytes(data)
            out = Path(td) / "out"
            subprocess.run(["soffice", "--headless", "--convert-to", "xlsx", "--outdir", str(out), str(p)],
                           check=True, capture_output=True, timeout=180)
            data = (out / spec["file"]).read_bytes()
    elif recalc:
        print("WARNING: LibreOffice not found; Helix-Pricing.xlsx has no cached formula values")
    return scrub_office(data)


def build_competitor_pdf(name: str, c: dict) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4, title=f"{c['product']} competitor profile",
                            author="Mei Tanaka", invariant=1)
    ss = getSampleStyleSheet()
    navy = colors.HexColor("#06185B")
    story = [Paragraph(f"Competitor profile: {c['product']}", ss["Title"]),
             Paragraph(f"Company: {c['company']}. Prepared by Mei Tanaka, Competitive Analyst, Zava.", ss["Normal"]),
             Spacer(1, 14)]
    t = Table([["Attribute", c["product"]], ["List price (USD)", str(c["price"])],
               ["Temperature accuracy", c["accuracy"]], ["Battery life", c["battery"]]],
              colWidths=[170, 260])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), navy), ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                           ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#C9D1E0")),
                           ("FONTSIZE", (0, 0), (-1, -1), 11), ("TOPPADDING", (0, 0), (-1, -1), 6),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    story += [t, Spacer(1, 14), Paragraph("Notes", ss["Heading2"])]
    story += [Paragraph(f"&bull; {n}", ss["Normal"]) for n in c["notes"]]
    story += [Spacer(1, 18), Paragraph("Figures are taken from the competitor's published product page and data sheet.", ss["Italic"])]
    doc.build(story)
    return scrub_pdf(buf.getvalue(), f"{c['product']} competitor profile", "Mei Tanaka")


PALETTE = ["#06185B", "#007FFF", "#8B3BAB", "#E8710A", "#0F8B8D", "#2E7D32", "#C62828", "#5C6B8A"]


def build_photo(key: str, name: str) -> bytes:
    from PIL import Image, ImageDraw, ImageFont

    size = 256
    col = PALETTE[int(hashlib.sha256(key.encode()).hexdigest(), 16) % len(PALETTE)]
    img = Image.new("RGB", (size, size), col)
    d = ImageDraw.Draw(img)
    initials = "".join(w[0] for w in name.split()[:2]).upper()
    font = None
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if Path(path).exists():
            font = ImageFont.truetype(path, 104)
            break
    font = font or ImageFont.load_default()
    box = d.textbbox((0, 0), initials, font=font)
    d.text(((size - (box[2] - box[0])) / 2 - box[0], (size - (box[3] - box[1])) / 2 - box[1]),
           initials, fill="white", font=font)
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


# --------------------------------------------------------------------------- pack
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "data" / "release"))
    ap.add_argument("--no-recalc", action="store_true", help="skip LibreOffice recalculation of the workbook")
    args = ap.parse_args()

    src = {p.stem: yaml.safe_load(p.read_text(encoding="utf-8")) for p in sorted(SRC.glob("*.yaml"))}
    counts = validate(src)
    docs = src["documents"]

    entries: dict[str, bytes] = {}
    for p in sorted(SRC.glob("*.yaml")):
        entries[f"source/{p.name}"] = p.read_bytes()
    for name, spec in docs["documents"].items():
        entries[f"files/{name}"] = build_docx(spec)
    entries[f"files/{docs['pricing']['file']}"] = build_pricing(docs["pricing"], not args.no_recalc)
    for name, c in docs["competitors"].items():
        entries[f"files/{name}"] = build_competitor_pdf(name, c)
    for p in src["people"]["internal"]:
        entries[f"photos/{p['key']}.png"] = build_photo(p["key"], f"{p['given']} {p['surname']}")

    layout = src["teams"]["team"]["channels"][0]["files_folder"]
    wanted = set(layout["shared"]) | set(layout["Recordings"])
    built = {k[len("files/"):] for k in entries if k.startswith("files/")}
    if wanted != built:
        fail(f"channel layout and built files differ: {sorted(wanted ^ built)}")

    manifest = {
        "name": "helix-datapack",
        "version": VERSION,
        "track": "COWORK-T1 Launch Command Center",
        "company": src["company"]["name"],
        "latest_content": LATEST,
        "counts": counts,
        "sha256": {k: hashlib.sha256(v).hexdigest() for k, v in sorted(entries.items())},
    }
    entries["manifest.json"] = json.dumps(manifest, indent=2).encode()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    zpath = out / f"helix-datapack-{VERSION}.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, entries[name])

    # Integrity lint on the finished pack.
    pack = DataPack.load(zpath)
    problems = pack.verify()
    if problems:
        fail("checksum problems: " + "; ".join(problems))
    forbidden = json.loads((ROOT / "data" / "scoring" / "scorecard.json").read_text())["seed_rules"]["forbidden"]
    tl = Timeline(date(2026, 10, 20), __import__("zoneinfo").ZoneInfo("UTC"))
    ctx = Context(tl, "Jordan Avery", "Jordan", "lab0001@zava.example")
    findings = scan_datapack(pack, forbidden, ctx)
    if findings:
        zpath.unlink()
        fail("scoring-integrity lint failed:\n  " + "\n  ".join(findings))

    print(f"Built {zpath.relative_to(ROOT) if zpath.is_relative_to(ROOT) else zpath}")
    print("  " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    print(f"  {len(entries)} entries, integrity lint passed ({len(forbidden)} forbidden phrases)")


if __name__ == "__main__":
    main()
