"""Dated events created by coordinators and administrators, linked to departments.

Who can create events for which departments:
- Administrators: any active department.
- Anyone with a club-wide calendar.create grant (issued by an administrator): any department.
- Coordinators: only the departments they coordinate.
"""
import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import Profile
from app.routers.hours import _coordinated_department_ids, _has_role
from app.schemas import Message
from app.services import audit

router = APIRouter(prefix="/events", tags=["events"])


# ---------- schemas ----------

class DepartmentOpt(BaseModel):
    id: uuid.UUID
    name: str


class EventIn(BaseModel):
    title: str = Field(min_length=2, max_length=200)
    starts_on: date
    department_ids: list[uuid.UUID] = Field(min_length=1, max_length=20)


class EventManageOut(BaseModel):
    id: uuid.UUID
    title: str
    event_date: date
    status: str
    departments: list[str]
    created_by_name: str | None
    can_cancel: bool


# ---------- helpers ----------

def _has_club_calendar_grant(db: Session, user_id: uuid.UUID) -> bool:
    return db.execute(text("""
        SELECT 1 FROM permission_grants
        WHERE user_id = :uid AND permission = 'calendar.create' AND scope_type = 'club'
          AND revoked_at IS NULL AND expires_at > now()
        LIMIT 1"""), {"uid": user_id}).first() is not None


def _sees_all_departments(db: Session, user: Profile) -> bool:
    return _has_role(db, user.id, "admin") or _has_club_calendar_grant(db, user.id)


def _allowed_department_ids(db: Session, user: Profile) -> set[uuid.UUID]:
    if _sees_all_departments(db, user):
        return set(db.execute(text("SELECT id FROM departments WHERE is_active")).scalars().all())
    if _has_role(db, user.id, "coordinator"):
        return _coordinated_department_ids(db, user.id)
    return set()


# ---------- endpoints ----------

@router.get("/departments", response_model=list[DepartmentOpt])
def event_departments(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    ids = list(_allowed_department_ids(db, user))
    if not ids:
        return []
    rows = db.execute(text("SELECT id, name FROM departments WHERE id = ANY(:ids) ORDER BY name"),
                      {"ids": ids}).all()
    return [DepartmentOpt(id=r.id, name=r.name) for r in rows]


@router.post("", response_model=Message, status_code=status.HTTP_201_CREATED)
def create_event(body: EventIn, user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    allowed = _allowed_department_ids(db, user)
    if not allowed:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Nu poți adăuga evenimente.")
    wanted = set(body.department_ids)
    if not wanted.issubset(allowed):
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Poți adăuga evenimente doar pentru departamentele tale.")

    # The date is taken as Bucharest local midnight.
    event_id = db.execute(text("""
        INSERT INTO activities (title, starts_at, status, visibility, created_by)
        VALUES (:title,
                ((CAST(:d AS date) + TIME '00:00') AT TIME ZONE 'Europe/Bucharest'),
                'published', 'departments', :uid)
        RETURNING id"""),
        {"title": body.title.strip(), "d": body.starts_on, "uid": user.id}).scalar()
    for dept_id in wanted:
        db.execute(text("""
            INSERT INTO activity_departments (activity_id, department_id)
            VALUES (:eid, :did)"""), {"eid": event_id, "did": dept_id})
    audit(db, user.id, "event.created", "activity", event_id,
          {"departments": [str(d) for d in wanted]})
    db.commit()
    return Message(message="Evenimentul a fost adăugat.")


@router.get("/manage", response_model=list[EventManageOut])
def manage_events(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    sees_all = _sees_all_departments(db, user)
    allowed = list(_allowed_department_ids(db, user)) or [uuid.UUID(int=0)]
    rows = db.execute(text("""
        SELECT a.id, a.title, a.status, a.created_by,
               CAST(a.starts_at AT TIME ZONE 'Europe/Bucharest' AS date) AS event_date,
               p.first_name || ' ' || p.last_name AS creator_name,
               COALESCE(array_agg(d.name ORDER BY d.name)
                        FILTER (WHERE d.id IS NOT NULL), '{}') AS dept_names
        FROM activities a
        LEFT JOIN profiles p ON p.id = a.created_by
        LEFT JOIN activity_departments ad ON ad.activity_id = a.id
        LEFT JOIN departments d ON d.id = ad.department_id
        WHERE a.visibility = 'departments' AND a.starts_at IS NOT NULL
          AND (:sees_all OR a.created_by = :uid OR ad.department_id = ANY(:dids))
        GROUP BY a.id, p.first_name, p.last_name
        ORDER BY event_date DESC, a.title
        LIMIT 300"""),
        {"sees_all": sees_all, "uid": user.id, "dids": allowed}).all()

    out = []
    for r in rows:
        can_cancel = (sees_all or r.created_by == user.id) and r.status == "published"
        out.append(EventManageOut(
            id=r.id, title=r.title, event_date=r.event_date, status=r.status,
            departments=list(r.dept_names), created_by_name=r.creator_name, can_cancel=can_cancel))
    return out


@router.post("/{event_id}/cancel", response_model=Message)
def cancel_event(event_id: uuid.UUID, user: Profile = Depends(require_active),
                 db: Session = Depends(get_db)):
    row = db.execute(text("""
        SELECT created_by, status FROM activities
        WHERE id = :id AND visibility = 'departments' FOR UPDATE"""), {"id": event_id}).first()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Evenimentul nu există.")
    if row.created_by != user.id and not _sees_all_departments(db, user):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Poți anula doar evenimentele tale.")
    if row.status != "published":
        raise HTTPException(status.HTTP_409_CONFLICT, "Evenimentul nu poate fi anulat în starea actuală.")
    db.execute(text("UPDATE activities SET status = 'cancelled', updated_at = now() WHERE id = :id"),
               {"id": event_id})
    audit(db, user.id, "event.cancelled", "activity", event_id, {})
    db.commit()
    return Message(message="Evenimentul a fost anulat.")