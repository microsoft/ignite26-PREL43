from collections.abc import AsyncIterator
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import get_settings

_settings = get_settings()

_engine_kwargs = {"pool_pre_ping": True}
if _settings.database_url.startswith("postgresql"):
    _engine_kwargs.update(pool_size=_settings.db_pool_size, max_overflow=_settings.db_pool_size)

engine = create_async_engine(_settings.database_url, **_engine_kwargs)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


def is_postgres() -> bool:
    return engine.dialect.name == "postgresql"


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
