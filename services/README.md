# OVERTHINK APP — baza de date V1

Pachet **executabil** pentru nucleul FastAPI + PostgreSQL. Include schema completă (23 de tabele + o vedere de raportare), prima migrare Alembic, 5 departamente inițiale, configurația Docker, script pentru crearea interactivă a celor **două** conturi de administrator și teste SQL reversibile. Nu conține încă endpointurile de business pentru înregistrare, login, calendar sau pontaj: construim aceste module peste schema stabilită aici.

## 1. Instalare (Windows / macOS / Linux)

**Ai nevoie de:** Docker Desktop sau Docker Engine + Compose, Python 3.11+ și un editor (ex. VS Code/PyCharm). Android Studio nu este necesar pentru această etapă.

1. Extrage arhiva și deschide un terminal în directorul `overthink-backend-v1`.
2. Creează fișierul de configurare:

   - PowerShell: `Copy-Item .env.example .env`
   - macOS / Linux: `cp .env.example .env`

3. Editează `.env`. Înlocuiește `CHANGE_ME_USE_A_LONG_RANDOM_PASSWORD` **în ambele locuri** cu aceeași parolă PostgreSQL, lungă și aleatoare. Dacă parola conține caractere rezervate într-un URL (`@`, `:`, `/`, `%` etc.), encodeaz-o în `DATABASE_URL` sau alege pentru dezvoltare o parolă alfanumerică aleatoare de 32+ caractere. Nu încărca `.env` în Git.
4. Pornește DOAR baza de date:

   ```bash
   docker compose up -d database
   docker compose ps
   ```

5. Creează și activează mediul virtual Python (din directorul rădăcină):

   **PowerShell:**
   ```powershell
   cd services/api
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install -r requirements.txt
   ```
   **macOS / Linux:**
   ```bash
   cd services/api
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r requirements.txt
   ```

6. Aplică **prima migrare Alembic** (din `services/api`):

   ```bash
   python -m alembic upgrade head
   python scripts/check_database.py
   ```

   Scriptul de migrare citește `database/001_initial_schema.sql` și creează automat tabelele + departamentele inițiale. **Nu rula și manual același SQL** dacă ai folosit Alembic; ai duplica schema.

7. Creează manual cele **două conturi inițiale de administrator**:

   ```bash
   python scripts/bootstrap_admin.py
   ```

   Scriptul solicită interactiv două nume, două e-mailuri distincte și parolele (ascunse la tastare). Parolele devin hash-uri Argon2id; sunt stocate doar hash-urile. Bootstrap se poate rula numai dacă nu există deja administratori. E-mailurile administratorilor sunt considerate pre-verificate prin procesul manual: verifică deținerea lor separat înainte de utilizare. Pentru producție, MFA este obligatoriu și trebuie implementat înainte de lansare.

8. Testează aplicația minimă FastAPI:

   ```bash
   uvicorn app.main:app --reload
   ```

   Accesează `http://127.0.0.1:8000/health` sau `http://127.0.0.1:8000/docs`.

## 2. Verifică tabelele în PostgreSQL

Din rădăcina proiectului:

```bash
docker compose exec database psql -U overthink_app -d overthink_app -c '\dt'
docker compose exec database psql -U overthink_app -d overthink_app -c 'SELECT name FROM departments ORDER BY name;'
docker compose exec database psql -U overthink_app -d overthink_app -c 'SELECT * FROM profile_hours_summary;'
```

Pentru un **smoke test SQL** care se încheie prin `ROLLBACK` (rulat **doar în dezvoltare**):

```bash
# Din radacina proiectului, foloseste un terminal cu stdin functional:
docker compose exec -T database psql -v ON_ERROR_STOP=1 -U overthink_app -d overthink_app < database/tests/001_smoke_test.sql
```

Testul acoperă: creditarea minutelor aprobate, anularea (voided), ignorarea pontajelor pending, respingerea intervalelor suprapuse și consumarea unui cod individual. La final nu rămân profiluri sau pontaje fictive.

## 3. Schema și regulile

- `database/001_initial_schema.sql`: schema V1; UUID, FK, `CHECK`, indexuri, exclusivitate pentru ore suprapuse, trigger de contorizare și trigger de consumare a codurilor.
- `database/seeds/002_departments.sql`: cele 5 departamente inițiale, editabile ulterior.
- `database/docs/SCHEMA_GUIDE.md`: descrierea tabelelor, relațiilor și a regulilor ce vor fi verificate în FastAPI.
- `database/docs/ERD.mmd`: diagrama Mermaid pentru schema relațională.
- `services/api/alembic/versions/0001_schema.py`: migrarea inițială.
- `services/api/scripts/check_database.py`: verificarea structurii și reconcilierea cache-ului de ore.

**Reguli de proiectare:** aplicația Flutter NU primește datele de conectare PostgreSQL. Comunică numai cu FastAPI. Înregistrarea normală impune toate câmpurile discutate (nume, prenume, e-mail, parolă și confirmare, data nașterii, liceu, localitate); coloanele DOB/liceu/localitate permit NULL în DB numai pentru conturile inițiale create administrativ. `profiles.email_normalized` este unic; `approved_minutes_cached` este întreținut automat din `time_entries` prin trigger. Confirmarea parolei nu se păstrează.

## 4. Ce NU pretinde schema singură că garantează

Înainte de lansarea efectivă, modulele FastAPI trebuie să implementeze și să testeze:

- Trimiterea/verificarea reală a e-mailurilor, tokenuri aleatorii de unică folosință, resetarea parolei, rate limiting și MFA pentru administratori.
- Tranzițiile legitime între stările `email_unverified` → `pending` → `active` sau `rejected`; doar admin aprobă. Reamintirea la 12 ore, SLA țintă 48 ore.
- Controlul complet al drepturilor (roluri, `permission_grants`, domeniu de aplicare); codul aplicației nu poate acorda drepturi prin simpla schimbare a interfeței.
- **Plafonul cumulat de 12 ore/zi**, luând în calcul `pending + approved`, inclusiv împărțirea intervalelor peste miezul nopții în `Europe/Bucharest`. Se face în tranzacție după blocarea rândului de profil (`SELECT ... FOR UPDATE`) și se testează cu solicitări concurente. Schema garantează numai maximul pe o singură înregistrare și suprapunerile cu interval cunoscut.
- O activitate creditată manual și apoi prin cod NU trebuie să fie creditată dublu; FastAPI compară participările și istoricul. Codurile fără ore exacte nu pot avea verificare anti-suprapunere temporală.
- La răscumpărarea unui cod: se verifică `assigned_user_id`, participarea/prezența, expirarea și limitele. Triggerul DB asigură atomic consumarea și previne refolosirea.
- Ștergere și anonimizare potrivit unei politici de retenție. **Nu** se păstrează parole decriptabile, tokenuri brute, linkuri secrete sau detalii sensibile în audit/outbox.

## 5. Pentru un server real

Docker Compose expune PostgreSQL **doar pe `127.0.0.1`**, ca măsură de protecție a mediului local. În producție folosește o bază gestionată sau rețea privată, TLS, utilizatori cu drepturi minime, backupuri criptate cu teste de restaurare, secrete gestionate securizat și migrații aplicate într-un proces controlat. Nu publica portul 5432 și nu pune parola DB în Flutter.

**Nu rula `docker compose down -v`** pe o bază ale cărei date vrei să le păstrezi: `-v` elimină volumul cu datele.
