"""Hours: events, tasks, manual submissions, review (approve/reject) and history.
Events are created in app/routers/events.py. Shared codes live in app/routers/codes.py."""
import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import Profile
from app.schemas import Message
from app.services import audit

router = APIRouter(prefix="/hours", tags=["hours"])


# ---------- schemas ----------

class DepartmentOption(BaseModel):
    id: uuid.UUID
    name: str


class EventOut(BaseModel):
    id: uuid.UUID
    title: str
    starts_at: date | None


class TaskOut(BaseModel):
    id: uuid.UUID
    name: str


class TaskIn(BaseModel):
    name: str = Field(min_length=2, max_length=120)


class ManualIn(BaseModel):
    department_id: uuid.UUID
    # Either an existing event, or "Altul" with a typed title (kept as a draft).
    event_id: uuid.UUID | None = None
    new_event_title: str | None = Field(default=None, min_length=2, max_length=200)
    task_id: uuid.UUID | None = None
    new_task_name: str | None = Field(default=None, min_length=2, max_length=120)
    work_date: date
    hours: int = Field(ge=1, le=12)
    mentions: str | None = Field(default=None, max_length=500)


class EntryOut(BaseModel):
    id: uuid.UUID
    status: str
    source: str
    hours: int
    work_date: date
    event_title: str
    task_name: str | None
    department_name: str | None
    member_name: str | None
    description: str
    rejection_reason: str | None


class RejectIn(BaseModel):
    reason: str = Field(min_length=3, max_length=500)


# ---------- helpers ----------

_ENTRY_SELECT = """
    SELECT te.id, te.status, te.source, te.duration_minutes, te.work_date, te.description,
           te.rejection_reason, te.activity_name_snapshot AS event_title,
           t.name AS task_name, d.name AS department_name,
           p.first_name || ' ' || p.last_name AS member_name
    FROM time_entries te
    LEFT JOIN activity_tasks t ON t.id = te.task_id
    LEFT JOIN departments d ON d.id = te.department_id
    LEFT JOIN profiles p ON p.id = te.user_id
"""


def _has_role(db: Session, user_id: uuid.UUID, role: str) -> bool:
    return db.execute(text("SELECT 1 FROM user_roles WHERE user_id = :uid AND role = :r"),
                      {"uid": user_id, "r": role}).first() is not None


def _member_department_ids(db: Session, user_id: uuid.UUID) -> set[uuid.UUID]:
    ids = set(db.execute(text(
        "SELECT department_id FROM member_departments WHERE user_id = :uid"),
        {"uid": user_id}).scalars().all())
    primary = db.execute(text("SELECT primary_department_id FROM profiles WHERE id = :uid"),
                         {"uid": user_id}).scalar()
    if primary is not None:
        ids.add(primary)
    return ids


def _general_department_id(db: Session) -> uuid.UUID | None:
    return db.execute(text("SELECT id FROM departments WHERE slug = 'sedinta-generala'")).scalar()


def _allowed_department_ids(db: Session, user: Profile) -> set[uuid.UUID]:
    """Admins: every active department. Members: their departments plus the general meeting."""
    if _has_role(db, user.id, "admin"):
        return set(db.execute(text("SELECT id FROM departments WHERE is_active")).scalars().all())
    ids = _member_department_ids(db, user.id)
    general = _general_department_id(db)
    if general is not None:
        ids.add(general)
    return ids


def _coordinated_department_ids(db: Session, user_id: uuid.UUID) -> set[uuid.UUID]:
    return set(db.execute(text(
        "SELECT id FROM departments WHERE coordinator_user_id = :uid"),
        {"uid": user_id}).scalars().all())


def _event_or_404(db: Session, event_id: uuid.UUID):
    row = db.execute(text(
        "SELECT id, title FROM activities WHERE id = :eid AND status = 'published'"),
        {"eid": event_id}).first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Evenimentul nu există sau nu este publicat.")
    return row


def _task_id_for_event(db: Session, event_id: uuid.UUID, name: str, user_id: uuid.UUID) -> uuid.UUID:
    db.execute(text("""
        INSERT INTO activity_tasks (activity_id, name, created_by)
        VALUES (:eid, :name, :uid)
        ON CONFLICT (activity_id, name) DO NOTHING"""),
        {"eid": event_id, "name": name.strip(), "uid": user_id})
    return db.execute(text(
        "SELECT id FROM activity_tasks WHERE activity_id = :eid AND name = :name"),
        {"eid": event_id, "name": name.strip()}).scalar()


def _entry_out(r) -> EntryOut:
    return EntryOut(
        id=r.id, status=r.status, source=r.source, hours=r.duration_minutes // 60,
        work_date=r.work_date, event_title=r.event_title, task_name=r.task_name,
        department_name=r.department_name, member_name=r.member_name,
        description=r.description or "", rejection_reason=r.rejection_reason)


# ---------- departments, events, tasks ----------

@router.get("/my-departments", response_model=list[DepartmentOption])
def my_departments(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    ids = list(_allowed_department_ids(db, user))
    if not ids:
        return []
    rows = db.execute(text("SELECT id, name FROM departments WHERE id = ANY(:ids) ORDER BY name"),
                      {"ids": ids}).all()
    return [DepartmentOption(id=r.id, name=r.name) for r in rows]


@router.get("/events", response_model=list[EventOut])
def list_events(_: Profile = Depends(require_active), db: Session = Depends(get_db)):
    rows = db.execute(text("""
        SELECT id, title, starts_at FROM activities
        WHERE status = 'published'
        ORDER BY starts_at NULLS LAST, title""")).all()
    return [EventOut(id=r.id, title=r.title, starts_at=r.starts_at.date() if r.starts_at else None)
            for r in rows]


@router.get("/events/{event_id}/tasks", response_model=list[TaskOut])
def list_tasks(event_id: uuid.UUID, _: Profile = Depends(require_active), db: Session = Depends(get_db)):
    rows = db.execute(text(
        "SELECT id, name FROM activity_tasks WHERE activity_id = :eid ORDER BY name"),
        {"eid": event_id}).all()
    return [TaskOut(id=r.id, name=r.name) for r in rows]


@router.post("/events/{event_id}/tasks", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def add_task(event_id: uuid.UUID, body: TaskIn, user: Profile = Depends(require_active),
             db: Session = Depends(get_db)):
    _event_or_404(db, event_id)
    task_id = _task_id_for_event(db, event_id, body.name, user.id)
    row = db.execute(text("SELECT id, name FROM activity_tasks WHERE id = :tid"),
                     {"tid": task_id}).first()
    db.commit()
    return TaskOut(id=row.id, name=row.name)


# ---------- submissions ----------

@router.post("/manual", response_model=Message, status_code=status.HTTP_201_CREATED)
def submit_manual(body: ManualIn, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    if body.department_id not in _allowed_department_ids(db, user):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            "Nu poți adăuga ore pentru acest departament.")
    if body.work_date > date.today():
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Data nu poate fi în viitor.")
    if body.event_id is None and not body.new_event_title:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            "Alege evenimentul sau scrie numele lui.")

    if body.event_id is not None:
        event = _event_or_404(db, body.event_id)
        event_id, event_title = event.id, event.title
    else:
        # "Altul": the volunteer typed an event. It stays a draft, so other members
        # never see it. Coordinators or admins can publish or merge it later.
        event_title = body.new_event_title.strip()
        event_id = db.execute(text("""
            INSERT INTO activities (title, status, visibility, created_by)
            VALUES (:title, 'draft', 'club', :uid)
            RETURNING id"""), {"title": event_title, "uid": user.id}).scalar()
        audit(db, user.id, "event.draft_created", "activity", event_id, {"title": event_title})

    task_id = body.task_id
    if body.new_task_name:
        task_id = _task_id_for_event(db, event_id, body.new_task_name, user.id)
    if task_id is not None:
        belongs = db.execute(text(
            "SELECT 1 FROM activity_tasks WHERE id = :tid AND activity_id = :eid"),
            {"tid": task_id, "eid": event_id}).first()
        if belongs is None:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                                "Task-ul nu aparține evenimentului ales.")

    minutes = body.hours * 60
    entry_id = db.execute(text("""
        INSERT INTO time_entries (user_id, activity_id, department_id, task_id,
                                  activity_name_snapshot, work_date, duration_minutes,
                                  description, source, status)
        VALUES (:uid, :eid, :did, :tid, :title, :d, :minutes, :desc, 'manual', 'pending')
        RETURNING id"""),
        {"uid": user.id, "eid": event_id, "did": body.department_id, "tid": task_id,
         "title": event_title, "d": body.work_date, "minutes": minutes,
         "desc": (body.mentions or "").strip()}).scalar()
    audit(db, user.id, "hours.submitted", "time_entry", entry_id, {"minutes": minutes})
    db.commit()
    return Message(message="Orele au fost trimise spre aprobare.")


# ---------- history and review ----------

@router.get("/mine", response_model=list[EntryOut])
def my_entries(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    rows = db.execute(text(_ENTRY_SELECT + """
        WHERE te.user_id = :uid
        ORDER BY te.work_date DESC, te.created_at DESC"""), {"uid": user.id}).all()
    return [_entry_out(r) for r in rows]


@router.get("/review", response_model=list[EntryOut])
def review_queue(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    if _has_role(db, user.id, "admin"):
        rows = db.execute(text(_ENTRY_SELECT + """
            WHERE te.status = 'pending'
            ORDER BY te.created_at""")).all()
    else:
        dept_ids = list(_coordinated_department_ids(db, user.id))
        if not dept_ids:
            return []
        rows = db.execute(text(_ENTRY_SELECT + """
            WHERE te.status = 'pending' AND te.department_id = ANY(:dids)
            ORDER BY te.created_at"""), {"dids": dept_ids}).all()
    return [_entry_out(r) for r in rows]


def _load_for_review(db: Session, entry_id: uuid.UUID, reviewer: Profile):
    entry = db.execute(text(
        "SELECT id, user_id, department_id, duration_minutes, status FROM time_entries "
        "WHERE id = :id FOR UPDATE"), {"id": entry_id}).first()
    if entry is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pontajul nu există.")
    if entry.user_id == reviewer.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Nu îți poți aproba propriile ore.")
    if not _has_role(db, reviewer.id, "admin") and \
            entry.department_id not in _coordinated_department_ids(db, reviewer.id):
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Poți revizui doar orele din departamentele tale.")
    if entry.status != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "Pontajul a fost deja revizuit.")
    return entry


@router.post("/review/{entry_id}/approve", response_model=Message)
def approve(entry_id: uuid.UUID, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    entry = _load_for_review(db, entry_id, user)
    db.execute(text("""
        UPDATE time_entries SET status = 'approved', reviewed_by = :uid, reviewed_at = now()
        WHERE id = :id"""), {"uid": user.id, "id": entry_id})
    audit(db, user.id, "hours.approved", "time_entry", entry_id,
          {"user_id": str(entry.user_id), "minutes": entry.duration_minutes})
    db.commit()
    return Message(message="Orele au fost aprobate.")


@router.post("/review/{entry_id}/reject", response_model=Message)
def reject(entry_id: uuid.UUID, body: RejectIn, user: Profile = Depends(require_active),
           db: Session = Depends(get_db)):
    entry = _load_for_review(db, entry_id, user)
    db.execute(text("""
        UPDATE time_entries SET status = 'rejected', reviewed_by = :uid, reviewed_at = now(),
               rejection_reason = :reason
        WHERE id = :id"""), {"uid": user.id, "id": entry_id, "reason": body.reason.strip()})
    audit(db, user.id, "hours.rejected", "time_entry", entry_id,
          {"user_id": str(entry.user_id), "minutes": entry.duration_minutes})
    db.commit()
    return Message(message="Orele au fost respinse.")