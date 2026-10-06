"""One-time tokens, e-mail verification codes and refresh sessions."""
import hmac
import uuid
from datetime import timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.config import settings
from app.models import AuthSession, AuthToken, TokenPurpose, utcnow
from app.security import (
    as_utc,
    hash_token,
    hash_verification_code,
    new_numeric_code,
    new_raw_token,
)


def issue(db: Session, user_id: uuid.UUID, purpose: str, ttl: timedelta) -> str:
    raw = new_raw_token()
    db.add(AuthToken(
        user_id=user_id,
        purpose=purpose,
        token_digest=hash_token(raw),
        expires_at=utcnow() + ttl,
    ))
    return raw


def consume(db: Session, raw: str, purpose: str) -> AuthToken | None:
    row = db.scalar(
        select(AuthToken).where(
            AuthToken.token_digest == hash_token(raw),
            AuthToken.purpose == purpose,
            AuthToken.invalidated_at.is_(None),
        ).with_for_update()
    )
    if row is None or row.used_at is not None or as_utc(row.expires_at) <= utcnow():
        return None
    row.used_at = utcnow()
    return row


def invalidate_active(db: Session, user_id: uuid.UUID, purpose: str) -> None:
    db.execute(
        update(AuthToken)
        .where(
            AuthToken.user_id == user_id,
            AuthToken.purpose == purpose,
            AuthToken.used_at.is_(None),
            AuthToken.invalidated_at.is_(None),
        )
        .values(invalidated_at=utcnow())
    )


def issue_verification_code(db: Session, user_id: uuid.UUID) -> tuple[str, AuthToken]:
    invalidate_active(db, user_id, TokenPurpose.verify_email.value)
    code = new_numeric_code(6)
    row = AuthToken(
        id=uuid.uuid4(),
        user_id=user_id,
        purpose=TokenPurpose.verify_email.value,
        token_digest="0" * 64,  # replaced immediately below before flush
        expires_at=utcnow() + timedelta(minutes=settings.verification_code_minutes),
    )
    row.token_digest = hash_verification_code(row.id, user_id, code)
    db.add(row)
    db.flush()
    return code, row


def consume_verification_code(db: Session, user_id: uuid.UUID, code: str) -> AuthToken | None:
    row = db.scalar(
        select(AuthToken)
        .where(
            AuthToken.user_id == user_id,
            AuthToken.purpose == TokenPurpose.verify_email.value,
            AuthToken.used_at.is_(None),
            AuthToken.invalidated_at.is_(None),
        )
        .order_by(AuthToken.created_at.desc())
        .with_for_update()
    )
    if row is None:
        return None

    now = utcnow()
    if as_utc(row.expires_at) <= now:
        row.invalidated_at = now
        return None
    if row.attempt_count >= settings.verification_code_max_attempts:
        row.invalidated_at = now
        return None

    expected = hash_verification_code(row.id, user_id, code)
    if not hmac.compare_digest(row.token_digest, expected):
        row.attempt_count += 1
        if row.attempt_count >= settings.verification_code_max_attempts:
            row.invalidated_at = now
        return None

    row.used_at = now
    return row


def issue_refresh(db: Session, user_id: uuid.UUID, ttl: timedelta) -> tuple[str, AuthSession]:
    raw = new_raw_token()
    session = AuthSession(
        user_id=user_id,
        refresh_token_digest=hash_token(raw),
        expires_at=utcnow() + ttl,
    )
    db.add(session)
    db.flush()
    return raw, session


def lookup_refresh(db: Session, raw: str, lock: bool = False) -> AuthSession | None:
    q = select(AuthSession).where(AuthSession.refresh_token_digest == hash_token(raw))
    return db.scalar(q.with_for_update() if lock else q)


def revoke_all_refresh(db: Session, user_id: uuid.UUID) -> None:
    db.execute(
        update(AuthSession)
        .where(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )
