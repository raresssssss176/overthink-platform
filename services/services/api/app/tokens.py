"""One-time verification/reset tokens and separately stored refresh sessions."""
import uuid
from datetime import timedelta
from sqlalchemy import select, update
from sqlalchemy.orm import Session
from app.models import AuthToken, AuthSession, utcnow
from app.security import as_utc,hash_token,new_raw_token

def issue(db:Session,user_id:uuid.UUID,purpose:str,ttl:timedelta)->str:
    raw=new_raw_token()
    db.add(AuthToken(user_id=user_id,purpose=purpose,token_digest=hash_token(raw),expires_at=utcnow()+ttl))
    return raw

def consume(db:Session,raw:str,purpose:str)->AuthToken|None:
    row=db.scalar(select(AuthToken).where(AuthToken.token_digest==hash_token(raw), AuthToken.purpose==purpose).with_for_update())
    if row is None or row.used_at is not None or as_utc(row.expires_at)<=utcnow():return None
    row.used_at=utcnow()
    return row

def issue_refresh(db:Session,user_id:uuid.UUID,ttl:timedelta)->tuple[str,AuthSession]:
    raw=new_raw_token()
    session=AuthSession(user_id=user_id,refresh_token_digest=hash_token(raw),expires_at=utcnow()+ttl)
    db.add(session);db.flush()
    return raw,session

def lookup_refresh(db:Session,raw:str,lock:bool=False)->AuthSession|None:
    q=select(AuthSession).where(AuthSession.refresh_token_digest==hash_token(raw))
    return db.scalar(q.with_for_update() if lock else q)

def revoke_all_refresh(db:Session,user_id:uuid.UUID)->None:
    db.execute(update(AuthSession).where(AuthSession.user_id==user_id,AuthSession.revoked_at.is_(None)).values(revoked_at=utcnow()))
