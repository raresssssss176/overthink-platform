import uuid

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db import get_db
from app.models import AccountStatus, Profile
from app.security import decode_access_token
from app.services import has_permission

_bearer = HTTPBearer(auto_error=False)
_UNAUTH = HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated",
                        headers={"WWW-Authenticate": "Bearer"})


def get_current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
                     db: Session = Depends(get_db)) -> Profile:
    """Any logged-in user whose account can sign in (pending or active)."""
    if creds is None:
        raise _UNAUTH
    try:
        payload = decode_access_token(creds.credentials)
        user = db.get(Profile, uuid.UUID(payload["sub"]))
    except (jwt.PyJWTError, ValueError, KeyError):
        raise _UNAUTH
    if user is None or user.credential.credentials_version != payload.get("cv"):
        raise _UNAUTH  # password changed / sessions revoked
    if user.account_status not in (AccountStatus.pending.value, AccountStatus.active.value):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account not available")
    return user


def require_active(user: Profile = Depends(get_current_user)) -> Profile:
    """Verified e-mail is NOT enough: the server insists on account_status == active."""
    if user.account_status != AccountStatus.active.value:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account is awaiting approval")
    return user


def require_permission(permission: str):
    def dep(user: Profile = Depends(require_active), db: Session = Depends(get_db)) -> Profile:
        if not has_permission(db, user.id, permission):
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Missing permission")
        return user
    return dep
