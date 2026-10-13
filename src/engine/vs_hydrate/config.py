"""tenant.yaml loading and validation. Exit code 3 on any configuration error."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

import yaml


class ConfigError(Exception):
    pass


GUID = re.compile(r"^[0-9a-fA-F-]{36}$")

DEFAULTS = {
    "datapack": {},
    "scoring": {"scorecard": "data/scoring/scorecard.json"},
    "readiness": {"check_set": "data/readiness/check-set-1.0.0.json"},
    "licences": {"seat_skus": ["SPE_E5", "Microsoft_365_Copilot"], "persona_sku": "SPE_E3"},
    "personas": {"usage_location": "US", "sign_in_enabled": False},
    "seats": {"prefix": "lab", "group": "VS-Lab-Seats", "time_zone": "UTC", "time_zone_iana": None,
              "locale": "en-US", "usage_location": "US", "given_name": "Jordan", "surname": "Avery",
              "reviewer": None, "tap_lifetime_minutes": 480, "team_add_personas": False,
              "provisioning_timeout_minutes": 30},
    "lab_day": "auto",
    "output": {"dir": "out"},
    "retire": {"permanent_delete": False},
    "attestations": {"cowork_enabled_for_group": False, "credits_policy_linked": False,
                     "external_mail_to_sink": False, "tap_policy_enabled": False},
}


def _merge(base: dict, over: dict) -> dict:
    out = dict(base)
    for k, v in (over or {}).items():
        out[k] = _merge(base[k], v) if isinstance(v, dict) and isinstance(base.get(k), dict) else v
    return out


@dataclass
class Config:
    raw: dict
    base_dir: Path
    path: Path
    offline: bool = False
    extra: dict = field(default_factory=dict)

    # ---------------------------------------------------------------- loading
    @classmethod
    def load(cls, path: str | Path, offline: bool = False) -> "Config":
        p = Path(path)
        if not p.is_file():
            raise ConfigError(f"configuration file not found: {p}")
        try:
            data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as e:
            raise ConfigError(f"{p}: invalid YAML: {e}") from e
        cfg = cls(raw=_merge(DEFAULTS, data), base_dir=p.resolve().parent, path=p, offline=offline)
        cfg.validate()
        return cfg

    def resolve(self, value: str) -> Path:
        v = Path(value)
        return v if v.is_absolute() else (self.base_dir / v)

    def validate(self) -> None:
        r = self.raw
        for key in ("tenant", "auth", "datapack"):
            if key not in r:
                raise ConfigError(f"missing section: {key}")
        if not r["tenant"].get("domain"):
            raise ConfigError("tenant.domain is required")
        if not self.offline:
            if not GUID.match(str(r["tenant"].get("id", ""))):
                raise ConfigError("tenant.id must be the directory (tenant) ID GUID")
            if not GUID.match(str(r["auth"].get("client_id", ""))):
                raise ConfigError("auth.client_id must be the app registration's client ID GUID")
            if not r["auth"].get("certificate_path"):
                raise ConfigError("auth.certificate_path is required (certificate credential)")
        if not r["datapack"].get("path"):
            raise ConfigError("datapack.path is required")
        if not re.match(r"^[a-z][a-z0-9]{1,15}$", r["seats"]["prefix"]):
            raise ConfigError("seats.prefix must be 2-16 lower-case letters or digits")
        if not r["licences"]["seat_skus"]:
            raise ConfigError("licences.seat_skus must list at least one SKU")
        ld = r["lab_day"]
        if ld != "auto":
            try:
                date.fromisoformat(str(ld))
            except ValueError as e:
                raise ConfigError("lab_day must be 'auto' or YYYY-MM-DD") from e
        tap = int(r["seats"]["tap_lifetime_minutes"])
        if not 10 <= tap <= 43200:
            raise ConfigError("seats.tap_lifetime_minutes must be between 10 and 43200")

    # ---------------------------------------------------------------- accessors
    @property
    def domain(self) -> str:
        return self.raw["tenant"]["domain"]

    @property
    def seats(self) -> dict:
        return self.raw["seats"]

    @property
    def licences(self) -> dict:
        return self.raw["licences"]

    @property
    def personas(self) -> dict:
        return self.raw["personas"]

    @property
    def out_dir(self) -> Path:
        d = self.resolve(self.raw["output"]["dir"])
        d.mkdir(parents=True, exist_ok=True)
        return d

    @property
    def datapack_path(self) -> Path:
        return self.resolve(self.raw["datapack"]["path"])

    @property
    def scorecard_path(self) -> Path:
        return self.resolve(self.raw["scoring"]["scorecard"])

    @property
    def check_set_path(self) -> Path:
        return self.resolve(self.raw["readiness"]["check_set"])

    def lab_day(self, today: date) -> date:
        ld = self.raw["lab_day"]
        return today if ld == "auto" else date.fromisoformat(str(ld))

    @property
    def reviewer_upn(self) -> str:
        return self.seats.get("reviewer") or f"helix.reviewer@{self.domain}"
