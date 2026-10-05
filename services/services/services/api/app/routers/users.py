from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.deps import get_current_user
from app.models import Decision, MembershipRequest, Profile, utcnow
from app.schemas import MembershipStatusOut, Message, ProfileOut
from app.security import as_utc
from app.services import notify_reviewers

router = APIRouter(tags=["users"])


@router.get("/users/me", response_model=ProfileOut)
def me(user: Profile = Depends(get_current_user)):
    return user


def _latest_request(db: Session, user: Profile) -> MembershipRequest:
    req = db.scalar(select(MembershipRequest).where(MembershipRequest.user_id == user.id)
                    .order_by(MembershipRequest.submitted_at.desc()))
    if req is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "No membership request")
    return req


def _next_reminder_at(req: MembershipRequest):
    base = as_utc(req.last_reminder_at or req.submitted_at)
    return base + timedelta(hours=settings.reminder_cooldown_hours)


@router.get("/membership/status", response_model=MembershipStatusOut)
def membership_status(user: Profile = Depends(get_current_user), db: Session = Depends(get_db)):
    req = _latest_request(db, user)
    pending = req.status == Decision.pending.value
    nxt = _next_reminder_at(req)
    can = pending and req.reminder_count < settings.max_reminders and nxt <= utcnow()
    return MembershipStatusOut(
        decision=req.status, submitted_at=req.submitted_at,
        review_deadline_at=as_utc(req.submitted_at) + timedelta(hours=settings.review_deadline_hours),
        rejection_reason=req.decision_reason, can_remind=can,
        next_reminder_at=nxt if pending else None)


@router.post("/membership/remind", response_model=Message)
def remind(user: Profile = Depends(get_current_user), db: Session = Depends(get_db)):
    """A reminder to the reviewers, not a new application."""
    req = db.scalar(select(MembershipRequest).where(MembershipRequest.user_id == user.id,
                    MembershipRequest.status == Decision.pending.value))
    if req is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "No pending request")
    if req.reminder_count >= settings.max_reminders:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Reminder limit reached")
    if _next_reminder_at(req) > utcnow():
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Reminder not available yet")
    req.last_reminder_at, req.reminder_count = utcnow(), req.reminder_count + 1
    db.commit()
    notify_reviewers(db, "Reamintire: cerere de aderare în așteptare",
                     f"{user.first_name} {user.last_name} așteaptă încă o decizie.")
    return Message(message="Administratorii au fost notificați.")
