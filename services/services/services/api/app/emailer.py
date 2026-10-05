"""Local console or Mailpit SMTP. Never use console backend in production."""
import logging
import smtplib
from email.message import EmailMessage
from app.config import settings
log = logging.getLogger('overthink.email')

def send_email(to: str, subject: str, body: str) -> None:
    if settings.email_backend == 'console' and settings.env != 'prod':
        log.warning('DEV EMAIL to=%s subject=%s\n%s', to, subject, body)
        return
    if settings.email_backend != 'smtp':
        raise RuntimeError('Invalid EMAIL_BACKEND')
    msg = EmailMessage()
    msg['From'] = settings.email_from
    msg['To'] = to
    msg['Subject'] = subject
    msg.set_content(body)
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
        smtp.send_message(msg)
