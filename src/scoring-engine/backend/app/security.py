"""Credentials for both audiences: vendors (client credentials -> JWT) and admins (local or Entra ID)."""
import hashlib
import hmac
import secrets
import time
from dataclasses import dataclass

import httpx
import jwt
from fastapi import Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_session, utcnow
from app.models import Integration

settings = get_settings()

VENDOR_AUDIENCE = "vectorsense-scoring-api"
ADMIN_AUDIENCE = "vectorsense-scoring-admin"
ISSUER = "vectorsense-scoring"


# ---------- client credentials ----------

def generate_client_id() -> str:
    return "vsl_" + secrets.token_hex(12)


def generate_client_secret() -> str:
    return "vss_" + secrets.token_urlsafe(36)


def hash_secret(secret: str) -> str:
    # Secrets are 288-bit random values, so a keyed SHA-256 is sufficient (no need for a slow KDF).
    return hmac.new(settings.secret_pepper.encode(), secret.encode(), hashlib.sha256).hexdigest()


def verify_secret(secret: str, secret_hash: str) -> bool:
    return hmac.compare_digest(hash_secret(secret), secret_hash)


def issue_vendor_token(integration: Integration) -> tuple[str, int]:
    now = int(time.time())
    ttl = settings.vendor_token_ttl_seconds
    claims = {
        "iss": ISSUER,
        "aud": VENDOR_AUDIENCE,
        "sub": integration.id,
        "client_id": integration.client_id,
        "iat": now,
        "exp": now + ttl,
        "jti": secrets.token_hex(8),
    }
    return jwt.encode(claims, settings.jwt_signing_key, algorithm="HS256"), ttl


def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Missing bearer token",
                            headers={"WWW-Authenticate": "Bearer"})
    return authorization.split(" ", 1)[1].strip()


async def require_vendor(
    authorization: str | None = Header(default=None),
    session: AsyncSession = Depends(get_session),
) -> Integration:
    token = _bearer(authorization)
    try:
        claims = jwt.decode(token, settings.jwt_signing_key, algorithms=["HS256"],
                            audience=VENDOR_AUDIENCE, issuer=ISSUER)
    except jwt.PyJWTError as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Invalid token: {exc}",
                            headers={"WWW-Authenticate": "Bearer"}) from exc
    integration = await session.get(Integration, claims["sub"])
    if integration is None or integration.status != "active":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Integration revoked")
    # A rotated secret invalidates tokens issued before the rotation.
    if claims["iat"] < int(integration.secret_rotated_at.timestamp()):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Token issued before secret rotation")
    return integration


async def authenticate_client(session: AsyncSession, client_id: str, client_secret: str) -> Integration | None:
    integration = (await session.execute(
        select(Integration).where(Integration.client_id == client_id)
    )).scalar_one_or_none()
    if integration is None or integration.status != "active":
        return None
    if not verify_secret(client_secret, integration.secret_hash):
        return None
    integration.last_used_at = utcnow()
    await session.commit()
    return integration


def sign_webhook(secret: str, body: bytes, timestamp: int) -> str:
    mac = hmac.new(secret.encode(), f"{timestamp}.".encode() + body, hashlib.sha256).hexdigest()
    return f"t={timestamp},v1={mac}"


# ---------- admin ----------

@dataclass
class Admin:
    username: str
    name: str


def issue_local_admin_token(username: str) -> str:
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "aud": ADMIN_AUDIENCE, "sub": username, "name": username,
                       "iat": now, "exp": now + 12 * 3600}, settings.jwt_signing_key, algorithm="HS256")


class _EntraKeys:
    """Caches the Entra ID signing keys (JWKS) for admin token validation."""

    def __init__(self) -> None:
        self._client: jwt.PyJWKClient | None = None

    def client(self) -> jwt.PyJWKClient:
        if self._client is None:
            url = f"https://login.microsoftonline.com/{settings.entra_tenant_id}/discovery/v2.0/keys"
            self._client = jwt.PyJWKClient(url, cache_keys=True, lifespan=3600)
        return self._client


_entra_keys = _EntraKeys()


def _validate_entra(token: str) -> Admin:
    signing_key = _entra_keys.client().get_signing_key_from_jwt(token)
    audiences = [settings.entra_api_client_id, f"api://{settings.entra_api_client_id}"]
    claims = jwt.decode(
        token, signing_key.key, algorithms=["RS256"], audience=audiences,
        issuer=f"https://login.microsoftonline.com/{settings.entra_tenant_id}/v2.0",
    )
    if settings.entra_required_role and settings.entra_required_role not in claims.get("roles", []):
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"Missing app role {settings.entra_required_role}")
    return Admin(username=claims.get("preferred_username") or claims.get("oid", "unknown"),
                 name=claims.get("name") or claims.get("preferred_username") or "Admin")


async def require_admin(authorization: str | None = Header(default=None)) -> Admin:
    token = _bearer(authorization)
    try:
        if settings.auth_mode == "entra":
            return _validate_entra(token)
        claims = jwt.decode(token, settings.jwt_signing_key, algorithms=["HS256"],
                            audience=ADMIN_AUDIENCE, issuer=ISSUER)
        return Admin(username=claims["sub"], name=claims.get("name", claims["sub"]))
    except HTTPException:
        raise
    except (jwt.PyJWTError, httpx.HTTPError) as exc:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"Invalid admin token: {exc}") from exc
