import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt
from argon2 import PasswordHasher, Type, exceptions as argon2_exceptions

from app.config import settings

_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4, hash_len=32, salt_len=16, type=Type.ID)
_DUMMY_HASH = _hasher.hash("timing-equalisation-dummy")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, stored_hash: str) -> tuple[bool, str | None]:
    """Returns (is_valid, new_hash_if_params_were_outdated)."""
    try:
        valid = _hasher.verify(stored_hash, password)
    except (argon2_exceptions.VerifyMismatchError, argon2_exceptions.VerificationError,
            argon2_exceptions.InvalidHashError):
        return False, None
    return valid, (_hasher.hash(password) if valid and _hasher.check_needs_rehash(stored_hash) else None)


def burn_password_check(password: str) -> None:
    """Spend the same time as a real check when the account doesn't exist."""
    try:
        _hasher.verify(_DUMMY_HASH, password)
    except argon2_exceptions.VerifyMismatchError:
        pass


def new_raw_token() -> str:
    return secrets.token_urlsafe(32)




def new_numeric_code(length: int = 6) -> str:
    if length < 6 or length > 10:
        raise ValueError("verification code length must be between 6 and 10")
    return f"{secrets.randbelow(10 ** length):0{length}d}"


def keyed_digest(context: str, value: str) -> str:
    """HMAC digest for low-entropy/private values (OTP, IP/e-mail rate keys)."""
    message = f"{context}:{value}".encode()
    return hmac.new(settings.auth_pepper_secret.encode(), message, hashlib.sha256).hexdigest()


def hash_verification_code(token_id: uuid.UUID, user_id: uuid.UUID, code: str) -> str:
    # token_id provides per-code salt/domain separation, so the same 6-digit code
    # issued twice does not result in the same database digest.
    return keyed_digest("verify-email", f"{token_id}:{user_id}:{code}")

def hash_token(raw: str) -> str:
    # Tokens are 256-bit random, so a fast hash is fine (unlike passwords).
    return hashlib.sha256(raw.encode()).hexdigest()


def as_utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def create_access_token(user_id: uuid.UUID, credentials_version: int) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "cv": credentials_version,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> dict:
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    if payload.get("type") != "access":
        raise jwt.InvalidTokenError("wrong token type")
    return payload
