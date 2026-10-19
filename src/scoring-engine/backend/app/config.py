"""Runtime configuration. Every value comes from the environment so one image deploys to any tenant."""
from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="VS_", env_file=".env", extra="ignore")

    app_name: str = "VectorSense Labs - Scoring Engine"
    environment: str = "local"
    public_base_url: str = "http://localhost:8080"       # admin portal + partner API
    scorecard_base_url: str = "http://localhost:8081"    # participant scorecard app

    # Database
    database_url: str = "postgresql+asyncpg://scoring:scoring@localhost:5432/scoring"
    db_pool_size: int = 10

    # Vendor API tokens (OAuth2 client credentials issued by this app)
    jwt_signing_key: str = "change-me-in-production-please-32b"
    vendor_token_ttl_seconds: int = 3600
    secret_pepper: str = "change-me-pepper"

    # Admin portal authentication
    auth_mode: Literal["local", "entra"] = "local"
    admin_username: str = "admin"
    admin_password: str = "admin"
    entra_tenant_id: str = ""
    entra_api_client_id: str = ""  # app registration that exposes the admin API
    entra_spa_client_id: str = ""  # SPA app registration used by the portal
    entra_required_role: str = "Scoring.Admin"

    # Microsoft Graph evidence source
    graph_mode: Literal["live", "mock"] = "mock"
    graph_tenant_id: str = ""
    graph_mock_file: str = "/app/samples/mock_graph.json"
    graph_max_concurrency: int = 16

    # Worker
    worker_concurrency: int = 8
    worker_poll_interval_seconds: float = 1.0
    worker_stale_lock_seconds: int = 300
    deferred_recheck_interval_seconds: int = 300
    deferred_max_age_seconds: int = 3 * 3600

    # CORS (only needed if the portal is served from another origin)
    cors_origins: str = ""


@lru_cache
def get_settings() -> Settings:
    return Settings()
