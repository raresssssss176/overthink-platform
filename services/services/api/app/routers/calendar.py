"""Calendar: dated, published events visible to the caller.
Coordinators and administrators see every published event. Volunteers see the events of their
departments (including the general meeting) and club-wide events."""
import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import Profile
from app.routers.hours import _allowed_department_ids, _has_role

router = APIRouter(prefix="/calendar", tags=["calendar"])

MAX_RANGE_DAYS = 100


class CalendarEvent(BaseModel):
    id: uuid.UUID
    title: str
    event_date: date
    departments: list[str]


@router.get("/events", response_model=list[CalendarEvent])
def calendar_events(start: date, end: date, user: Profile = Depends(require_active),
                    db: Session = Depends(get_db)):
    if end < start:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Intervalul este invalid.")
    if (end - start) > timedelta(days=MAX_RANGE_DAYS):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Intervalul este prea mare.")

    sees_all = _has_role(db, user.id, "admin") or _has_role(db, user.id, "coordinator")
    allowed = list(_allowed_department_ids(db, user)) or [uuid.UUID(int=0)]

    rows = db.execute(text("""
        SELECT a.id, a.title,
               CAST(a.starts_at AT TIME ZONE 'Europe/Bucharest' AS date) AS event_date,
               COALESCE(array_agg(d.name ORDER BY d.name)
                        FILTER (WHERE d.id IS NOT NULL), '{}') AS dept_names
        FROM activities a
        LEFT JOIN activity_departments ad ON ad.activity_id = a.id
        LEFT JOIN departments d ON d.id = ad.department_id
        WHERE a.status = 'published'
          AND a.starts_at IS NOT NULL
          AND CAST(a.starts_at AT TIME ZONE 'Europe/Bucharest' AS date) BETWEEN :start AND :end
          AND (:sees_all OR a.visibility = 'club' OR ad.department_id = ANY(:dids))
        GROUP BY a.id
        ORDER BY event_date, a.title"""),
        {"start": start, "end": end, "sees_all": sees_all, "dids": allowed}).all()

    return [CalendarEvent(id=r.id, title=r.title, event_date=r.event_date,
                          departments=list(r.dept_names)) for r in rows]