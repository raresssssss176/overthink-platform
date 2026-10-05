# Integrare Register/Login peste schema EXISTENTĂ

Această variantă pleacă de la proiectul ORIGINAL din stânga. Nu schimbă volumul Docker, conturile admin, schema inițială sau configurația PostgreSQL.

## Copiere sigură
1. Fă backup la proiectul local și la datele PostgreSQL. **NU șterge** originalul până nu testezi.
2. Copiază conținutul arhivei integrate în proiectul existent, păstrând fișierul local `.env` (nu este inclus în arhivă).
3. Păstrează parola existentă din `.env`; adaugă manual noile variabile din `.env.example` (ENV, JWT_SECRET, APP_BASE_URL, EMAIL_BACKEND, SMTP_HOST, SMTP_PORT, EMAIL_FROM, PRIVACY_POLICY_VERSION).
4. Folosește fișierul docker-compose.yml integrat, care păstrează serviciul `database` PostgreSQL 17 și volumul `overthink_pgdata` și adaugă serviciul `mailpit`. **Nu folosi** docker-compose.yml din overthink-api.zip: acesta pornește altă bază (postgres:16, serviciu db, volum pgdata, utilizator overthink).
5. Din rădăcina ORIGINALULUI:

```powershell
docker compose config --quiet
docker compose up -d database mailpit
docker compose ps
cd services/api
py -m pip install -r requirements.txt
py -m alembic current
py -m alembic upgrade head
py scripts/check_database.py
py -m uvicorn app.main:app --reload
```

Swagger: http://127.0.0.1:8000/docs ; inbox Mailpit: http://127.0.0.1:8025

## IMPORTANT despre e-mail
Cu EMAIL_BACKEND=smtp, linkul de verificare apare în Mailpit. Linkul din e-mail este o pagină web de exemplu; în V1 copiezi valoarea token=... și o trimiți prin POST /auth/verify-email din Swagger.

## Ce am adaptat din noua arhivă
- Database session folosește ORIGINALUL `app/db/session.py` și root `.env`.
- ORM-ul are doar tabelele de autentificare deja existente (`primary_department_id`, `profile_photo_key`, `token_digest`, `membership_requests.status`, `decision_reason`, `audit_logs.metadata_safe_json`).
- `auth_sessions` este folosit pentru refresh token; `auth_tokens` numai pentru `verify_email` și `reset_password`.
- Adminii existenți sunt detectați prin `user_roles.role='admin'`, fără a recrea conturi.
- Consimțământul pentru informarea de confidențialitate folosește `profiles.privacy_notice_version` + `privacy_acknowledged_at`, nu un tabel inexistent `consent_records`.
- Adăugată DOAR migrarea `0002_auth_lockout.py` cu `auth_credentials.locked_until`.
- `scripts/bootstrap_admin.py` rămâne cel original; NU îl rula din nou.

## Testare manuală, în această ordine
1. Login cu un admin existent: POST /auth/login → status active, access_token.
2. POST /auth/register cu voluntar nou → verifică Mailpit.
3. POST /auth/verify-email {"token":"..."} → cererea devine pending.
4. Login voluntar → returnează status pending. Nu are acces în /admin.
5. Authorize cu access_token-ul adminului în Swagger; GET /admin/membership-requests.
6. POST /admin/membership-requests/{id}/approve.
7. Login voluntar → status active; GET /users/me.
8. Verifică limitele de 12 ore pentru reamintire și resetarea parolei.

## Limitări înainte de publicare
- Acesta este un patch de dezvoltare; trebuie validat prin teste de integrare pe propria bază PostgreSQL.
- Nu există încă interfața Flutter pentru confirmarea e-mailului; backendul expune endpointul.
- SMTP configurat către Mailpit este doar pentru testare locală, nu pentru trimitere efectivă către utilizatori.
- Revizuiește protecția datelor minorilor și adaugă MFA pentru administratori înainte de lansare.

## Copiere recomandată: arhiva patch-only

Dacă folosești `overthink-auth-patch-only.zip`, extrage arhiva și copiază **conținutul directorului `patch/`** peste rădăcina proiectului original, acceptând unirea directoarelor și înlocuirea doar a fișierelor cu nume identic. Nu copia `overthink-api.zip` brut!

### Fișiere NOI
- `services/api/app/config.py`
- `services/api/app/models.py`
- `services/api/app/schemas.py`
- `services/api/app/security.py`
- `services/api/app/emailer.py`
- `services/api/app/tokens.py`
- `services/api/app/deps.py`
- `services/api/app/services.py`
- `services/api/app/routers/{__init__,auth,users,admin}.py`
- `services/api/alembic/versions/0002_auth_lockout.py`
- `services/api/tests/test_auth_unit.py`
- `AUTH_INTEGRATION.md`

### Fișiere ÎNLOCUITE/ACTUALIZATE
- `services/api/app/main.py`
- `services/api/app/db/__init__.py` (doar export pentru originalul `session.py`)
- `services/api/requirements.txt` (dependințele vechi păstrate + cele noi)
- `docker-compose.yml` (păstrează `database` și `overthink_pgdata`; adaugă `mailpit`)
- `.env.example` (exemplu fără secrete reale; NU este `.env`)

### Fișiere care NU se ating
- `.env` original (nu se află în patch; doar se adaugă variabile manual)
- `database/`
- `services/api/alembic/env.py` și `alembic.ini`
- `services/api/alembic/versions/0001_schema.py`
- `services/api/app/db/session.py`
- `services/api/scripts/bootstrap_admin.py` și `check_database.py`

Nu mai rula `bootstrap_admin.py`; adminii existenți sunt citiți prin `user_roles`.
