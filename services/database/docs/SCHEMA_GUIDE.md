# Baza de date `overthink_app` — modelul V1

## Principii

- PostgreSQL 17, chei primare UUID; toate momentele sunt `timestamptz`, preferabil furnizate în UTC de backend. Data de raportare se interpretează în `Europe/Bucharest`.
- Parolele sunt doar hash Argon2id în `auth_credentials`. Tokenurile/codurile din DB sunt numai digesturi (sau HMAC pentru codurile de prezentare, cu cheia pe server), nu valori brute.
- `profiles.id` este identificatorul comun al utilizatorului pentru toate modulele. Fotografia de profil este o cheie de obiect privat, nu un BLOB SQL sau URL public permanent.
- `profiles.primary_department_id` arată departamentul principal; `member_departments` păstrează apartenențe **suplimentare**. Nu este necesară duplicarea departamentului principal în tabelul suplimentar.

## Inventar de tabele (23)

| Zonă | Tabel | Scop |
|---|---|---|
| Organizare | `departments` | Departamentele clubului. |
| Identitate | `profiles` | Nume/prenume, email unic, DOB, liceu, localitate, status, departament principal, avatar, minute aprobate. |
| Identitate | `auth_credentials` | Hash Argon2id, e-mail verificat, versiunea parolei. |
| Identitate | `auth_tokens` | Tokenuri cu digest/expirare pentru e-mail, resetare, schimbare adresă. |
| Identitate | `auth_sessions` | Refresh token-uri hash-uite și revocabile. |
| Aderare | `membership_requests` | Cereri, verificare admin, motiv, contor de reamintiri. |
| Organizare | `member_departments` | Departamente adiționale. |
| Organizare | `teams` | Echipe în interiorul departamentelor. |
| Organizare | `team_members` | Membri ai echipelor, funcții, atribuire. |
| Acces | `user_roles` | `volunteer`, `coordinator`, `admin`. |
| Proiecte | `projects` | Identitate proiect pentru activități/pontaj; extindere ulterioară cu producții. |
| Acces | `permission_grants` | Permisiuni granulare pe club/departament/echipă/proiect, revocabile. |
| Proiecte | `project_members` | Membri, responsabilități. |
| Calendar | `activities` | Activități publicabile cu doar titlu; dată, timp, locație, descriere sunt opționale. |
| Calendar | `activity_departments` | Vizibilitate/relevanță multi-departament. |
| Calendar | `activity_teams` | Vizibilitate/relevanță multi-echipă. |
| Calendar | `activity_participants` | Atribuire, confirmare și prezență (NU aprobă ore automat). |
| Pontaj | `activity_codes` | Un cod individual / activitate / membru, digest unic, durată, rol, expirare. |
| Pontaj | `time_entries` | Pontaj manual sau prin cod, minute, activitate, rol, status, verificator. |
| Pontaj | `time_entry_feedback` | Feedbackul coordonatorilor/adminilor, inclusiv mai multe mesaje per pontaj. |
| Preferințe | `user_settings` | Temă și notificări. |
| Audit | `audit_logs` | Evenimente administrative, fără parole/tokenuri. |
| Notificări | `notification_outbox` | Evenimente pentru un worker e-mail, fără secrete brute în payload. |

### Vedere raportare

`profile_hours_summary`: `approved_minutes`, `pending_minutes`, valoarea cache din profil și `cache_difference_minutes`. Dacă diferența este nenulă, **nu** afișa un total ca fiind oficial înainte de investigare.

## Stări și fluxuri

**Cont:** `email_unverified` → `pending` → `active` / `rejected`, apoi posibil `suspended` / `deleted`.

**Cerere:** `submitted` → `pending` → `approved` / `rejected`; un singur request deschis deodată per membru. `last_reminder_at`/`reminder_count` sunt doar evidență; FastAPI verifică 12 ore între reamintiri.

**Pontaj:** manual: `pending` → `approved` / `needs_changes` / `rejected`; o corectură administrativă după aprobare poate marca `voided`, păstrând istoricul. Prin cod: creat direct `approved`, poate fi ulterior anulat (`voided`), dar codul rămâne consumat.

**Calendar:** `draft` / `published` / `cancelled` / `completed`. Dacă `starts_at` este NULL, activitatea intră la „În curs de programare”. `ends_at` nu poate exista fără `starts_at`; locația și descrierea rămân opționale.

**Participarea:** `assigned` / `confirmed` / `withdrawn` este diferită de prezență (`unknown` / `present` / `absent` / `excused`).

## Protecții implementate efectiv în SQL

1. Chei străine și unicitate (email normalizat, o singură cerere deschisă, o singură atribuire a unui cod/membru/activitate, o singură utilizare de cod într-un pontaj).
2. `CHECK` pentru statusuri, durate 1..720 minute, perioade, necesitatea intervalului și a descrierii la pontajul manual; potrivirea duratei cu intervalul exact.
3. FK compus pe cod/membru/activitate/data/durata: un client nu poate utiliza un cod emis altei persoane sau pentru altă durată.
4. Trigger: consumă codul numai dacă este nefolosit și neexpirat, în aceeași tranzacție cu pontajul automat.
5. Constrângere PostgreSQL `EXCLUDE USING gist` (extensia `btree_gist`) contra suprapunerii intervalelor cunoscute din pontaje pending/approved ale aceluiași membru.
6. Triggerul `overthink_sync_approved_minutes()` actualizează atomic totalul de minute în profil la inserare, corecție, anulare sau ștergere a pontajului.
7. `permission_grants` păstrează cheile străine ale țintei concrete, nu un `scope_id` arbitrar, imposibil de validat.

## Verificări obligatorii în serviciile FastAPI, încă neimplementate

- La sign up, `birth_date`, `school`, `locality`, informarea de confidențialitate și confirmarea parolei sunt obligatorii; excepția structurală (NULL la DOB/liceu/localitate) există pentru administratorii creați prin bootstrap. Protecții adaptate minorilor înainte de producție.
- Tranziții de stare și verificarea reală a controlului adresei de e-mail.
- `approved_minutes_cached` nu se modifică prin API. Coordonatorul nu își aprobă propriul pontaj (SQL CHECK blochează și auto-review pentru manual).
- Plafonul **cumulat** de 12 ore pe **fiecare** dată locală, incluzând `pending + approved`, cu intervale care pot traversa miezul nopții. Pentru coduri fără interval temporal, alocă toate minutele în `activity_codes.work_date`. Folosește tranzacție și blochează rândul de profil înainte de calcul/insert pentru concurență.
- Controlul permisiunilor la toate citirile/scrierile: doar cei doi administratori inițiali sunt bootstrap-uiți direct, granturile coordinatorilor trebuie autorizate explicit.
- Codurile sunt generate cu entropie ridicată (minimum 128 biți), nu 6–8 caractere ghicibile; se stochează doar digest/HMAC și se comunică pe canal securizat. Verificarea prezenței pentru activitatea asociată se face în serviciu.
- Fără dublă creditare manual + cod a aceleiași participări; exclusivitatea intervalelor ajută numai când intervalele sunt cunoscute.
- Tokenurile de resetare/verificare nu intră în `notification_outbox.payload_safe_json` necriptate. Dacă se folosește outbox pentru linkurile cu secrete, payloadul trebuie criptat separat sau refăcut protocolul, cu TTL scurt.
- Accesul direct la DB va fi limitat, migrațiile fiind executate de un cont cu privilegii separate în producție. Nu da aplicației mobile user/parolă PostgreSQL.
