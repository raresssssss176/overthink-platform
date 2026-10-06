from datetime import timedelta

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import tokens
from app.config import settings
from app.db import get_db
from app.deps import get_current_user
from app.emailer import send_email_safe
from app.models import AccountStatus, AuthCredential, MembershipRequest, Profile, TokenPurpose, utcnow
from app.rate_limit import (
    client_ip,
    enforce_verification_attempt_limit,
    register_verification_send,
)
from app.schemas import (
    ChangePasswordIn,
    EmailIn,
    LoginIn,
    Message,
    RefreshIn,
    RegisterIn,
    ResetPasswordIn,
    TokenIn,
    TokenPair,
    VerifyEmailCodeIn,
)
from app.security import as_utc, burn_password_check, create_access_token, hash_password, verify_password
from app.services import audit, notify_reviewers

router = APIRouter(prefix="/auth", tags=["auth"])

_BAD_LOGIN = HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid e-mail or password")
_BAD_TOKEN = HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid or expired token")
_BAD_CODE = HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid or expired verification code")
_VERIFICATION_GENERIC = Message(
    message="Dacă adresa este eligibilă pentru verificare, vei primi un cod prin e-mail."
)


def _issue_pair(db: Session, user: Profile) -> TokenPair:
    refresh, _ = tokens.issue_refresh(db, user.id, timedelta(days=settings.refresh_token_days))
    return TokenPair(
        access_token=create_access_token(user.id, user.credential.credentials_version),
        refresh_token=refresh,
        account_status=user.account_status,
    )


def _queue_verification_email(background_tasks: BackgroundTasks, user: Profile, code: str,
                              token_id) -> None:
    minutes = settings.verification_code_minutes
    body = (
        f"Salut, {user.first_name}!\n\n"
        f"Codul tău de verificare Overthink este: {code}\n\n"
        f"Codul expiră în {minutes} minute. Dacă nu ai cerut acest cod, ignoră mesajul."
    )
    html = (
        f"<p>Salut, {user.first_name}!</p>"
        f"<p>Codul tău de verificare Overthink este:</p>"
        f"<p style='font-size:32px;font-weight:700;letter-spacing:8px'>{code}</p>"
        f"<p>Codul expiră în {minutes} minute.</p>"
        f"<p>Dacă nu ai cerut acest cod, poți ignora mesajul.</p>"
    )
    background_tasks.add_task(
        send_email_safe,
        user.email,
        "Codul tău de verificare Overthink",
        body,
        html=html,
        idempotency_key=f"verify-email/{token_id}",
    )


@router.post("/register", response_model=Message, status_code=status.HTTP_202_ACCEPTED)
def register(body: RegisterIn, request: Request, background_tasks: BackgroundTasks,
             db: Session = Depends(get_db)):
    email = body.email.lower()
    limit = register_verification_send(db, email, client_ip(request))

    existing = db.scalar(select(Profile).where(Profile.email == email))
    if existing:
        # Registration itself never doubles as "resend". This keeps repeated
        # registration attempts from becoming an e-mail spam endpoint.
        return _VERIFICATION_GENERIC

    user = Profile(
        first_name=body.first_name.strip(),
        last_name=body.last_name.strip(),
        email=email,
        birth_date=body.birth_date,
        school=body.school.strip(),
        locality=body.locality.strip(),
        account_status=AccountStatus.email_unverified.value,
        privacy_notice_version=settings.privacy_policy_version,
        privacy_acknowledged_at=utcnow(),
        credential=AuthCredential(password_hash=hash_password(body.password)),
    )
    db.add(user)
    db.flush()
    audit(db, user.id, "account.registered", "profile", user.id)

    issued = None
    if limit.allowed:
        issued = tokens.issue_verification_code(db, user.id)
    db.commit()

    if issued:
        code, token_row = issued
        _queue_verification_email(background_tasks, user, code, token_row.id)
    return _VERIFICATION_GENERIC


@router.post("/resend-verification", response_model=Message, status_code=status.HTTP_202_ACCEPTED)
def resend_verification(body: EmailIn, request: Request, background_tasks: BackgroundTasks,
                        db: Session = Depends(get_db)):
    email = body.email.lower()
    limit = register_verification_send(db, email, client_ip(request))
    user = db.scalar(select(Profile).where(Profile.email == email))

    if (
        limit.allowed
        and user is not None
        and user.account_status == AccountStatus.email_unverified.value
        and user.credential.email_verified_at is None
    ):
        code, token_row = tokens.issue_verification_code(db, user.id)
        db.commit()
        _queue_verification_email(background_tasks, user, code, token_row.id)

    # Same response whether the account exists, is already verified, is in a
    # soft e-mail cooldown, or a code was actually queued.
    return _VERIFICATION_GENERIC


@router.post("/verify-email", response_model=Message)
def verify_email(body: VerifyEmailCodeIn, request: Request, db: Session = Depends(get_db)):
    email = body.email.lower()
    enforce_verification_attempt_limit(db, email, client_ip(request))

    user = db.scalar(select(Profile).where(Profile.email == email))
    if (
        user is None
        or user.account_status != AccountStatus.email_unverified.value
        or user.credential.email_verified_at is not None
    ):
        raise _BAD_CODE

    row = tokens.consume_verification_code(db, user.id, body.code)
    if row is None:
        db.commit()  # persist failed-attempt counter/invalidation
        raise _BAD_CODE

    user.credential.email_verified_at = utcnow()
    user.account_status = AccountStatus.pending.value
    db.add(MembershipRequest(user_id=user.id, status="pending"))
    audit(db, user.id, "account.email_verified", "profile", user.id)
    db.commit()

    # Reviewer notification is not security-critical for the user's successful
    # verification. Failure to send it must not roll back verification.
    try:
        notify_reviewers(
            db,
            "Cerere nouă de aderare Overthink",
            f"{user.first_name} {user.last_name} a trimis o cerere de aderare.",
        )
    except Exception:
        pass

    return Message(message="E-mail confirmat. Cererea ta așteaptă aprobarea.")


@router.post("/login", response_model=TokenPair)
def login(body: LoginIn, db: Session = Depends(get_db)):
    user = db.scalar(select(Profile).where(Profile.email == body.email.lower()))
    if user is None:
        burn_password_check(body.password)
        raise _BAD_LOGIN
    cred, now = user.credential, utcnow()

    if cred.locked_until and as_utc(cred.locked_until) > now:
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Too many attempts. Try again later.")

    ok, new_hash = verify_password(body.password, cred.password_hash)
    if not ok:
        cred.failed_login_attempts += 1
        if cred.failed_login_attempts >= settings.max_failed_logins:
            cred.locked_until = now + timedelta(minutes=settings.lockout_minutes)
            cred.failed_login_attempts = 0
        db.commit()
        raise _BAD_LOGIN

    if new_hash:
        cred.password_hash = new_hash
    cred.failed_login_attempts, cred.locked_until = 0, None

    if user.account_status == AccountStatus.email_unverified.value:
        db.commit()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "E-mail not verified")
    if user.account_status not in (AccountStatus.pending.value, AccountStatus.active.value):
        db.commit()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account not available")

    pair = _issue_pair(db, user)
    db.commit()
    return pair


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshIn, db: Session = Depends(get_db)):
    row = tokens.lookup_refresh(db, body.refresh_token, lock=True)
    if row is None:
        raise _BAD_TOKEN
    if row.revoked_at is not None:
        if row.replaced_by is not None:
            tokens.revoke_all_refresh(db, row.user_id)
            db.commit()
        raise _BAD_TOKEN
    if as_utc(row.expires_at) <= utcnow():
        raise _BAD_TOKEN
    user = db.get(Profile, row.user_id)
    if user is None or user.account_status not in (AccountStatus.pending.value, AccountStatus.active.value):
        row.revoked_at = utcnow()
        db.commit()
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Account not available")
    pair = _issue_pair(db, user)
    new_row = tokens.lookup_refresh(db, pair.refresh_token)
    row.revoked_at = utcnow()
    row.replaced_by = new_row.id
    row.last_used_at = utcnow()
    db.commit()
    return pair


@router.post("/logout", response_model=Message)
def logout(body: RefreshIn, db: Session = Depends(get_db)):
    row = tokens.lookup_refresh(db, body.refresh_token, lock=True)
    if row and row.revoked_at is None:
        row.revoked_at = utcnow()
        db.commit()
    return Message(message="Deconectat.")


@router.post("/forgot-password", response_model=Message, status_code=status.HTTP_202_ACCEPTED)
def forgot_password(body: EmailIn, background_tasks: BackgroundTasks,
                    db: Session = Depends(get_db)):
    user = db.scalar(select(Profile).where(Profile.email == body.email.lower()))
    if user and user.account_status in (AccountStatus.pending.value, AccountStatus.active.value):
        raw = tokens.issue(
            db,
            user.id,
            TokenPurpose.reset_password.value,
            timedelta(minutes=settings.password_reset_minutes),
        )
        db.commit()
        background_tasks.add_task(
            send_email_safe,
            user.email,
            "Resetare parolă Overthink",
            f"Resetează parola: {settings.app_base_url}/reset-password?token={raw}\n"
            f"Linkul expiră în {settings.password_reset_minutes} de minute.",
            idempotency_key=f"password-reset/{user.id}/{int(utcnow().timestamp())}",
        )
    return Message(message="Dacă există un cont, vei primi un e-mail cu instrucțiuni.")


def _set_password(db: Session, user: Profile, new_password: str) -> None:
    cred = user.credential
    cred.password_hash = hash_password(new_password)
    cred.password_changed_at = utcnow()
    cred.credentials_version += 1
    cred.failed_login_attempts, cred.locked_until = 0, None
    tokens.revoke_all_refresh(db, user.id)


@router.post("/reset-password", response_model=Message)
def reset_password(body: ResetPasswordIn, db: Session = Depends(get_db)):
    row = tokens.consume(db, body.token, TokenPurpose.reset_password.value)
    if row is None:
        raise _BAD_TOKEN
    user = db.get(Profile, row.user_id)
    _set_password(db, user, body.new_password)
    audit(db, user.id, "account.password_reset", "profile", user.id)
    db.commit()
    return Message(message="Parola a fost schimbată. Autentifică-te din nou.")


@router.post("/change-password", response_model=TokenPair)
def change_password(body: ChangePasswordIn, user: Profile = Depends(get_current_user),
                    db: Session = Depends(get_db)):
    ok, _ = verify_password(body.current_password, user.credential.password_hash)
    if not ok:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Current password is incorrect")
    _set_password(db, user, body.new_password)
    audit(db, user.id, "account.password_changed", "profile", user.id)
    pair = _issue_pair(db, user)
    db.commit()
    return pair
