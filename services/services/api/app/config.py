"""Application settings loaded from the backend root .env file."""
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

ROOT = Path(__file__).resolve().parents[3]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(ROOT / ".env"), extra="ignore")

    env: str = "dev"
    database_url: str

    jwt_secret: str
    jwt_algorithm: str = "HS256"
    auth_pepper_secret: str

    app_base_url: str = "http://127.0.0.1:8000"

    email_backend: str = "resend"
    resend_api_key: str | None = None
    resend_from: str = "Overthink <onboarding@resend.dev>"

    access_token_minutes: int = 15
    refresh_token_days: int = 30

    verification_code_minutes: int = 10
    verification_code_max_attempts: int = 5
    verification_resend_seconds: int = 60
    verification_send_window_minutes: int = 60
    verification_email_send_limit: int = 5
    verification_ip_send_limit: int = 20
    verification_attempt_window_minutes: int = 15
    verification_email_attempt_limit: int = 10
    verification_ip_attempt_limit: int = 30

    password_reset_minutes: int = 30
    max_failed_logins: int = 5
    lockout_minutes: int = 15
    reminder_cooldown_hours: int = 12
    max_reminders: int = 5
    review_deadline_hours: int = 48
    privacy_policy_version: str = "2026-10-01"


settings = Settings()

if len(settings.jwt_secret) < 32:
    raise RuntimeError("JWT_SECRET must contain at least 32 characters (configure services/.env)")
if len(settings.auth_pepper_secret) < 32:
    raise RuntimeError("AUTH_PEPPER_SECRET must contain at least 32 characters (configure services/.env)")
if settings.email_backend == "resend" and not settings.resend_api_key:
    raise RuntimeError("RESEND_API_KEY is required when EMAIL_BACKEND=resend")
if settings.env == "prod" and settings.email_backend != "resend":
    raise RuntimeError("Production e-mail delivery must use EMAIL_BACKEND=resend")
