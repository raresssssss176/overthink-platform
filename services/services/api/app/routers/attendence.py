"""Attendance marking and .xlsx export for today's published events.

Who can mark attendance for an event:
- Administrators: any published event.
- Users with an active club-wide 'attendance.mark' grant: any published event.
- Coordinators: published events linked to a department they coordinate.
- Volunteers with an active department-scoped 'attendance.mark' grant: published events
  linked to the granted department(s).
"""
import io
import re
import unicodedata
import uuid
from datetime import date, datetime
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.deps import require_active
from app.models import Profile
from app.routers.hours import _coordinated_department_ids, _has_role
from app.schemas import Message
from app.services import audit

router = APIRouter(prefix="/attendance", tags=["attendance"])

BUCHAREST_TZ = ZoneInfo("Europe/Bucharest")
AttendanceStatus = Literal["unknown", "present", "absent", "excused"]

_STATUS_LABELS: dict[str, str] = {
    "present": "Prezent",
    "absent": "Absent",
    "excused": "Motivat",
    "unknown": "Nemarcat",
}


# ---------- schemas ----------

class AttendanceEventOut(BaseModel):
    id: uuid.UUID
    title: str
    event_date: date
    departments: list[str]
    total_participants: int
    marked_participants: int


class RosterParticipantOut(BaseModel):
    user_id: uuid.UUID
    first_name: str
    last_name: str
    email: str
    acronym: str | None
    departments: list[str]
    attendance_status: AttendanceStatus


class EventRosterOut(BaseModel):
    event_id: uuid.UUID
    event_title: str
    event_date: date
    departments: list[str]
    participants: list[RosterParticipantOut]


class RosterItemIn(BaseModel):
    user_id: uuid.UUID
    attendance_status: AttendanceStatus


class RosterUpdateIn(BaseModel):
    items: list[RosterItemIn] = Field(min_length=1, max_length=500)


# ---------- helpers ----------

def _today_bucharest() -> date:
    return datetime.now(BUCHAREST_TZ).date()


def _attendance_scope(db: Session, user_id: uuid.UUID) -> tuple[bool, set[uuid.UUID]]:
    """Returns (sees_all_events, allowed_department_ids)."""
    if _has_role(db, user_id, "admin"):
        return True, set()

    has_club_grant = db.execute(text("""
        SELECT 1 FROM permission_grants
        WHERE user_id = :uid
          AND permission = 'attendance.mark'
          AND scope_type = 'club'
          AND revoked_at IS NULL
          AND expires_at > now()
        LIMIT 1"""), {"uid": user_id}).first() is not None
    if has_club_grant:
        return True, set()

    dept_ids: set[uuid.UUID] = set()
    if _has_role(db, user_id, "coordinator"):
        dept_ids.update(_coordinated_department_ids(db, user_id))

    granted_depts = db.execute(text("""
        SELECT department_id FROM permission_grants
        WHERE user_id = :uid
          AND permission = 'attendance.mark'
          AND scope_type = 'department'
          AND department_id IS NOT NULL
          AND revoked_at IS NULL
          AND expires_at > now()"""), {"uid": user_id}).scalars().all()
    dept_ids.update(granted_depts)
    return False, dept_ids


def _load_authorized_event(db: Session, user_id: uuid.UUID, event_id: uuid.UUID):
    sees_all, allowed_depts = _attendance_scope(db, user_id)
    if not sees_all and not allowed_depts:
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Nu ai permisiunea de a marca prezența.")

    row = db.execute(text("""
        SELECT a.id, a.title, a.status, a.visibility,
               CAST(a.starts_at AT TIME ZONE 'Europe/Bucharest' AS date) AS event_date,
               COALESCE(array_agg(d.id) FILTER (WHERE d.id IS NOT NULL), '{}') AS dept_ids,
               COALESCE(array_agg(d.name ORDER BY d.name)
                        FILTER (WHERE d.id IS NOT NULL), '{}') AS dept_names
        FROM activities a
        LEFT JOIN activity_departments ad ON ad.activity_id = a.id
        LEFT JOIN departments d ON d.id = ad.department_id
        WHERE a.id = :eid AND a.status = 'published' AND a.starts_at IS NOT NULL
        GROUP BY a.id"""), {"eid": event_id}).first()

    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND,
                            "Evenimentul nu există sau nu este publicat.")

    if not sees_all:
        event_depts = set(row.dept_ids or [])
        if not event_depts.intersection(allowed_depts):
            raise HTTPException(status.HTTP_403_FORBIDDEN,
                                "Nu ai permisiunea de a marca prezența pentru acest eveniment.")

    return row


def _require_event_today(event_date: date) -> None:
    if event_date != _today_bucharest():
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Prezența poate fi marcată doar în ziua evenimentului.")


def _sync_event_roster(db: Session, event_id: uuid.UUID) -> None:
    """Ensure all active members of the event's departments are in activity_participants."""
    db.execute(text("""
        INSERT INTO activity_participants (activity_id, user_id, attendance_status)
        SELECT :eid, p.id, 'unknown'
        FROM profiles p
        WHERE p.account_status = 'active'
          AND (
              p.primary_department_id IN (
                  SELECT department_id FROM activity_departments WHERE activity_id = :eid
              )
              OR EXISTS (
                  SELECT 1
                  FROM member_departments md
                  JOIN activity_departments ad ON ad.department_id = md.department_id
                  WHERE md.user_id = p.id AND ad.activity_id = :eid
              )
              OR EXISTS (
                  SELECT 1
                  FROM activity_departments ad
                  JOIN departments d ON d.id = ad.department_id
                  WHERE ad.activity_id = :eid AND d.slug = 'sedinta-generala'
              )
              OR (
                  EXISTS (
                      SELECT 1 FROM activities a
                      WHERE a.id = :eid AND a.visibility = 'club'
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM activity_departments ad WHERE ad.activity_id = :eid
                  )
              )
          )
        ON CONFLICT (activity_id, user_id) DO NOTHING"""), {"eid": event_id})


def _fetch_roster_rows(db: Session, event_id: uuid.UUID):
    return db.execute(text("""
        SELECT ap.user_id,
               p.first_name,
               p.last_name,
               p.email,
               p.acronym,
               ap.attendance_status,
               COALESCE(
                   (
                       SELECT array_agg(DISTINCT d.name ORDER BY d.name)
                       FROM departments d
                       WHERE d.id = p.primary_department_id
                          OR d.id IN (
                              SELECT md.department_id
                              FROM member_departments md
                              WHERE md.user_id = p.id
                          )
                   ),
                   '{}'
               ) AS departments
        FROM activity_participants ap
        JOIN profiles p ON p.id = ap.user_id
        WHERE ap.activity_id = :eid
        ORDER BY p.last_name, p.first_name, p.email"""), {"eid": event_id}).all()


def _safe_filename(title: str, event_date: date) -> str:
    normalized = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", normalized).strip("-").lower() or "eveniment"
    return f"prezenta_{slug[:50]}_{event_date.isoformat()}.xlsx"


def _build_xlsx(event_title: str, event_date: date, departments: list[str], rows) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Prezență"

    bold = Font(bold=True)
    header_font = Font(bold=True, color="FFFFFF")
    header_fill = PatternFill(fill_type="solid", fgColor="1E293B")
    thin_side = Side(style="thin", color="CBD5E1")
    border = Border(left=thin_side, right=thin_side, top=thin_side, bottom=thin_side)

    ws["A1"] = "Eveniment:"
    ws["A1"].font = bold
    ws["B1"] = event_title

    ws["A2"] = "Data:"
    ws["A2"].font = bold
    ws["B2"] = event_date.strftime("%d.%m.%Y")

    ws["A3"] = "Departamente:"
    ws["A3"].font = bold
    ws["B3"] = ", ".join(departments) if departments else "Club"

    headers = ["Nr.", "Nume", "Prenume", "Email", "Acronim", "Departament", "Status prezență"]
    header_row = 5
    for col_idx, text_val in enumerate(headers, start=1):
        cell = ws.cell(row=header_row, column=col_idx, value=text_val)
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="left", vertical="center")
        cell.border = border

    counts = {"present": 0, "absent": 0, "excused": 0, "unknown": 0}
    for idx, r in enumerate(rows, start=1):
        counts[r.attendance_status] = counts.get(r.attendance_status, 0) + 1
        row_num = header_row + idx
        values = [
            idx,
            r.last_name,
            r.first_name,
            r.email,
            r.acronym or "-",
            ", ".join(r.departments) if r.departments else "-",
            _STATUS_LABELS.get(r.attendance_status, r.attendance_status),
        ]
        for col_idx, val in enumerate(values, start=1):
            cell = ws.cell(row=row_num, column=col_idx, value=val)
            cell.border = border
            cell.alignment = Alignment(horizontal="left", vertical="center")

    summary_start = header_row + len(rows) + 2
    summary_items = [
        ("Total membri", len(rows)),
        ("Prezenți", counts["present"]),
        ("Absenți", counts["absent"]),
        ("Motivați", counts["excused"]),
        ("Nemarcați", counts["unknown"]),
    ]
    for offset, (label, total) in enumerate(summary_items):
        ws.cell(row=summary_start + offset, column=1, value=label).font = bold
        ws.cell(row=summary_start + offset, column=2, value=total)

    for col in ws.columns:
        col_letter = get_column_letter(col[0].column)
        max_len = max((len(str(cell.value or "")) for cell in col), default=10)
        ws.column_dimensions[col_letter].width = min(max(max_len + 4, 12), 45)

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


# ---------- endpoints ----------

@router.get("/events", response_model=list[AttendanceEventOut])
def list_attendance_events(user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    sees_all, allowed_depts = _attendance_scope(db, user.id)
    if not sees_all and not allowed_depts:
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Nu ai permisiunea de a marca prezența.")

    today = _today_bucharest()
    dids = list(allowed_depts) or [uuid.UUID(int=0)]

    rows = db.execute(text("""
        SELECT a.id,
               a.title,
               CAST(a.starts_at AT TIME ZONE 'Europe/Bucharest' AS date) AS event_date,
               COALESCE(array_agg(DISTINCT d.name ORDER BY d.name)
                        FILTER (WHERE d.id IS NOT NULL), '{}') AS dept_names,
               (SELECT COUNT(*) FROM activity_participants ap WHERE ap.activity_id = a.id) AS total_count,
               (SELECT COUNT(*) FROM activity_participants ap
                WHERE ap.activity_id = a.id AND ap.attendance_status <> 'unknown') AS marked_count
        FROM activities a
        LEFT JOIN activity_departments ad ON ad.activity_id = a.id
        LEFT JOIN departments d ON d.id = ad.department_id
        WHERE a.status = 'published'
          AND a.starts_at IS NOT NULL
          AND CAST(a.starts_at AT TIME ZONE 'Europe/Bucharest' AS date) = :today
          AND (:sees_all OR ad.department_id = ANY(:dids))
        GROUP BY a.id
        ORDER BY a.title"""),
        {"today": today, "sees_all": sees_all, "dids": dids}).all()

    return [
        AttendanceEventOut(
            id=r.id,
            title=r.title,
            event_date=r.event_date,
            departments=list(r.dept_names),
            total_participants=int(r.total_count),
            marked_participants=int(r.marked_count),
        )
        for r in rows
    ]


@router.get("/events/{event_id}/roster", response_model=EventRosterOut)
def get_event_roster(event_id: uuid.UUID, user: Profile = Depends(require_active),
                     db: Session = Depends(get_db)):
    event = _load_authorized_event(db, user.id, event_id)
    _require_event_today(event.event_date)

    _sync_event_roster(db, event.id)
    db.commit()

    rows = _fetch_roster_rows(db, event.id)
    return EventRosterOut(
        event_id=event.id,
        event_title=event.title,
        event_date=event.event_date,
        departments=list(event.dept_names),
        participants=[
            RosterParticipantOut(
                user_id=r.user_id,
                first_name=r.first_name,
                last_name=r.last_name,
                email=r.email,
                acronym=r.acronym,
                departments=list(r.departments),
                attendance_status=r.attendance_status,
            )
            for r in rows
        ],
    )


@router.put("/events/{event_id}/roster", response_model=Message)
def save_event_roster(event_id: uuid.UUID, body: RosterUpdateIn,
                      user: Profile = Depends(require_active), db: Session = Depends(get_db)):
    event = _load_authorized_event(db, user.id, event_id)
    _require_event_today(event.event_date)

    seen: set[uuid.UUID] = set()
    for item in body.items:
        if item.user_id in seen:
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                                "Lista conține utilizatori duplicați.")
        seen.add(item.user_id)

    existing_ids = set(db.execute(text(
        "SELECT user_id FROM activity_participants WHERE activity_id = :eid"),
        {"eid": event.id}).scalars().all())
    if not seen.issubset(existing_ids):
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY,
                            "Unul dintre utilizatori nu face parte din lista de prezență a evenimentului.")

    for item in body.items:
        db.execute(text("""
            UPDATE activity_participants
            SET attendance_status = :status
            WHERE activity_id = :eid AND user_id = :uid"""),
            {"status": item.attendance_status, "eid": event.id, "uid": item.user_id})

    audit(db, user.id, "attendance.marked", "activity", event.id,
          {"updated_count": len(body.items)})
    db.commit()
    return Message(message="Prezența a fost salvată.")


@router.get("/events/{event_id}/export")
def export_event_roster(event_id: uuid.UUID, user: Profile = Depends(require_active),
                        db: Session = Depends(get_db)):
    event = _load_authorized_event(db, user.id, event_id)
    if event.event_date == _today_bucharest():
        _sync_event_roster(db, event.id)
        db.commit()

    rows = _fetch_roster_rows(db, event.id)
    content = _build_xlsx(event.title, event.event_date, list(event.dept_names), rows)
    filename = _safe_filename(event.title, event.event_date)

    return Response(
        content=content,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )