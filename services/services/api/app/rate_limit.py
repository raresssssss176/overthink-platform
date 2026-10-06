"""Small PostgreSQL-backed rate limiter for authentication endpoints.

It deliberately stores only keyed digests of e-mail/IP values, never the raw
IP address. This is enough for the current single-service Overthink backend and
can later be replaced by Redis without changing the API contract.
"""
from dataclasses import dataclass
from datetime import timedelta

from fastapi import HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import AuthRateLimitEvent, utcnow
from app.security import keyed_digest


@dataclass(frozen=True)
class SendLimitDecision:
    allowed: bool


def client_ip(request: Request) -> str:
    # Do not parse X-Forwarded-For manually. In production configure Uvicorn's
    # trusted proxy settings so request.client is rewritten only by a trusted proxy.
    if request.client is None or not request.client.host:
        return "unknown"
    return request.client.host


def _digests(email: str, ip: str) -> tuple[str, str]:
    email_digest = keyed_digest("rate-email", email.strip().lower())
    ip_digest = keyed_digest("rate-ip", ip)
    return email_digest, ip_digest


def _count(db: Session, *, action: str, since, email_digest: str | None = None,
           ip_digest: str | None = None) -> int:
    q = select(func.count(AuthRateLimitEvent.id)).where(
        AuthRateLimitEvent.action == action,
        AuthRateLimitEvent.created_at >= since,
    )
    if email_digest is not None:
        q = q.where(AuthRateLimitEvent.email_digest == email_digest)
    if ip_digest is not None:
        q = q.where(AuthRateLimitEvent.ip_digest == ip_digest)
    return int(db.scalar(q) or 0)


def _last_email_event(db: Session, *, action: str, email_digest: str):
    return db.scalar(
        select(func.max(AuthRateLimitEvent.created_at)).where(
            AuthRateLimitEvent.action == action,
            AuthRateLimitEvent.email_digest == email_digest,
        )
    )


def register_verification_send(db: Session, email: str, ip: str) -> SendLimitDecision:
    """Record every send request.

    IP exhaustion is a hard 429 because it is independent of account existence.
    E-mail cooldown/hour limits are silent so the response cannot reveal whether
    the address exists in the database.
    """
    now = utcnow()
    email_digest, ip_digest = _digests(email, ip)
    since = now - timedelta(minutes=settings.verification_send_window_minutes)

    ip_count = _count(db, action="verification_send", since=since, ip_digest=ip_digest)
    email_count = _count(db, action="verification_send", since=since, email_digest=email_digest)
    last_email = _last_email_event(db, action="verification_send", email_digest=email_digest)

    db.add(AuthRateLimitEvent(
        action="verification_send",
        email_digest=email_digest,
        ip_digest=ip_digest,
    ))
    db.commit()  # Keep abuse accounting even if the following request is rejected.

    if ip_count >= settings.verification_ip_send_limit:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Try again later.",
            headers={"Retry-After": str(settings.verification_send_window_minutes * 60)},
        )

    cooldown_ok = (
        last_email is None
        or last_email <= now - timedelta(seconds=settings.verification_resend_seconds)
    )
    allowed = email_count < settings.verification_email_send_limit and cooldown_ok
    return SendLimitDecision(allowed=allowed)


def enforce_verification_attempt_limit(db: Session, email: str, ip: str) -> None:
    now = utcnow()
    email_digest, ip_digest = _digests(email, ip)
    since = now - timedelta(minutes=settings.verification_attempt_window_minutes)

    ip_count = _count(db, action="verification_attempt", since=since, ip_digest=ip_digest)
    email_count = _count(db, action="verification_attempt", since=since, email_digest=email_digest)

    db.add(AuthRateLimitEvent(
        action="verification_attempt",
        email_digest=email_digest,
        ip_digest=ip_digest,
    ))
    db.commit()

    if (
        ip_count >= settings.verification_ip_attempt_limit
        or email_count >= settings.verification_email_attempt_limit
    ):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many verification attempts. Try again later.",
            headers={"Retry-After": str(settings.verification_attempt_window_minutes * 60)},
        )
