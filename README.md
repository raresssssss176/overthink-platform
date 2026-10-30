# Overthink

Platforma clubului de film Overthink: aplicația mobilă Flutter (Android) și backend-ul FastAPI cu PostgreSQL.

## Structura proiectului

```
overthink-platform/
├── apps/mobile/            # Aplicația Flutter
└── services/
    ├── .env                
    ├── .env.example        # Șablon pentru .env
    ├── docker-compose.yml  # PostgreSQL (și Mailpit pentru teste de e-mail)
    └── services/api/       # Backend-ul FastAPI + Alembic
```

Doar baza de date rulează în Docker. Backend-ul rulează direct cu Python pe calculatorul tău.

## Cerințe

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (pornit înainte de orice comandă Docker)
- Python 3.13
- Flutter SDK 3.47 sau mai nou, cu Android Studio și un emulator (sau un telefon)
- Git

## 1. Clonează repo-ul

```powershell
git clone https://github.com/raresssssss176/overthink-platform.git
cd overthink-platform
```

## 2. Creează fișierul .env

Fișierul `.env` se află în folderul `services`, nu în `services\services\api`.

```powershell
cd services
copy .env.example .env
```

Deschide `services\.env` și completează valorile (vezi tabelul de mai jos). Generează secretele cu:

```powershell
py -3.13 -c "import secrets; print(secrets.token_urlsafe(48))"
```

Rulează comanda de două ori și folosește rezultate diferite pentru `JWT_SECRET` și `AUTH_PEPPER_SECRET`.

Dacă parola din `POSTGRES_PASSWORD` conține caractere speciale (`@ : / % #`), în `DATABASE_URL` trebuie să fie codificate în URL. Cel mai simplu este să alegi o parolă formată doar din litere și cifre.

## 3. Pornește baza de date cu Docker

Din folderul `services`:

```powershell
cd C:\Users\<utilizator>\Desktop\overthink-platform\services
docker compose up -d database
docker compose ps
```

Aștepți până când `database` are statusul `healthy` (de obicei 10–20 de secunde). Prima pornire descarcă imaginea `postgres:17`.

## 4. Instalează dependențele backend-ului

Din folderul API:

```powershell
cd C:\Users\<utilizator>\Desktop\overthink-platform\services\services\api
py -3.13 -m pip install -r requirements.txt
```

## 5. Aplică migrările bazei de date

Din același folder `services\services\api`:

```powershell
py -3.13 -m alembic upgrade head
py -3.13 -m alembic current
```

`current` trebuie să afișeze ultima migrare (`0009_department_join_requests (head)`).

Migrările creează toate tabelele, rolurile, permisiunile și cele șase departamente.

## 6. Creează administratorii inițiali

Rulează o singură dată, din același folder:

```powershell
py -3.13 scripts\bootstrap_admin.py
```

Scriptul cere pentru fiecare admin: prenume, nume, email și o parolă de cel puțin 14 caractere. Adresele trebuie să fie reale, deoarece sunt marcate ca verificate fără cod. Scriptul refuză să ruleze dacă există deja administratori.

## 7. Pornește backend-ul

```powershell
py -3.13 -m uvicorn app.main:app --reload
```

Verificări:
- `http://127.0.0.1:8000/health` returnează `{"status": "ok"}`
- `http://127.0.0.1:8000/docs` afișează documentația API

## 8. Pornește aplicația Flutter

În alt terminal, din `apps\mobile`:

```powershell
cd C:\Users\<utilizator>\Desktop\overthink-platform\apps\mobile
flutter pub get
flutter run
```

Pentru emulatorul Android, aplicația folosește implicit `http://10.0.2.2:8000`, adică `127.0.0.1` de pe calculator. Pentru telefon fizic, vezi documentația din `apps/mobile/README.md`.

## Variabilele din `services\.env`

### Baza de date și Docker

| Variabilă | Obligatorie | Descriere |
|---|---|---|
| `POSTGRES_DB` | Da | Numele bazei de date |
| `POSTGRES_USER` | Da | Utilizatorul PostgreSQL |
| `POSTGRES_PASSWORD` | Da | Parola PostgreSQL. Folosită de Docker la creare |
| `POSTGRES_PORT` | Nu (`5432`) | Portul publicat pe `127.0.0.1` |
| `DATABASE_URL` | Da | Forma `postgresql+psycopg://USER:PAROLA@127.0.0.1:PORT/BAZA`. Trebuie să se potrivească cu valorile de mai sus |

### Aplicație și securitate

| Variabilă | Obligatorie | Descriere |
|---|---|---|
| `ENV` | Nu (`dev`) | `dev` sau `prod`. În `prod` e-mailul trebuie să fie `resend` |
| `JWT_SECRET` | Da | Cheia pentru token-urile JWT. Minimum 32 de caractere |
| `AUTH_PEPPER_SECRET` | Da | Secret adăugat la parole înainte de hash. Minimum 32 de caractere. Nu-l schimba după ce ai utilizatori |
| `APP_BASE_URL` | Nu | Adresa API-ului, folosită în e-mailuri |
| `PRIVACY_POLICY_VERSION` | Nu | Versiunea informării de confidențialitate acceptate la înregistrare |

### Token-uri și autentificare

| Variabilă | Implicit | Descriere |
|---|---|---|
| `ACCESS_TOKEN_MINUTES` | `15` | Durata token-ului de acces |
| `REFRESH_TOKEN_DAYS` | `30` | Durata token-ului de reîmprospătare |
| `MAX_FAILED_LOGINS` | `5` | Câte parole greșite sunt permise înainte de blocare |
| `LOCKOUT_MINUTES` | `15` | Cât durează blocarea după parole greșite |
| `PASSWORD_RESET_MINUTES` | `30` | Valabilitatea linkului de resetare a parolei |

### Coduri de verificare a e-mailului

| Variabilă | Implicit | Descriere |
|---|---|---|
| `VERIFICATION_CODE_MINUTES` | `10` | Valabilitatea codului |
| `VERIFICATION_CODE_MAX_ATTEMPTS` | `5` | Încercări greșite pentru un cod |
| `VERIFICATION_RESEND_SECONDS` | `60` | Pauza minimă între două trimiteri |
| `VERIFICATION_SEND_WINDOW_MINUTES` | `60` | Fereastra pentru limita de trimiteri |
| `VERIFICATION_EMAIL_SEND_LIMIT` | `5` | Trimiteri permise pe o adresă în fereastră |
| `VERIFICATION_IP_SEND_LIMIT` | `20` | Trimiteri permise pe o adresă IP în fereastră |
| `VERIFICATION_ATTEMPT_WINDOW_MINUTES` | `15` | Fereastra pentru limita de încercări |
| `VERIFICATION_EMAIL_ATTEMPT_LIMIT` | `10` | Încercări permise pe o adresă în fereastră |
| `VERIFICATION_IP_ATTEMPT_LIMIT` | `30` | Încercări permise pe o adresă IP în fereastră |

### E-mail

| Variabilă | Implicit | Descriere |
|---|---|---|
| `EMAIL_BACKEND` | `resend` | `resend` trimite e-mailuri reale. `console` afișează codurile în terminalul uvicorn, util în dezvoltare |
| `RESEND_API_KEY` | — | Cheia API Resend. Obligatorie dacă `EMAIL_BACKEND=resend` |
| `RESEND_FROM` | `Overthink <onboarding@resend.dev>` | Adresa expeditorului. Adresa de test funcționează doar către emailul contului Resend |

### Aprobări

| Variabilă | Implicit | Descriere |
|---|---|---|
| `REVIEW_DEADLINE_HOURS` | `48` | Termenul în care un admin trebuie să revizuiască o cerere |
| `REMINDER_COOLDOWN_HOURS` | `12` | Pauza între două reamintiri |
| `MAX_REMINDERS` | `5` | Câte reamintiri se pot trimite pentru o cerere |

### Exemplu de `services\.env` pentru dezvoltare

```
POSTGRES_DB=overthink_app
POSTGRES_USER=overthink_app
POSTGRES_PASSWORD=parola_ta_lunga
POSTGRES_PORT=5432
DATABASE_URL=postgresql+psycopg://overthink_app:parola_ta_lunga@127.0.0.1:5432/overthink_app

ENV=dev
JWT_SECRET=<generat cu secrets.token_urlsafe(48)>
AUTH_PEPPER_SECRET=<alt secret generat>
APP_BASE_URL=http://127.0.0.1:8000

EMAIL_BACKEND=console
```

Cu `EMAIL_BACKEND=console` nu ai nevoie de `RESEND_API_KEY`. Codurile de verificare apar în terminalul uvicorn.

## Comenzi Docker utile

Toate comenzile se rulează din folderul `services`.

```powershell
docker compose up -d database      # pornește baza de date în fundal
docker compose ps                  # starea containerelor
docker compose logs -f database    # jurnalul bazei de date
docker compose stop database       # oprește, păstrează datele
docker compose start database      # pornește din nou
docker compose down                # oprește și șterge containerele, păstrează datele
```

Pentru a șterge toate datele din baza de date (ireversibil):

```powershell
docker compose down -v
```

După `down -v` trebuie să rulezi din nou pașii 3, 5 și 6.

Serviciul `mailpit` există în compose pentru testarea e-mailurilor. Interfața lui este pe `http://127.0.0.1:8025`. Pornește-l cu `docker compose up -d mailpit`, dacă ai nevoie.

## Conectarea la baza de date

Cu psql din container:

```powershell
docker compose exec database psql -U <POSTGRES_USER> -d <POSTGRES_DB>
```

Cu un client grafic (DBeaver, pgAdmin): host `localhost`, port `POSTGRES_PORT`, utilizator, parolă și bază de date din `.env`.

## Probleme frecvente

**`docker compose` spune că variabila lipsește.** Compose cere `POSTGRES_DB`, `POSTGRES_USER` și `POSTGRES_PASSWORD` în `services\.env`. Verifică că fișierul există și că nu are spații în jurul semnului `=`.

**`password authentication failed` la migrare sau la pornirea API-ului.** `DATABASE_URL` nu corespunde cu `POSTGRES_USER` și `POSTGRES_PASSWORD`. Dacă ai schimbat parola după prima pornire, volumul vechi păstrează parola veche. Soluția este `docker compose down -v` și repetarea pașilor 3, 5 și 6.

**`RuntimeError: JWT_SECRET must contain at least 32 characters`.** Secretul este prea scurt sau lipsește. Generează unul nou cu comanda de mai sus.

**Migrarea se blochează.** Baza de date nu rulează. Verifică `docker compose ps`, apoi `docker compose logs database`.

**Telefonul nu vede API-ul.** Vezi documentația din `apps/mobile/README.md`.

## Securitate

- Fișierul `services\.env` conține secrete și **nu trebuie urcat pe GitHub**. Verifică că `.gitignore` îl exclude.
- Dacă un secret a ajuns în istoricul Git, schimbă-l imediat: `JWT_SECRET`, `AUTH_PEPPER_SECRET`, parola bazei de date și cheia Resend.
- Portul bazei de date este legat doar la `127.0.0.1`, deci nu este accesibil din rețea.