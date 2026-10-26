"""Admin audit log view: who promoted/demoted coordinators, granted or revoked permissions,
approved or rejected requests and hours. Reads the audit_logs table written by the other routers.
"""
import json
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import Profile
from app.routers.admin_members import require_admin

router = APIRouter(prefix="/admin", tags=["admin-audit"])


class AuditEntry(BaseModel):
    id: uuid.UUID
    created_at: datetime
    action: str
    category: str  # coordinator | permission | hours | account | other
    actor_name: str | None
    target_name: str | None
    description: str


def _category(action: str) -> str:
    if action in ("member.promoted", "member.demoted"):
        return "coordinator"
    if action.startswith("permission."):
        return "permission"
    if action.startswith("hours."):
        return "hours"
    if action.startswith("membership.") or action.startswith("account.") or action == "member.deleted":
        return "account"
    return "other"


def _describe(action: str, meta: dict, dept_names: dict[str, str], perm_labels: dict[str, str]) -> str:
    if action == "member.promoted":
        return f"Promovat la coordonator: {dept_names.get(str(meta.get('department_id')), 'departament necunoscut')}"
    if action == "member.demoted":
        return "Demotat de la coordonator"
    if action in ("permission.granted", "permission.revoked"):
        code = meta.get("permission", "")
        label = perm_labels.get(code, code)
        return f"Permisiune {'acordată' if action.endswith('granted') else 'revocată'}: {label}"
    if action == "membership.approved":
        return "Cerere de aderare aprobată"
    if action == "membership.rejected":
        return "Cerere de aderare respinsă"
    if action == "member.deleted":
        return "Cont șters"
    if action == "account.registered":
        return "Cont nou înregistrat"
    if action.startswith("hours."):
        minutes = meta.get("minutes")
        extra = f" ({minutes / 60:.1f} h)" if isinstance(minutes, (int, float)) else ""
        return f"Ore: {action.split('.', 1)[1]}{extra}"
    return action


def _safe_uuid(value) -> uuid.UUID | None:
    try:
        return uuid.UUID(str(value))
    except (ValueError, TypeError):
        return None


@router.get("/audit-logs", response_model=list[AuditEntry])
def audit_logs(limit: int = 500, _: Profile = Depends(require_admin), db: Session = Depends(get_db)):
    limit = max(1, min(limit, 1000))
    rows = db.execute(text("""
        SELECT a.id, a.created_at, a.action, a.entity_type, a.entity_id, a.metadata_safe_json,
               actor.first_name || ' ' || actor.last_name AS actor_name
        FROM audit_logs a
        LEFT JOIN profiles actor ON actor.id = a.actor_id
        ORDER BY a.created_at DESC
        LIMIT :limit"""), {"limit": limit}).all()

    dept_names = {str(r.id): r.name for r in db.execute(text("SELECT id, name FROM departments")).all()}
    perm_labels = {r.code: r.label for r in db.execute(text("SELECT code, label FROM permission_types")).all()}

    parsed = []
    target_ids = set()
    for row in rows:
        meta = row.metadata_safe_json or {}
        if isinstance(meta, str):
            meta = json.loads(meta)
        # Target: the user in the metadata, or the profile itself for member.* and account.* actions.
        target = _safe_uuid(meta.get("user_id")) or (
            _safe_uuid(row.entity_id) if row.entity_type == "profile" else None)
        if target is not None:
            target_ids.add(target)
        parsed.append((row, meta, target))

    names = {}
    if target_ids:
        names = {str(r.id): r.name for r in db.execute(text(
            "SELECT id, first_name || ' ' || last_name AS name FROM profiles WHERE id = ANY(:ids)"),
            {"ids": list(target_ids)}).all()}

    out = []
    for row, meta, target in parsed:
        out.append(AuditEntry(
            id=row.id,
            created_at=row.created_at,
            action=row.action,
            category=_category(row.action),
            actor_name=row.actor_name,
            target_name=names.get(str(target)) if target else None,
            description=_describe(row.action, meta, dept_names, perm_labels),
        ))
    return out