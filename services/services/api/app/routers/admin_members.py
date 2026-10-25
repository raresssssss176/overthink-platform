"""Admin member management: list active members, member details with hour totals,
promote/demote coordinators and delete volunteer/coordinator accounts.

Only administrators can use these endpoints (see require_admin).
"""
import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import AccountStatus, Department, MembershipRequest, Profile, UserRole
from app.schemas import Message
from app.services import audit

router = APIRouter(prefix="/admin", tags=["admin-members"])


# ---------- schemas ----------

class MemberSummary(BaseModel):
    id: uuid.UUID
    first_name: str
    last_name: str
    email: EmailStr
    roles: list[str]
    coordinated_departments: list[str]


class DepartmentRef(BaseModel):
    id: uuid.UUID
    name: str


class HoursSummary(BaseModel):
    approved_minutes: int
    pending_minutes: int
    rejected_minutes: int


class MemberDetails(BaseModel):
    id: uuid.UUID
    first_name: str
    last_name: str
    email: EmailStr
    phone: str | None
    acronym: str | None
    gender: str | None
    birth_date: date | None
    school: str | None
    locality: str | None
    account_status: str
    roles: list[str]
    departments: list[DepartmentRef]
    membership_request_id: uuid.UUID | None
    membership_request_status: str | None
    hours: HoursSummary


class PromoteIn(BaseModel):
    department_id: uuid.UUID


# ---------- access control ----------

def require_admin(user: Profile = Depends(require_active), db: Session = Depends(get_db)) -> Profile:
    is_admin = db.scalar(select(UserRole.user_id).where(
        UserRole.user_id == user.id, UserRole.role == "admin"))
    if not is_admin:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Doar administratorii pot face această acțiune.")
    return user


# ---------- helpers ----------

def _roles(db: Session, user_id: uuid.UUID) -> list[str]:
    return list(db.scalars(select(UserRole.role).where(UserRole.user_id == user_id)).all())


def _hours(db: Session, user_id: uuid.UUID) -> HoursSummary:
    rows = db.execute(text("""
        SELECT status, COALESCE(SUM(duration_minutes), 0) AS minutes
        FROM time_entries
        WHERE user_id = :uid
        GROUP BY status
    """), {"uid": user_id}).all()
    totals = {row.status: int(row.minutes) for row in rows}
    return HoursSummary(
        approved_minutes=totals.get("approved", 0),
        pending_minutes=totals.get("pending", 0) + totals.get("needs_changes", 0),
        rejected_minutes=totals.get("rejected", 0),
    )


def _member_or_404(db: Session, user_id: uuid.UUID) -> Profile:
    user = db.get(Profile, user_id)
    if user is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Utilizatorul nu există.")
    return user


def _active_member_or_404(db: Session, user_id: uuid.UUID) -> Profile:
    user = _member_or_404(db, user_id)
    if user.account_status != AccountStatus.active.value:
        raise HTTPException(status.HTTP_409_CONFLICT, "Contul nu este activ.")
    return user


def _in_department(db: Session, user: Profile, department_id: uuid.UUID) -> bool:
    if user.primary_department_id == department_id:
        return True
    row = db.execute(text(
        "SELECT 1 FROM member_departments WHERE user_id = :uid AND department_id = :did"),
        {"uid": user.id, "did": department_id}).first()
    return row is not None


# ---------- endpoints ----------

@router.get("/members", response_model=list[MemberSummary])
def list_members(_: Profile = Depends(require_admin), db: Session = Depends(get_db)):
    users = db.scalars(
        select(Profile)
        .where(Profile.account_status == AccountStatus.active.value)
        .order_by(Profile.last_name, Profile.first_name)).all()
    out = []
    for u in users:
        coordinated = db.execute(text(
            "SELECT name FROM departments WHERE coordinator_user_id = :uid ORDER BY name"),
            {"uid": u.id}).scalars().all()
        out.append(MemberSummary(
            id=u.id, first_name=u.first_name, last_name=u.last_name, email=u.email,
            roles=_roles(db, u.id), coordinated_departments=list(coordinated)))
    return out


@router.get("/members/{user_id}/details", response_model=MemberDetails)
def member_details(user_id: uuid.UUID, _: Profile = Depends(require_admin),
                   db: Session = Depends(get_db)):
    user = _member_or_404(db, user_id)

    if user.account_status == AccountStatus.active.value:
        dept_rows = db.execute(text("""
            SELECT d.id, d.name FROM departments d
            WHERE d.id IN (SELECT department_id FROM member_departments WHERE user_id = :uid)
               OR d.id = :primary
            ORDER BY d.name"""),
            {"uid": user.id, "primary": user.primary_department_id}).all()
    else:
        # Pending users: show what they asked for at registration.
        dept_rows = db.execute(
            select(Department.id, Department.name)
            .where(Department.id.in_(user.requested_department_ids or []))
            .order_by(Department.name)).all()

    req = db.scalar(select(MembershipRequest)
                    .where(MembershipRequest.user_id == user.id)
                    .order_by(MembershipRequest.submitted_at.desc()))

    return MemberDetails(
        id=user.id, first_name=user.first_name, last_name=user.last_name, email=user.email,
        phone=user.phone, acronym=user.acronym, gender=user.gender,
        birth_date=user.birth_date, school=user.school, locality=user.locality,
        account_status=user.account_status, roles=_roles(db, user.id),
        departments=[DepartmentRef(id=d.id, name=d.name) for d in dept_rows],
        membership_request_id=req.id if req else None,
        membership_request_status=req.status if req else None,
        hours=_hours(db, user.id),
    )


@router.post("/members/{user_id}/promote", response_model=Message)
def promote(user_id: uuid.UUID, body: PromoteIn, admin: Profile = Depends(require_admin),
            db: Session = Depends(get_db)):
    user = _active_member_or_404(db, user_id)
    roles = _roles(db, user.id)
    is_admin_target = "admin" in roles
    if "volunteer" not in roles and not is_admin_target:
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Doar voluntarii sau administratorii pot fi promovați la coordonator.")

    dept = db.get(Department, body.department_id)
    if dept is None or not dept.is_active:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Departamentul nu există.")
    if not is_admin_target and not _in_department(db, user, dept.id):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            "Voluntarul nu face parte din departamentul ales.")

    current = db.execute(text(
        "SELECT coordinator_user_id FROM departments WHERE id = :did FOR UPDATE"),
        {"did": dept.id}).scalar()
    if current is not None and current != user.id:
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Departamentul are deja un coordonator.")

    db.execute(text("""
        INSERT INTO user_roles (user_id, role, assigned_by)
        VALUES (:uid, 'coordinator', :by)
        ON CONFLICT DO NOTHING"""), {"uid": user.id, "by": admin.id})
    db.execute(text("UPDATE departments SET coordinator_user_id = :uid WHERE id = :did"),
               {"uid": user.id, "did": dept.id})
    audit(db, admin.id, "member.promoted", "profile", user.id,
          {"department_id": str(dept.id)})
    db.commit()
    return Message(message="Voluntarul a fost promovat la coordonator.")


@router.post("/members/{user_id}/demote", response_model=Message)
def demote(user_id: uuid.UUID, admin: Profile = Depends(require_admin),
           db: Session = Depends(get_db)):
    user = _active_member_or_404(db, user_id)
    if "coordinator" not in _roles(db, user.id):
        raise HTTPException(status.HTTP_409_CONFLICT, "Utilizatorul nu este coordonator.")

    # Permissions this coordinator granted are NOT revoked automatically.
    db.execute(text("DELETE FROM user_roles WHERE user_id = :uid AND role = 'coordinator'"),
               {"uid": user.id})
    db.execute(text("UPDATE departments SET coordinator_user_id = NULL WHERE coordinator_user_id = :uid"),
               {"uid": user.id})
    audit(db, admin.id, "member.demoted", "profile", user.id)
    db.commit()
    return Message(message="Coordonatorul a fost demotat la voluntar.")


@router.delete("/members/{user_id}", response_model=Message)
def delete_member(user_id: uuid.UUID, admin: Profile = Depends(require_admin),
                  db: Session = Depends(get_db)):
    if user_id == admin.id:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Nu îți poți șterge propriul cont.")
    user = _member_or_404(db, user_id)
    if "admin" in _roles(db, user.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Conturile de administrator nu pot fi șterse de aici.")

    uid, email = user.id, user.email

    # Records that must be kept block deletion instead of being erased.
    blockers = {
        "Contul are ore înregistrate și nu poate fi șters.":
            "SELECT 1 FROM time_entries WHERE user_id = :uid OR reviewed_by = :uid LIMIT 1",
        "Contul are permisiuni acordate sau a acordat permisiuni. Istoricul trebuie păstrat.":
            "SELECT 1 FROM permission_grants WHERE user_id = :uid OR granted_by = :uid LIMIT 1",
        "Contul a revizuit cereri de aderare și nu poate fi șters.":
            "SELECT 1 FROM membership_requests WHERE reviewed_by = :uid LIMIT 1",
    }
    for message, sql in blockers.items():
        if db.execute(text(sql), {"uid": uid}).first() is not None:
            raise HTTPException(status.HTTP_409_CONFLICT, message)

    try:
        db.execute(text("DELETE FROM notification_outbox WHERE recipient_user_id = :uid OR recipient_email = :email"),
                   {"uid": uid, "email": email})
        db.execute(text("DELETE FROM user_roles WHERE user_id = :uid"), {"uid": uid})
        db.execute(text("DELETE FROM member_departments WHERE user_id = :uid"), {"uid": uid})
        db.execute(text("DELETE FROM team_members WHERE user_id = :uid"), {"uid": uid})
        db.execute(text("DELETE FROM membership_requests WHERE user_id = :uid"), {"uid": uid})
        db.execute(text("UPDATE departments SET coordinator_user_id = NULL WHERE coordinator_user_id = :uid"),
                   {"uid": uid})
        # Sessions, tokens, credentials and settings are removed by ON DELETE CASCADE.
        audit(db, admin.id, "member.deleted", "profile", uid)
        db.execute(text("DELETE FROM profiles WHERE id = :uid"), {"uid": uid})
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Contul are date asociate și nu poate fi șters.")
    return Message(message="Contul a fost șters.")