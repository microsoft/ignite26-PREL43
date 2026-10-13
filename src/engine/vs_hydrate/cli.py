"""vs-hydrate command line.

  vs-hydrate validate            --config tenant.yaml
  vs-hydrate tenant              --config tenant.yaml
  vs-hydrate seats --count N     --config tenant.yaml
  vs-hydrate check [--seat UPN]  --config tenant.yaml
  vs-hydrate score --seat UPN    --config tenant.yaml --json
  vs-hydrate retire --seat UPN | --used | --failed

Exit codes: 0 success, 1 validation failed, 2 partial failure (see report),
3 configuration error.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
import threading

from . import __version__
from .api.base import TenantError
from .config import Config, ConfigError
from .kit import Kit
from .state import write_report

EXIT_OK, EXIT_VALIDATION, EXIT_PARTIAL, EXIT_CONFIG = 0, 1, 2, 3


class Locked:
    """Serialises calls into a non-thread-safe API (the offline fake)."""

    def __init__(self, api):
        self._api, self._lock = api, threading.RLock()

    def __getattr__(self, name):
        target = getattr(self._api, name)
        if not callable(target):
            return target

        def call(*a, **k):
            with self._lock:
                return target(*a, **k)
        return call


def build_parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--config", default="tenant.yaml", help="path to tenant.yaml (default: ./tenant.yaml)")
    common.add_argument("--json", action="store_true", help="machine-readable output")
    common.add_argument("--dry-run", action="store_true", help="show what would change without writing")
    common.add_argument("--concurrency", type=int, default=4, help="parallel seats (default 4)")
    common.add_argument("--offline", action="store_true",
                        help="rehearse against an in-memory tenant saved in out/offline-tenant.json")
    common.add_argument("-v", "--verbose", action="store_true")

    p = argparse.ArgumentParser(prog="vs-hydrate", description="VectorSense Hydration Kit engine",
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    p.add_argument("--version", action="version", version=f"vs-hydrate {__version__}")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("validate", parents=[common], help="check permissions, licences, data pack; changes nothing")
    sub.add_parser("tenant", parents=[common], help="create or update personas and the reviewer account")
    s = sub.add_parser("seats", parents=[common], help="create and hydrate new seats (resumes an unfinished batch)")
    s.add_argument("--count", type=int, default=0)
    c = sub.add_parser("check", parents=[common], help="readiness check; writes seat-inventory.json")
    c.add_argument("--seat")
    c.add_argument("--all", action="store_true", help="re-check ready seats too")
    sc = sub.add_parser("score", parents=[common], help="score one seat")
    sc.add_argument("--seat", required=True)
    sc.add_argument("--details", action="store_true", help="include the reason for each check")
    r = sub.add_parser("retire", parents=[common], help="remove seats and release licences")
    g = r.add_mutually_exclusive_group(required=True)
    g.add_argument("--seat")
    g.add_argument("--used", action="store_true")
    g.add_argument("--failed", action="store_true")
    return p


def make_api(cfg: Config):
    if cfg.offline:
        from .api.fake import FakeTenant
        fake = FakeTenant.open(cfg.out_dir / "offline-tenant.json", groups=[cfg.seats["group"]])
        return fake, Locked(fake)
    from .api.graph import GraphTenant
    a = cfg.raw["auth"]
    return None, GraphTenant(cfg.raw["tenant"]["id"], a["client_id"], str(cfg.resolve(a["certificate_path"])))


def human(command: str, code: int, body: dict) -> str:
    if "error" in body:
        return f"error (exit {code}): {body['error']}"
    if command == "score":
        lines = [f"{body['seat']}: {body['score']}/{body['max']} ({'PASS' if body['passed'] else 'NOT PASSED'}, pass mark {body['pass_mark']})"]
        lines += [f"  {k:<26} {v}" for k, v in body["checks"].items()]
        if body.get("recheck"):
            lines.append("  re-check later: " + ", ".join(body["recheck"]))
        lines.append("  " + body["feedback"])
        return "\n".join(lines)
    if command == "validate":
        mark = {"pass": "ok  ", "fail": "FAIL", "warn": "warn", "manual": "todo", "info": "info"}
        return "\n".join(f"[{mark.get(c['status'], c['status'])}] {c['check']}: {c['detail']}" for c in body["checks"])
    out = []
    for k, v in body.items():
        if k in ("seats", "planned_writes") and isinstance(v, (list, dict)) and len(v) > 12:
            out.append(f"{k}: {len(v)} entries (see report)")
        else:
            out.append(f"{k}: {json.dumps(v) if isinstance(v, (list, dict)) else v}")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.WARNING,
                        format="%(levelname)s %(name)s: %(message)s", stream=sys.stderr)
    from .ops import check, retire, score, seats, tenant, validate
    ops = {"validate": validate, "tenant": tenant, "seats": seats, "check": check, "score": score, "retire": retire}
    fake = None
    try:
        cfg = Config.load(args.config, offline=args.offline)
        fake, api = make_api(cfg)
        kit = Kit.build(cfg, api, dry_run=args.dry_run, concurrency=args.concurrency)
        code, body = ops[args.command].run(kit, args)
    except ConfigError as e:
        code, body = EXIT_CONFIG, {"error": str(e)}
    except TenantError as e:
        code, body = EXIT_PARTIAL, {"error": str(e)}
    finally:
        if fake is not None and not args.dry_run:
            fake.save()
    body = {"version": __version__, "exit_code": code, **body}
    try:
        if "cfg" in locals():
            body["report"] = str(write_report(cfg.out_dir, args.command, body))
    except OSError:
        pass
    print(json.dumps(body, indent=2, default=str) if args.json else human(args.command, code, body))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
