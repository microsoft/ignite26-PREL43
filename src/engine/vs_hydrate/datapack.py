"""Load and verify a data pack (zip or unpacked directory).

Layout:
  manifest.json            version, counts, checksums
  source/*.yaml            company, people, mail, teams, calendar, documents
  files/<name>             channel files (docx, xlsx, pdf)
  photos/<key>.png         persona photos
"""
from __future__ import annotations

import hashlib
import json
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import yaml

SOURCES = ("company", "people", "mail", "teams", "calendar", "documents")


class DataPackError(Exception):
    pass


@dataclass
class DataPack:
    manifest: dict
    company: dict
    people: dict
    mail: dict
    teams: dict
    calendar: dict
    documents: dict
    files: dict[str, bytes] = field(default_factory=dict)
    photos: dict[str, bytes] = field(default_factory=dict)
    _raw: dict[str, bytes] = field(default_factory=dict, repr=False)

    # ------------------------------------------------------------------ loading
    @classmethod
    def load(cls, path: str | Path) -> "DataPack":
        path = Path(path)
        raw: dict[str, bytes] = {}
        if path.is_dir():
            for p in sorted(path.rglob("*")):
                if p.is_file():
                    raw[p.relative_to(path).as_posix()] = p.read_bytes()
        elif path.is_file():
            with zipfile.ZipFile(path) as z:
                for n in z.namelist():
                    if not n.endswith("/"):
                        raw[n] = z.read(n)
        else:
            raise DataPackError(f"data pack not found: {path}")
        if "manifest.json" not in raw:
            raise DataPackError("data pack has no manifest.json")
        manifest = json.loads(raw["manifest.json"])
        src = {}
        for s in SOURCES:
            key = f"source/{s}.yaml"
            if key not in raw:
                raise DataPackError(f"data pack is missing {key}")
            src[s] = yaml.safe_load(raw[key])
        files = {k[len("files/"):]: v for k, v in raw.items() if k.startswith("files/")}
        photos = {Path(k).stem: v for k, v in raw.items() if k.startswith("photos/")}
        return cls(manifest=manifest, files=files, photos=photos, _raw=raw, **src)

    def verify(self) -> list[str]:
        """Return a list of problems; empty means the checksums match."""
        problems = []
        sums = self.manifest.get("sha256", {})
        for name, digest in sums.items():
            data = self._raw.get(name)
            if data is None:
                problems.append(f"missing {name}")
            elif hashlib.sha256(data).hexdigest() != digest:
                problems.append(f"checksum mismatch {name}")
        for name in self._raw:
            if name != "manifest.json" and name not in sums:
                problems.append(f"unlisted file {name}")
        return problems

    # ------------------------------------------------------------------ helpers
    @property
    def version(self) -> str:
        return self.manifest["version"]

    @property
    def latest_content(self) -> str:
        return self.manifest.get("latest_content", "D-1 09:00")

    @property
    def internal(self) -> list[dict]:
        return self.people["internal"]

    @property
    def external(self) -> list[dict]:
        return self.people["external"]

    def person(self, key: str) -> dict:
        for p in self.internal:
            if p["key"] == key:
                return {**p, "kind": "internal"}
        for p in self.external:
            if p["key"] == key:
                return {**p, "kind": "external"}
        raise DataPackError(f"unknown person key {key!r}")

    @staticmethod
    def display(p: dict) -> str:
        return f"{p['given']} {p['surname']}"

    def address(self, key: str, domain: str) -> dict:
        """{name, address} for a persona or external contact."""
        p = self.person(key)
        addr = p["email"] if p["kind"] == "external" else f"{p['mail']}@{domain}"
        return {"name": self.display(p), "address": addr}

    def upn(self, key: str, domain: str) -> str:
        p = self.person(key)
        if p["kind"] != "internal":
            raise DataPackError(f"{key} is external and has no account")
        return f"{p['mail']}@{domain}"

    @property
    def messages(self) -> list[dict]:
        return self.mail["messages"]

    @property
    def posts(self) -> list[dict]:
        return self.teams["posts"]

    @property
    def team(self) -> dict:
        return self.teams["team"]

    @property
    def channel(self) -> dict:
        return self.team["channels"][0]

    @property
    def events(self) -> list[dict]:
        return self.calendar["events"]

    def file_layout(self) -> list[tuple[str | None, str]]:
        """[(subfolder or None, file name)] for the channel files folder."""
        out = []
        for folder, names in self.channel["files_folder"].items():
            for n in names:
                out.append((None if folder == "shared" else folder, n))
        return out

    def all_text_items(self):
        """Yield (where, raw text) for every seeded string, before rendering."""
        for m in self.messages:
            yield f"mail {m['id']} subject", m["subject"]
            yield f"mail {m['id']} body", m["body"]
        for p in self.posts:
            yield f"post {p['id']}", p["body"]
            for i, r in enumerate(p.get("replies", []), 1):
                yield f"post {p['id']} reply {i}", r["body"]
        for e in self.events:
            yield f"event {e['id']} subject", e["subject"]
            yield f"event {e['id']} body", e.get("body", "")
        yield "team name", self.team["display_name"]
        yield "channel name", self.channel["name"]
        for _, name in self.file_layout():
            yield f"file name {name}", name
