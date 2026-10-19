"""Apply db/migrations/*.sql in order. Safe to run on every deploy (Helm pre-upgrade hook)."""
import asyncio
import logging
from pathlib import Path

from sqlalchemy import text

from app.db import engine

MIGRATIONS_DIR = Path(__file__).resolve().parent.parent / "db" / "migrations"
LOCK_KEY = 784512  # pg_advisory_lock key so parallel pods never migrate at once

log = logging.getLogger("migrate")


async def migrate() -> list[str]:
    applied_now: list[str] = []
    async with engine.begin() as conn:
        await conn.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": LOCK_KEY})
        await conn.execute(text(
            "CREATE TABLE IF NOT EXISTS schema_migrations ("
            " version VARCHAR(200) PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())"
        ))
        done = {r[0] for r in (await conn.execute(text("SELECT version FROM schema_migrations"))).all()}
        for path in sorted(MIGRATIONS_DIR.glob("*.sql")):
            if path.name in done:
                continue
            log.info("applying %s", path.name)
            raw = await conn.get_raw_connection()
            await raw.driver_connection.execute(path.read_text())
            await conn.execute(text("INSERT INTO schema_migrations (version) VALUES (:v)"), {"v": path.name})
            applied_now.append(path.name)
    return applied_now


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    applied = asyncio.run(migrate())
    log.info("migrations applied: %s", applied or "none (up to date)")
