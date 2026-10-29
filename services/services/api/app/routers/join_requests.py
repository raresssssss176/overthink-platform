"""Department join requests. A coordinator sees all active volunteers and asks for one of them
to join a department they coordinate. An administrator approves or rejects the request."""
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import Profile
from app.routers.hours import _coordinated_department_ids, _has_role
from app.schemas import Message
from app.services import audit

router = APIRouter(prefix="/department-requests", tags=["department-requests"])


# ---------- schemas ----------

class DeptRef(BaseModel):
    id: uuid.UUID
    name: str


class VolunteerRow(BaseModel):
    id: uuid.UUID
    first_name: str
    last_name: str
    email: EmailStr
    departments: list[str]
    in_my_departments: bool
    pending_department_ids: list[uuid.UUID]


class Overview(BaseModel):
    my_departments: list[DeptRef]
    volunteers: list[VolunteerRow]


class RequestIn(BaseModel):
    user_id: uuid.UUID
    department_id: uuid.UUID


class JoinRequestOut(BaseModel):
    id: uuid.UUID
    user_name: str
    department_name: str
    requested_by_name: str
    status: str
    created_at: datetime
    decision_reason: str | None


class RejectIn(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


# ---------- helpers ----------

def _require_coordinator(db: Session, user: Profile) -> set[uuid.UUID]:
    if not _has_role(db, user.id, "coordinator"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Doar coordonatorii pot face această acțiune.")
    return _coordinated_department_ids(db, user.id)


def _member_department_ids(db: Session, user_id: uuid.UUID) -> set[uuid.UUID]:
    ids = set(db.execute(text(
        "SELECT department_id FROM member_departments WHERE user_id = :uid"),
        {"uid": user_id}).scalars().all())
    primary = db.execute(text("SELECT primary_department_id FROM profiles WHERE id = :uid"),
                         {"uid": user_id}).scalar()
    if primary is not None:
        ids.add(primary)
    return ids


# ---------- endpoints ----------

@router.get("/overview", response_model=Overview)
def overview(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    """All active volunteers, for coordinators (and admins, who see the same list)."""
    if not (_has_role(db, user.id, "coordinator") or _has_role(db, user.id, "admin")):
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Doar coordonatorii și administratorii pot vedea voluntarii.")

    mine = _coordinated_department_ids(db, user.id)
    my_depts = []
    if mine:
        my_depts = db.execute(text(
            "SELECT id, name FROM departments WHERE id = ANY(:ids) ORDER BY name"),
            {"ids": list(mine)}).all()

    people = db.execute(text("""
        SELECT id, first_name, last_name, email FROM profiles
        WHERE account_status = 'active'
        ORDER BY last_name, first_name""")).all()

    dept_rows = db.execute(text("""
        SELECT x.user_id, d.id AS dept_id, d.name
        FROM (
            SELECT user_id, department_id FROM member_departments
            UNION
            SELECT id AS user_id, primary_department_id AS department_id
            FROM profiles WHERE primary_department_id IS NOT NULL
        ) x
        JOIN departments d ON d.id = x.department_id""")).all()
    depts_by_user: dict[uuid.UUID, list[tuple[uuid.UUID, str]]] = {}
    for r in dept_rows:
        depts_by_user.setdefault(r.user_id, []).append((r.dept_id, r.name))

    pending_rows = db.execute(text("""
        SELECT user_id, department_id FROM department_join_requests
        WHERE status = 'pending' AND department_id = ANY(:dids)"""),
        {"dids": list(mine) or [uuid.UUID(int=0)]}).all()
    pending_by_user: dict[uuid.UUID, list[uuid.UUID]] = {}
    for r in pending_rows:
        pending_by_user.setdefault(r.user_id, []).append(r.department_id)

    volunteers = []
    for p in people:
        entries = depts_by_user.get(p.id, [])
        volunteers.append(VolunteerRow(
            id=p.id, first_name=p.first_name, last_name=p.last_name, email=p.email,
            departments=sorted({name for _, name in entries}),
            in_my_departments=any(dept_id in mine for dept_id, _ in entries),
            pending_department_ids=pending_by_user.get(p.id, []),
        ))
    return Overview(
        my_departments=[DeptRef(id=d.id, name=d.name) for d in my_depts],
        volunteers=volunteers)


@router.post("", response_model=Message, status_code=status.HTTP_201_CREATED)
def request_join(body: RequestIn, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    mine = _require_coordinator(db, user)
    if body.department_id not in mine:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Poți cere doar pentru departamentele tale.")

    target = db.execute(text(
        "SELECT id, account_status FROM profiles WHERE id = :uid"), {"uid": body.user_id}).first()
    if target is None or target.account_status != "active":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Voluntarul nu există sau nu este activ.")
    if body.department_id in _member_department_ids(db, body.user_id):
        raise HTTPException(status.HTTP_409_CONFLICT, "Voluntarul face deja parte din departament.")

    pending = db.execute(text("""
        SELECT 1 FROM department_join_requests
        WHERE user_id = :uid AND department_id = :did AND status = 'pending'"""),
        {"uid": body.user_id, "did": body.department_id}).first()
    if pending is not None:
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Există deja o cerere în așteptare pentru acest voluntar.")

    req_id = db.execute(text("""
        INSERT INTO department_join_requests (user_id, department_id, requested_by)
        VALUES (:uid, :did, :by) RETURNING id"""),
        {"uid": body.user_id, "did": body.department_id, "by": user.id}).scalar()
    audit(db, user.id, "department.join_requested", "department_join_request", req_id,
          {"user_id": str(body.user_id), "department_id": str(body.department_id)})
    db.commit()
    return Message(message="Cererea a fost trimisă administratorului.")


_REQUEST_SELECT = """
    SELECT r.id, r.status, r.created_at, r.decision_reason,
           u.first_name || ' ' || u.last_name AS user_name,
           d.name AS department_name,
           b.first_name || ' ' || b.last_name AS requested_by_name
    FROM department_join_requests r
    JOIN profiles u ON u.id = r.user_id
    JOIN departments d ON d.id = r.department_id
    JOIN profiles b ON b.id = r.requested_by
"""


@router.get("", response_model=list[JoinRequestOut])
def list_requests(status_filter: str = "pending", user: Profile = Depends(require_active),
                  db: Session = Depends(get_db)):
    if status_filter not in ("pending", "approved", "rejected"):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Stare invalidă.")
    if _has_role(db, user.id, "admin"):
        rows = db.execute(text(_REQUEST_SELECT + """
            WHERE r.status = :s ORDER BY r.created_at"""), {"s": status_filter}).all()
    elif _has_role(db, user.id, "coordinator"):
        rows = db.execute(text(_REQUEST_SELECT + """
            WHERE r.requested_by = :uid AND r.status = :s ORDER BY r.created_at"""),
            {"uid": user.id, "s": status_filter}).all()
    else:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Nu ai acces la aceste cereri.")
    return [JoinRequestOut(
        id=r.id, user_name=r.user_name, department_name=r.department_name,
        requested_by_name=r.requested_by_name, status=r.status, created_at=r.created_at,
        decision_reason=r.decision_reason) for r in rows]


def _load_pending_for_admin(db: Session, request_id: uuid.UUID, admin: Profile):
    if not _has_role(db, admin.id, "admin"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Doar administratorii pot decide asupra cererilor.")
    req = db.execute(text(
        "SELECT id, user_id, department_id, status FROM department_join_requests "
        "WHERE id = :id FOR UPDATE"), {"id": request_id}).first()
    if req is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Cererea nu există.")
    if req.status != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Cererea a fost deja decisă.")
    return req


@router.post("/{request_id}/approve", response_model=Message)
def approve(request_id: uuid.UUID, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    req = _load_pending_for_admin(db, request_id, user)
    db.execute(text("""
        INSERT INTO member_departments (user_id, department_id, assigned_by)
        VALUES (:uid, :did, :by)
        ON CONFLICT DO NOTHING"""), {"uid": req.user_id, "did": req.department_id, "by": user.id})
    db.execute(text("""
        UPDATE department_join_requests
        SET status = 'approved', reviewed_by = :by, reviewed_at = now()
        WHERE id = :id"""), {"by": user.id, "id": request_id})
    audit(db, user.id, "department.join_approved", "department_join_request", request_id,
          {"user_id": str(req.user_id), "department_id": str(req.department_id)})
    db.commit()
    return Message(message="Voluntarul a fost adăugat în departament.")


@router.post("/{request_id}/reject", response_model=Message)
def reject(request_id: uuid.UUID, body: RejectIn, user: Profile = Depends(require_active),
           db: Session = Depends(get_db)):
    req = _load_pending_for_admin(db, request_id, user)
    reason = (body.reason or "").strip() or "Respinsă de administrator"
    db.execute(text("""
        UPDATE department_join_requests
        SET status = 'rejected', reviewed_by = :by, reviewed_at = now(), decision_reason = :reason
        WHERE id = :id"""), {"by": user.id, "id": request_id, "reason": reason})
    audit(db, user.id, "department.join_rejected", "department_join_request", request_id,
          {"user_id": str(req.user_id), "department_id": str(req.department_id)})
    db.commit()
    return Message(message="Cererea a fost respinsă.")