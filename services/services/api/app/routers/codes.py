"""Shared hour codes: a coordinator or admin creates one code for an event; several volunteers
can redeem it while it is valid (15 minutes). Only a SHA-256 digest of the code is stored."""
import hashlib
import secrets
import uuid
from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import Profile, utcnow
from app.routers.hours import (
    _allowed_department_ids, _coordinated_department_ids, _event_or_404,
    _general_department_id, _has_role, _task_id_for_event,
)
from app.schemas import Message
from app.services import audit

router = APIRouter(prefix="/codes", tags=["codes"])

CODE_TTL = timedelta(minutes=15)


# ---------- schemas ----------

class DepartmentOpt(BaseModel):
    id: uuid.UUID
    name: str


class CodeIn(BaseModel):
    department_id: uuid.UUID
    event_id: uuid.UUID
    task_id: uuid.UUID | None = None
    new_task_name: str | None = Field(default=None, min_length=2, max_length=120)
    work_date: date
    hours: int = Field(ge=1, le=12)
    description: str | None = Field(default=None, max_length=500)


class CodeCreated(BaseModel):
    id: uuid.UUID
    code: str  # shown once, never stored in clear
    expires_at: datetime
    department_name: str
    event_title: str
    hours: int
    work_date: date


class CodeListItem(BaseModel):
    id: uuid.UUID
    department_name: str
    event_title: str
    task_name: str | None
    hours: int
    work_date: date
    created_at: datetime
    expires_at: datetime
    redemptions: int
    state: str  # active | expired | cancelled


class RedeemIn(BaseModel):
    code: str = Field(min_length=10, max_length=100)


# ---------- helpers ----------

def _digest(code: str) -> str:
    return hashlib.sha256(code.strip().encode("utf-8")).hexdigest()


def _require_creator(db: Session, user: Profile) -> None:
    if not (_has_role(db, user.id, "admin") or _has_role(db, user.id, "coordinator")):
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Doar coordonatorii și administratorii pot genera coduri.")


def _creator_department_ids(db: Session, user: Profile) -> set[uuid.UUID]:
    """Admins: every active department. Coordinators: the departments they coordinate, plus the general meeting."""
    if _has_role(db, user.id, "admin"):
        return _allowed_department_ids(db, user)
    ids = _coordinated_department_ids(db, user.id)
    general = _general_department_id(db)
    if general is not None:
        ids.add(general)
    return ids


# ---------- endpoints ----------

@router.get("/departments", response_model=list[DepartmentOpt])
def creator_departments(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    _require_creator(db, user)
    ids = list(_creator_department_ids(db, user))
    if not ids:
        return []
    rows = db.execute(text("SELECT id, name FROM departments WHERE id = ANY(:ids) ORDER BY name"),
                      {"ids": ids}).all()
    return [DepartmentOpt(id=r.id, name=r.name) for r in rows]


@router.post("", response_model=CodeCreated, status_code=status.HTTP_201_CREATED)
def create_code(body: CodeIn, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    _require_creator(db, user)
    if body.department_id not in _creator_department_ids(db, user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Nu poți genera coduri pentru acest departament.")
    if body.work_date > date.today():
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Data nu poate fi în viitor.")

    event = _event_or_404(db, body.event_id)
    task_id = body.task_id
    if body.new_task_name:
        task_id = _task_id_for_event(db, event.id, body.new_task_name, user.id)
    if task_id is not None:
        belongs = db.execute(text(
            "SELECT 1 FROM activity_tasks WHERE id = :tid AND activity_id = :eid"),
            {"tid": task_id, "eid": event.id}).first()
        if belongs is None:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                                "Task-ul nu aparține evenimentului ales.")

    # 128 bits of randomness. Only the digest goes into the database.
    code = secrets.token_urlsafe(16)
    expires_at = utcnow() + CODE_TTL
    row = db.execute(text("""
        INSERT INTO shared_hour_codes (code_digest, activity_id, task_id, department_id,
                                       work_date, minutes, description, created_by, expires_at)
        VALUES (:digest, :eid, :tid, :did, :d, :minutes, :desc, :uid, :exp)
        RETURNING id"""),
        {"digest": _digest(code), "eid": event.id, "tid": task_id, "did": body.department_id,
         "d": body.work_date, "minutes": body.hours * 60,
         "desc": (body.description or "").strip(), "uid": user.id, "exp": expires_at}).scalar()
    dept_name = db.execute(text("SELECT name FROM departments WHERE id = :d"),
                           {"d": body.department_id}).scalar()
    audit(db, user.id, "hours.code_created", "shared_hour_code", row,
          {"minutes": body.hours * 60, "department_id": str(body.department_id)})
    db.commit()
    return CodeCreated(id=row, code=code, expires_at=expires_at, department_name=dept_name,
                       event_title=event.title, hours=body.hours, work_date=body.work_date)


@router.get("", response_model=list[CodeListItem])
def my_codes(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    _require_creator(db, user)
    is_admin = _has_role(db, user.id, "admin")
    rows = db.execute(text("""
        SELECT c.id, d.name AS department_name, a.title AS event_title, t.name AS task_name,
               c.minutes, c.work_date, c.created_at, c.expires_at, c.cancelled_at,
               (SELECT COUNT(*) FROM shared_hour_code_redemptions r WHERE r.code_id = c.id) AS redemptions
        FROM shared_hour_codes c
        JOIN departments d ON d.id = c.department_id
        JOIN activities a ON a.id = c.activity_id
        LEFT JOIN activity_tasks t ON t.id = c.task_id
        WHERE (:is_admin OR c.created_by = :uid)
        ORDER BY c.created_at DESC
        LIMIT 200"""), {"is_admin": is_admin, "uid": user.id}).all()
    now = utcnow()
    out = []
    for r in rows:
        if r.cancelled_at is not None:
            state = "cancelled"
        elif r.expires_at <= now:
            state = "expired"
        else:
            state = "active"
        out.append(CodeListItem(
            id=r.id, department_name=r.department_name, event_title=r.event_title,
            task_name=r.task_name, hours=r.minutes // 60, work_date=r.work_date,
            created_at=r.created_at, expires_at=r.expires_at,
            redemptions=int(r.redemptions), state=state))
    return out


@router.post("/{code_id}/cancel", response_model=Message)
def cancel_code(code_id: uuid.UUID, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    _require_creator(db, user)
    row = db.execute(text(
        "SELECT created_by, cancelled_at FROM shared_hour_codes WHERE id = :id FOR UPDATE"),
        {"id": code_id}).first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Codul nu există.")
    if row.created_by != user.id and not _has_role(db, user.id, "admin"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Poți anula doar codurile tale.")
    if row.cancelled_at is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Codul este deja anulat.")
    db.execute(text("UPDATE shared_hour_codes SET cancelled_at = now() WHERE id = :id"), {"id": code_id})
    audit(db, user.id, "hours.code_cancelled", "shared_hour_code", code_id, {})
    db.commit()
    return Message(message="Codul a fost anulat.")


@router.post("/redeem", response_model=Message, status_code=status.HTTP_201_CREATED)
def redeem(body: RedeemIn, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    # Lock the code row so that concurrent redemptions are serialised.
    code = db.execute(text("""
        SELECT id, created_by, activity_id, task_id, department_id, work_date, minutes,
               description, expires_at, cancelled_at
        FROM shared_hour_codes WHERE code_digest = :d FOR UPDATE"""),
        {"d": _digest(body.code)}).first()
    if code is None or code.cancelled_at is not None or code.expires_at <= utcnow():
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Codul nu este valid sau a expirat.")
    if code.created_by == user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Nu poți folosi un cod generat de tine.")
    if code.department_id not in _allowed_department_ids(db, user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Codul nu este pentru departamentele tale.")

    already = db.execute(text(
        "SELECT 1 FROM shared_hour_code_redemptions WHERE code_id = :cid AND user_id = :uid"),
        {"cid": code.id, "uid": user.id}).first()
    if already is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Ai folosit deja acest cod.")

    entry_id = db.execute(text("""
        INSERT INTO time_entries (user_id, activity_id, department_id, task_id,
                                  activity_name_snapshot, work_date, duration_minutes,
                                  description, source, status, shared_code_id)
        VALUES (:uid, :eid, :did, :tid,
                (SELECT title FROM activities WHERE id = :eid),
                :d, :minutes, :desc, 'shared_code', 'approved', :cid)
        RETURNING id"""),
        {"uid": user.id, "eid": code.activity_id, "did": code.department_id, "tid": code.task_id,
         "d": code.work_date, "minutes": code.minutes, "desc": code.description or "",
         "cid": code.id}).scalar()
    db.execute(text("""
        INSERT INTO shared_hour_code_redemptions (code_id, user_id, time_entry_id)
        VALUES (:cid, :uid, :eid)"""), {"cid": code.id, "uid": user.id, "eid": entry_id})
    audit(db, user.id, "hours.code_redeemed", "time_entry", entry_id,
          {"user_id": str(user.id), "minutes": code.minutes})
    db.commit()
    return Message(message=f"Ai primit {code.minutes // 60} ore.")