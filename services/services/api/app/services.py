import uuid
from sqlalchemy import select
from sqlalchemy.orm import Session
from app.emailer import send_email_safe
from app.models import AccountStatus, AuditLog, UserRole, PermissionGrant, Profile

def audit(db:Session, actor_id:uuid.UUID|None, action:str, entity_type:str,
          entity_id:uuid.UUID|None=None, details:dict|None=None)->None:
    db.add(AuditLog(actor_id=actor_id, action=action, entity_type=entity_type,
                    entity_id=entity_id, metadata_safe_json=details or {}))

def has_permission(db:Session,user_id:uuid.UUID,permission:str)->bool:
    # Existing two admins are represented by user_roles, not permission_grants.
    if db.scalar(select(UserRole.user_id).where(UserRole.user_id==user_id, UserRole.role=='admin')):
        return True
    return bool(db.scalar(select(PermissionGrant.id).where(
        PermissionGrant.user_id==user_id,PermissionGrant.permission==permission,
        PermissionGrant.scope_type=='club',PermissionGrant.revoked_at.is_(None))))

def notify_reviewers(db:Session, subject:str, body:str)->int:
    reviewers=db.scalars(select(Profile).where(Profile.account_status==AccountStatus.active.value)).all()
    count=0
    for person in reviewers:
        if has_permission(db,person.id,'members.review'):
            send_email_safe(person.email,subject,body);count+=1
    return count
