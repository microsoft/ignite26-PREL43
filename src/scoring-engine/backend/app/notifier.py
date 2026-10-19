"""Realtime fan-out for leaderboards.

Workers publish a tiny "event X changed" signal through Postgres NOTIFY. Each API pod holds one
LISTEN connection and fans the signal out to its connected SSE clients, which then refetch over
plain HTTP. Signals never carry participant data, so the stream can stay unauthenticated.
"""
import asyncio
import json
import logging

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import is_postgres

CHANNEL = "scoring_updates"
log = logging.getLogger("notifier")


async def publish(session: AsyncSession, event_id: str, kind: str = "update") -> None:
    payload = json.dumps({"event_id": event_id, "kind": kind})
    if is_postgres():
        await session.execute(text("SELECT pg_notify(:c, :p)"), {"c": CHANNEL, "p": payload})
    else:
        hub.dispatch(payload)


class Hub:
    def __init__(self) -> None:
        self._subscribers: dict[str, set[asyncio.Queue]] = {}
        self._task: asyncio.Task | None = None

    def subscribe(self, event_id: str) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=16)
        self._subscribers.setdefault(event_id, set()).add(q)
        return q

    def unsubscribe(self, event_id: str, q: asyncio.Queue) -> None:
        subs = self._subscribers.get(event_id)
        if subs:
            subs.discard(q)

    def dispatch(self, payload: str) -> None:
        try:
            msg = json.loads(payload)
        except ValueError:
            return
        for q in list(self._subscribers.get(msg.get("event_id"), ())):
            if not q.full():  # a slow client just misses a ping; it refetches on the next one
                q.put_nowait(msg)

    async def start(self) -> None:
        if is_postgres() and self._task is None:
            self._task = asyncio.create_task(self._listen_forever())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()

    async def _listen_forever(self) -> None:
        import asyncpg

        # SQLAlchemy's asyncpg URL takes ?ssl=require; a raw asyncpg DSN spells it sslmode.
        dsn = (get_settings().database_url.replace("postgresql+asyncpg://", "postgresql://")
               .replace("ssl=require", "sslmode=require"))
        while True:
            try:
                conn = await asyncpg.connect(dsn)
                await conn.add_listener(CHANNEL, lambda *args: self.dispatch(args[-1]))
                log.info("listening on %s", CHANNEL)
                while not conn.is_closed():
                    await asyncio.sleep(15)
                    await conn.execute("SELECT 1")
            except asyncio.CancelledError:
                raise
            except Exception:  # reconnect on any connection failure
                log.exception("listener dropped, reconnecting")
                await asyncio.sleep(3)


hub = Hub()
