"""Team endpoints for coordinators and administrators.

A coordinator sees the active members of the departments they coordinate, opens their
details and grants permissions to them. An administrator can do the same for any active member.
"""
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import AccountStatus, PermissionGrant, Profile, utcnow
from app.routers import admin_members as am
from app.services import audit

router = APIRouter(prefix="/team", tags=["team"])


# ---------- schemas ----------

class GrantIn(BaseModel):
    permission: str = Field(min_length=3, max_length=60)
    # Coordinators: one of their departments. Optional when the member belongs to only one of them.
    department_id: uuid.UUID | None = None
    hours: int = Field(default=48, ge=1, le=720)


class GrantOut(BaseModel):
    id: uuid.UUID
    permission: str
    scope_type: str
    department_id: uuid.UUID | None
    granted_by: uuid.UUID
    created_at: datetime
    expires_at: datetime


# ---------- access control ----------

def require_team_lead(user: Profile = Depends(require_active), db: Session = Depends(get_db)) -> Profile:
    roles = am._roles(db, user.id)
    if "admin" not in roles and "coordinator" not in roles:
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Doar coordonatorii și administratorii pot face această acțiune.")
    return user


# ---------- helpers ----------

def _is_admin(db: Session, user_id: uuid.UUID) -> bool:
    return "admin" in am._roles(db, user_id)


def _coordinated_ids(db: Session, user_id: uuid.UUID) -> list[uuid.UUID]:
    return list(db.execute(text(
        "SELECT id FROM departments WHERE coordinator_user_id = :uid"),
        {"uid": user_id}).scalars().all())


def _team_ids(db: Session, dept_ids: list[uuid.UUID]) -> list[uuid.UUID]:
    if not dept_ids:
        return []
    return list(db.execute(text("""
        SELECT p.id FROM profiles p
        WHERE p.account_status = 'active'
          AND (p.primary_department_id = ANY(:dids)
               OR p.id IN (SELECT user_id FROM member_departments WHERE department_id = ANY(:dids)))
        ORDER BY p.last_name, p.first_name"""),
        {"dids": dept_ids}).scalars().all())


def _target_department_ids(db: Session, user: Profile) -> list[uuid.UUID]:
    ids = list(db.execute(text(
        "SELECT department_id FROM member_departments WHERE user_id = :uid"),
        {"uid": user.id}).scalars().all())
    if user.primary_department_id is not None:
        ids.append(user.primary_department_id)
    return ids


def _can_manage(db: Session, caller: Profile, target_id: uuid.UUID) -> bool:
    if _is_admin(db, caller.id):
        return True
    return target_id in _team_ids(db, _coordinated_ids(db, caller.id))


def _grant_out(grant: PermissionGrant) -> GrantOut:
    return GrantOut(
        id=grant.id, permission=grant.permission, scope_type=grant.scope_type,
        department_id=grant.department_id, granted_by=grant.granted_by,
        created_at=grant.created_at, expires_at=grant.expires_at)


# ---------- endpoints ----------

@router.get("/members", response_model=list[am.MemberSummary])
def my_team(caller: Profile = Depends(require_team_lead), db: Session = Depends(get_db)):
    ids = _team_ids(db, _coordinated_ids(db, caller.id))
    out = []
    for uid in ids:
        u = db.get(Profile, uid)
        out.append(am.MemberSummary(
            id=u.id, first_name=u.first_name, last_name=u.last_name, email=u.email,
            roles=am._roles(db, u.id), coordinated_departments=[]))
    return out


@router.get("/members/{user_id}/details", response_model=am.MemberDetails)
def member_details(user_id: uuid.UUID, caller: Profile = Depends(require_team_lead),
                   db: Session = Depends(get_db)):
    if not _can_manage(db, caller, user_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Acest voluntar nu face parte din echipa ta.")
    # Same data as the admin page: personal data, departments, requests and hour totals.
    return am.member_details(user_id, caller, db)


@router.get("/members/{user_id}/grants", response_model=list[GrantOut])
def member_grants(user_id: uuid.UUID, caller: Profile = Depends(require_team_lead),
                  db: Session = Depends(get_db)):
    if not _can_manage(db, caller, user_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Acest voluntar nu face parte din echipa ta.")
    grants = db.scalars(select(PermissionGrant).where(
        PermissionGrant.user_id == user_id,
        PermissionGrant.revoked_at.is_(None),
        PermissionGrant.expires_at > utcnow(),
    ).order_by(PermissionGrant.created_at.desc())).all()
    return [_grant_out(g) for g in grants]


@router.post("/members/{user_id}/grants", response_model=GrantOut, status_code=status.HTTP_201_CREATED)
def create_grant(user_id: uuid.UUID, body: GrantIn, caller: Profile = Depends(require_team_lead),
                 db: Session = Depends(get_db)):
    if not _can_manage(db, caller, user_id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Acest voluntar nu face parte din echipa ta.")

    target = am._member_or_404(db, user_id)
    if target.account_status != AccountStatus.active.value:
        raise HTTPException(status.HTTP_409_CONFLICT, "Contul nu este activ.")

    exists = db.execute(text(
        "SELECT 1 FROM permission_types WHERE code = :p AND is_active"), {"p": body.permission}).first()
    if exists is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Permisiunea nu există.")

    if _is_admin(db, caller.id):
        granter_role, scope, dept_id = "admin", "club", None
    else:
        granter_role, scope = "coordinator", "department"
        my_depts = set(_coordinated_ids(db, caller.id))
        target_depts = my_depts.intersection(_target_department_ids(db, target))
        if not target_depts:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                                "Voluntarul nu face parte din departamentele tale.")
        if body.department_id is not None:
            if body.department_id not in target_depts:
                raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                                    "Voluntarul nu face parte din departamentul ales.")
            dept_id = body.department_id
        else:
            dept_id = sorted(target_depts)[0]

    allowed = db.execute(text(
        "SELECT 1 FROM delegation_rules WHERE granter_role = :r AND permission = :p"),
        {"r": granter_role, "p": body.permission}).first()
    if allowed is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Nu poți acorda această permisiune.")

    grant = PermissionGrant(
        user_id=target.id, permission=body.permission, scope_type=scope,
        department_id=dept_id, granted_by=caller.id,
        expires_at=utcnow() + timedelta(hours=body.hours))
    db.add(grant)
    db.flush()
    audit(db, caller.id, "permission.granted", "permission_grant", grant.id,
          {"user_id": str(target.id), "permission": body.permission})
    db.commit()
    db.refresh(grant)
    return _grant_out(grant)


@router.delete("/grants/{grant_id}", response_model=am.Message)
def revoke_grant(grant_id: uuid.UUID, caller: Profile = Depends(require_team_lead),
                 db: Session = Depends(get_db)):
    grant = db.get(PermissionGrant, grant_id)
    if grant is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Permisiunea nu există.")
    if grant.granted_by != caller.id and not _is_admin(db, caller.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Poți revoca doar permisiunile pe care le-ai acordat.")
    if grant.revoked_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Permisiunea a fost deja revocată.")
    grant.revoked_at = utcnow()
    audit(db, caller.id, "permission.revoked", "permission_grant", grant.id,
          {"user_id": str(grant.user_id), "permission": grant.permission})
    db.commit()
    return am.Message(message="Permisiunea a fost revocată.")