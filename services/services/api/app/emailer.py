"""Transactional e-mail delivery.

Resend is the production/default backend. A console backend is kept only for
local tests that deliberately do not send real e-mail.
"""
import logging

import resend

from app.config import settings

log = logging.getLogger("overthink.email")


class EmailDeliveryError(RuntimeError):
    pass


def send_email(
    to: str,
    subject: str,
    body: str,
    *,
    html: str | None = None,
    idempotency_key: str | None = None,
) -> str | None:
    if settings.email_backend == "console" and settings.env != "prod":
        log.warning("DEV EMAIL to=%s subject=%s\n%s", to, subject, body)
        return None

    if settings.email_backend != "resend":
        raise EmailDeliveryError("Invalid EMAIL_BACKEND")

    resend.api_key = settings.resend_api_key
    params: resend.Emails.SendParams = {
        "from": settings.resend_from,
        "to": [to],
        "subject": subject,
        "text": body,
    }
    if html:
        params["html"] = html

    try:
        response = resend.Emails.send(params)
    except resend.exceptions.ResendError as exc:
        raise EmailDeliveryError("Resend could not deliver the message") from exc

    # The SDK response is dict-like in current versions.
    try:
        return response.get("id")  # type: ignore[union-attr]
    except AttributeError:
        return getattr(response, "id", None)


def send_email_safe(*args, **kwargs) -> None:
    """Best-effort send for background/post-commit notifications.

    Never logs the message body, API key, OTP or reset token.
    """
    try:
        send_email(*args, **kwargs)
    except Exception:
        log.exception("Transactional e-mail delivery failed")
