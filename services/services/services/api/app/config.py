"""Read the ORIGINAL project root/.env, not services/api/.env."""
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict
ROOT = Path(__file__).resolve().parents[3]

class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=str(ROOT / '.env'), extra='ignore')
    env: str = 'dev'
    database_url: str
    jwt_secret: str
    jwt_algorithm: str = 'HS256'
    app_base_url: str = 'http://127.0.0.1:8000'
    email_backend: str = 'console'
    smtp_host: str = '127.0.0.1'
    smtp_port: int = 1025
    email_from: str = 'office@overthink.local'
    access_token_minutes: int = 15
    refresh_token_days: int = 30
    email_verify_hours: int = 24
    password_reset_minutes: int = 30
    max_failed_logins: int = 5
    lockout_minutes: int = 15
    reminder_cooldown_hours: int = 12
    max_reminders: int = 5
    review_deadline_hours: int = 48
    privacy_policy_version: str = '2026-10-01'
settings = Settings()
if len(settings.jwt_secret) < 32:
    raise RuntimeError('JWT_SECRET must contain at least 32 characters (configure root/.env)')
if settings.env == 'prod' and settings.email_backend == 'console':
    raise RuntimeError('EMAIL_BACKEND=console is only allowed for local development')
