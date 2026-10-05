import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.deps import require_permission
from app.emailer import send_email
from app.models import UserRole, AccountStatus, Decision, MembershipRequest, Profile, utcnow
from app.schemas import Message, PendingRequestOut, RejectIn
from app.security import as_utc
from app.services import audit

router = APIRouter(prefix="/admin", tags=["admin"])
reviewer = require_permission("members.review")


@router.get("/membership-requests", response_model=list[PendingRequestOut])
def list_pending(_: Profile = Depends(reviewer), db: Session = Depends(get_db)):
    rows = db.execute(
        select(MembershipRequest, Profile).join(Profile, Profile.id == MembershipRequest.user_id)
        .where(MembershipRequest.status == Decision.pending.value)
        .order_by(MembershipRequest.submitted_at)).all()
    now, out = utcnow(), []
    for req, p in rows:
        deadline = as_utc(req.submitted_at) + timedelta(hours=settings.review_deadline_hours)
        out.append(PendingRequestOut(
            id=req.id, user_id=p.id, first_name=p.first_name, last_name=p.last_name,
            email=p.email, birth_date=p.birth_date, school=p.school, locality=p.locality,
            submitted_at=req.submitted_at, review_deadline_at=deadline, overdue=deadline < now,
            reminder_count=req.reminder_count, last_reminder_at=req.last_reminder_at))
    return out


def _load_pending(db: Session, request_id: uuid.UUID) -> tuple[MembershipRequest, Profile]:
    req = db.scalar(select(MembershipRequest).where(MembershipRequest.id == request_id)
                    .with_for_update())  # serialises two admins deciding at once
    if req is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Request not found")
    if req.status != Decision.pending.value:
        raise HTTPException(status.HTTP_409_CONFLICT, "Request already reviewed")
    return req, db.get(Profile, req.user_id)


@router.post("/membership-requests/{request_id}/approve", response_model=Message)
def approve(request_id: uuid.UUID, admin: Profile = Depends(reviewer), db: Session = Depends(get_db)):
    req, user = _load_pending(db, request_id)
    req.status, req.reviewed_by, req.reviewed_at = Decision.approved.value, admin.id, utcnow()
    user.account_status, user.joined_at = AccountStatus.active.value, utcnow()
    db.add(UserRole(user_id=user.id,role='volunteer',assigned_by=admin.id))
    audit(db, admin.id, "membership.approved", "membership_request", req.id, {"user_id": str(user.id)})
    db.commit()
    send_email(user.email, "Bine ai venit în Overthink!",
               f"Salut, {user.first_name}! Cererea ta a fost aprobată. Te poți autentifica.")
    return Message(message="Cerere aprobată.")


@router.post("/membership-requests/{request_id}/reject", response_model=Message)
def reject(request_id: uuid.UUID, body: RejectIn, admin: Profile = Depends(reviewer),
           db: Session = Depends(get_db)):
    req, user = _load_pending(db, request_id)
    req.status, req.reviewed_by, req.reviewed_at = Decision.rejected.value, admin.id, utcnow()
    req.decision_reason = body.reason
    user.account_status = AccountStatus.rejected.value
    audit(db, admin.id, "membership.rejected", "membership_request", req.id, {"user_id": str(user.id)})
    db.commit()
    send_email(user.email, "Despre cererea ta Overthink",
               f"Salut, {user.first_name}. Cererea ta nu a fost aprobată.\nMotiv: {body.reason}")
    return Message(message="Cerere respinsă.")
