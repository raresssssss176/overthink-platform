"""ORM models mapped EXACTLY to original database/001_initial_schema.sql.
Only authentication-related entities are mapped here; existing remaining tables stay intact.
Do not run Base.metadata.create_all against the populated database.
"""
import enum
import uuid
from datetime import datetime, timezone, date
from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Integer, String, Text, Uuid, text as sqltext, JSON
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase): pass

def utcnow() -> datetime:
    return datetime.now(timezone.utc)
def _pk():
    return mapped_column(Uuid, primary_key=True, server_default=sqltext('gen_random_uuid()'))
def _ts(**kwargs):
    return mapped_column(DateTime(timezone=True), **kwargs)

class AccountStatus(str,enum.Enum):
    email_unverified='email_unverified';pending='pending';active='active'
    rejected='rejected';suspended='suspended';deleted='deleted'
class TokenPurpose(str,enum.Enum):
    verify_email='verify_email';reset_password='reset_password'
class Decision(str,enum.Enum):
    pending='pending';approved='approved';rejected='rejected'

class Profile(Base):
    __tablename__='profiles'
    id: Mapped[uuid.UUID]=_pk()
    first_name: Mapped[str]=mapped_column(Text)
    last_name: Mapped[str]=mapped_column(Text)
    email: Mapped[str]=mapped_column(Text)
    birth_date: Mapped[date|None]=mapped_column(Date,nullable=True)
    school: Mapped[str|None]=mapped_column(Text,nullable=True)
    locality: Mapped[str|None]=mapped_column(Text,nullable=True)
    primary_department_id: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    profile_photo_key: Mapped[str|None]=mapped_column(Text,nullable=True)
    approved_minutes_cached: Mapped[int]=mapped_column(Integer,server_default=sqltext('0'))
    account_status: Mapped[str]=mapped_column(Text,server_default=sqltext("'email_unverified'"))
    joined_at: Mapped[datetime|None]=_ts(nullable=True)
    privacy_notice_version: Mapped[str|None]=mapped_column(Text,nullable=True)
    privacy_acknowledged_at: Mapped[datetime|None]=_ts(nullable=True)
    created_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
    updated_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
    deleted_at: Mapped[datetime|None]=_ts(nullable=True)
    credential: Mapped['AuthCredential']=relationship(uselist=False,lazy='joined',cascade='all,delete-orphan')

class AuthCredential(Base):
    __tablename__='auth_credentials'
    user_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('profiles.id',ondelete='CASCADE'),primary_key=True)
    password_hash: Mapped[str]=mapped_column(Text)
    email_verified_at: Mapped[datetime|None]=_ts(nullable=True)
    password_changed_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
    failed_login_attempts: Mapped[int]=mapped_column(Integer,server_default=sqltext('0'))
    credentials_version: Mapped[int]=mapped_column(Integer,server_default=sqltext('1'))
    locked_until: Mapped[datetime|None]=_ts(nullable=True) # 0002 migration

class AuthToken(Base):
    __tablename__='auth_tokens'
    id: Mapped[uuid.UUID]=_pk()
    user_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('profiles.id',ondelete='CASCADE'))
    purpose: Mapped[str]=mapped_column(Text)
    token_digest: Mapped[str]=mapped_column(String(64))
    expires_at: Mapped[datetime]=_ts()
    used_at: Mapped[datetime|None]=_ts(nullable=True)
    created_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))

class AuthSession(Base):
    __tablename__='auth_sessions'
    id: Mapped[uuid.UUID]=_pk()
    user_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('profiles.id',ondelete='CASCADE'))
    refresh_token_digest: Mapped[str]=mapped_column(String(64))
    device_label: Mapped[str|None]=mapped_column(Text,nullable=True)
    created_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
    expires_at: Mapped[datetime]=_ts()
    last_used_at: Mapped[datetime|None]=_ts(nullable=True)
    revoked_at: Mapped[datetime|None]=_ts(nullable=True)
    replaced_by: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)

class MembershipRequest(Base):
    __tablename__='membership_requests'
    id: Mapped[uuid.UUID]=_pk()
    user_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('profiles.id',ondelete='RESTRICT'))
    status: Mapped[str]=mapped_column(Text,server_default=sqltext("'submitted'"))
    submitted_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
    last_reminder_at: Mapped[datetime|None]=_ts(nullable=True)
    reminder_count: Mapped[int]=mapped_column(Integer,server_default=sqltext('0'))
    reviewed_by: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    reviewed_at: Mapped[datetime|None]=_ts(nullable=True)
    decision_reason: Mapped[str|None]=mapped_column(Text,nullable=True)

class UserRole(Base):
    __tablename__='user_roles'
    user_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('profiles.id'),primary_key=True)
    role: Mapped[str]=mapped_column(Text,primary_key=True)
    assigned_by: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    assigned_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))

class PermissionGrant(Base):
    __tablename__='permission_grants'
    id: Mapped[uuid.UUID]=_pk()
    user_id: Mapped[uuid.UUID]=mapped_column(ForeignKey('profiles.id'))
    permission: Mapped[str]=mapped_column(Text)
    scope_type: Mapped[str]=mapped_column(Text)
    department_id: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    team_id: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    project_id: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    granted_by: Mapped[uuid.UUID]=mapped_column(Uuid)
    created_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
    revoked_at: Mapped[datetime|None]=_ts(nullable=True)

class AuditLog(Base):
    __tablename__='audit_logs'
    id: Mapped[uuid.UUID]=_pk()
    actor_id: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    action: Mapped[str]=mapped_column(Text)
    entity_type: Mapped[str]=mapped_column(Text)
    entity_id: Mapped[uuid.UUID|None]=mapped_column(Uuid,nullable=True)
    metadata_safe_json: Mapped[dict]=mapped_column(JSON,default=dict)
    created_at: Mapped[datetime]=_ts(server_default=sqltext('now()'))
