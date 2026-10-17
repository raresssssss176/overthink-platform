# Overthink Auth 1.1 — Resend + e-mail verification code

## UX decision
V1 verifies e-mail with a six-digit code entered in the mobile app. This avoids hosting a web verification page and avoids Android App Links / iOS Universal Links before the mobile client is ready.

Flow:

1. `POST /auth/register`
2. App opens the Verify E-mail screen.
3. Resend delivers a 6-digit code.
4. `POST /auth/verify-email` with `{ "email": "...", "code": "123456" }`.
5. Account becomes `pending` and waits for admin approval.
6. `POST /auth/resend-verification` is available when the UI resend countdown expires.

## Security rules

- Code TTL: 10 minutes.
- Maximum 5 wrong attempts per issued code; then it is invalidated.
- Issuing a new code invalidates all older unused verification codes.
- The database never stores the six-digit code. It stores a server-keyed HMAC digest that includes the token UUID and user UUID.
- Register and resend return the same generic message whether the account exists or not.
- Send requests: 60-second e-mail cooldown, maximum 5/hour per e-mail digest, maximum 20/hour per IP digest.
- Verification attempts: maximum 10/15 min per e-mail digest and 30/15 min per IP digest, in addition to the 5-attempt per-code limit.
- Raw IP addresses are not stored in the rate-limit table; only keyed digests are stored.
- Do not trust `X-Forwarded-For` manually. When deploying behind a reverse proxy, configure Uvicorn's trusted proxy options so `request.client.host` is trustworthy.

## Resend configuration

Add to your real `services/.env` (do not commit it):

```env
EMAIL_BACKEND=resend
RESEND_API_KEY=re_...
RESEND_FROM=Overthink <onboarding@resend.dev>
AUTH_PEPPER_SECRET=<a different 32+ character random secret>
```

Generate the pepper with:

```powershell
py -c "import secrets; print(secrets.token_urlsafe(48))"
```

For real users, replace `onboarding@resend.dev` with an address on a domain verified in Resend.

## Apply database migration

From `overthink-platform/services/services/api`:

```powershell
py -m pip install -r requirements.txt
py -m alembic upgrade head
```

The new head should be `0003_email_verification_security`.

## Start the API

```powershell
py -m uvicorn app.main:app --reload
```

## Test with Swagger

1. `POST /auth/register`
2. Read the code from the actual inbox / Resend dashboard.
3. `POST /auth/verify-email`:

```json
{
  "email": "user@example.com",
  "code": "123456"
}
```

4. Confirm `/membership/status` after login reports the account as pending.

## Repository cleanup found during review

The current repository contains an accidental duplicate subtree:

`services/services/services/`

The live API is under:

`services/services/api/`

After confirming there are no unique files you need in the duplicate tree, remove the duplicate subtree. The repository also contains duplicate `services/services/docker-compose.yml` and `services/services/.env.example`; the canonical backend-level versions should be `services/docker-compose.yml` and `services/.env.example`.

## One-time repository cleanup

From the repository root, after making a backup/commit, the accidental duplicate subtree can be removed:

```powershell
Remove-Item -Recurse -Force .\services\services\services
Remove-Item -Force .\services\services\docker-compose.yml
Remove-Item -Force .\services\services\.env.example
```

`services/services/AUTH_INTEGRATION.md` is an old integration note and can also be removed once this Auth 1.1 document is committed.

The root `.idea` directory is currently tracked by Git. The patch adds a root `.gitignore`; remove the already tracked IDE files once with:

```powershell
git rm -r --cached .idea
git add .gitignore
git commit -m "Ignore local IDE files"
```

Do not commit or share `services/.env`.
