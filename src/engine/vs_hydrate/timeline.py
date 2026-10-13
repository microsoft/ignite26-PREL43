"""Relative dates.

Every timestamp in the data pack is an offset from the lab day (D0) in the
seat's time zone, for example "D-9 09:12" or "D+10". This keeps the launch
ten days out whenever the lab runs.
"""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

OFFSET_RE = re.compile(r"^\s*D\s*([+-]\s*\d+)?\s*(?:(\d{1,2}):(\d{2}))?\s*$")

# Windows time zone names (used by Exchange) to IANA names (used here).
WINDOWS_TO_IANA = {
    "UTC": "UTC",
    "GMT Standard Time": "Europe/London",
    "W. Europe Standard Time": "Europe/Berlin",
    "Romance Standard Time": "Europe/Paris",
    "Central Europe Standard Time": "Europe/Budapest",
    "India Standard Time": "Asia/Kolkata",
    "Singapore Standard Time": "Asia/Singapore",
    "Tokyo Standard Time": "Asia/Tokyo",
    "China Standard Time": "Asia/Shanghai",
    "AUS Eastern Standard Time": "Australia/Sydney",
    "Arabian Standard Time": "Asia/Dubai",
    "Eastern Standard Time": "America/New_York",
    "Central Standard Time": "America/Chicago",
    "Mountain Standard Time": "America/Denver",
    "Pacific Standard Time": "America/Los_Angeles",
    "E. South America Standard Time": "America/Sao_Paulo",
}


class OffsetError(ValueError):
    pass


def parse_offset(text: str) -> tuple[int, time | None]:
    """'D-9 09:12' -> (-9, 09:12); 'D+10' -> (10, None); 'D' -> (0, None)."""
    m = OFFSET_RE.match(str(text))
    if not m:
        raise OffsetError(f"not a lab-day offset: {text!r}")
    days = int(m.group(1).replace(" ", "")) if m.group(1) else 0
    t = time(int(m.group(2)), int(m.group(3))) if m.group(2) else None
    return days, t


def iana_zone(windows_name: str, iana_override: str | None = None) -> ZoneInfo:
    name = iana_override or WINDOWS_TO_IANA.get(windows_name)
    if not name:
        raise OffsetError(
            f"unknown time zone {windows_name!r}; set seats.time_zone_iana as well")
    return ZoneInfo(name)


@dataclass(frozen=True)
class Timeline:
    lab_day: date
    tz: ZoneInfo
    windows_tz: str = "UTC"

    def day(self, offset: str | int) -> date:
        days = offset if isinstance(offset, int) else parse_offset(offset)[0]
        return self.lab_day + timedelta(days=days)

    def at(self, offset: str) -> datetime:
        """Aware datetime in the seat time zone."""
        days, t = parse_offset(offset)
        return datetime.combine(self.lab_day + timedelta(days=days), t or time(0, 0), self.tz)

    def utc(self, offset: str) -> datetime:
        return self.at(offset).astimezone(timezone.utc)

    def utc_iso(self, offset: str) -> str:
        return self.utc(offset).strftime("%Y-%m-%dT%H:%M:%S.000Z")

    def local_iso(self, offset: str) -> str:
        """Wall-clock time for Graph {dateTime, timeZone} pairs."""
        return self.at(offset).strftime("%Y-%m-%dT%H:%M:%S")

    def date_text(self, offset: str) -> str:
        d = self.day(offset)
        return f"{d.strftime('%A')} {d.day} {d.strftime('%B %Y')}"

    def weekday_text(self, offset: str) -> str:
        return self.day(offset).strftime("%A")

    def window(self, start_offset: str, end_offset: str) -> tuple[datetime, datetime]:
        return self.at(start_offset), self.at(end_offset)
