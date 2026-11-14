from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.deps import get_current_user
from app.models import Decision, MembershipRequest, Profile, UserRole, utcnow
from app.schemas import MembershipStatusOut, Message, ProfileOut
from app.security import as_utc
from app.services import notify_reviewers

router = APIRouter(tags=["users"])


def _effective_permissions(db: Session, user_id, roles: list[str]) -> list[str]:
    if "admin" in roles:
        rows = db.execute(text("SELECT code FROM permission_types WHERE is_active")).scalars().all()
        return sorted(set(rows))

    perms: set[str] = set()
    if roles:
        role_rows = db.execute(text("""
            SELECT rp.permission
            FROM role_permissions rp
            JOIN permission_types pt ON pt.code = rp.permission
            WHERE pt.is_active AND rp.role = ANY(:roles)"""),
            {"roles": roles}).scalars().all()
        perms.update(role_rows)

    grant_rows = db.execute(text("""
        SELECT pg.permission
        FROM permission_grants pg
        JOIN permission_types pt ON pt.code = pg.permission
        WHERE pt.is_active
          AND pg.user_id = :uid
          AND pg.revoked_at IS NULL
          AND pg.expires_at > now()"""),
        {"uid": user_id}).scalars().all()
    perms.update(grant_rows)
    return sorted(perms)


@router.get("/users/me", response_model=ProfileOut)
def me(user: Profile = Depends(get_current_user), db: Session = Depends(get_db)):
    roles = list(db.scalars(select(UserRole.role).where(UserRole.user_id == user.id)).all())
    permissions = _effective_permissions(db, user.id, roles)
    return ProfileOut.model_validate(user).model_copy(update={
        "roles": roles,
        "permissions": permissions,
    })