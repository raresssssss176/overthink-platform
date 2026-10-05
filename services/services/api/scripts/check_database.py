"""Verifică existența tabelelor, indexurilor-cheie și egalitatea totalurilor de ore."""
import os
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[3]
load_dotenv(ROOT / '.env')
url=os.environ.get('DATABASE_URL')
if not url:
    raise SystemExit('Lipsește DATABASE_URL în .env')
required = {
    'departments','profiles','auth_credentials','auth_tokens','auth_sessions',
    'membership_requests','member_departments','teams','team_members','user_roles',
    'projects','permission_grants','project_members','activities','activity_departments',
    'activity_teams','activity_participants','activity_codes','time_entries',
    'time_entry_feedback','user_settings','audit_logs','notification_outbox'
}
engine=create_engine(url,pool_pre_ping=True)
with engine.connect() as c:
    names=set(c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public'")).scalars().all())
    missing=required-names
    if missing:
        raise SystemExit(f'LIPSESC TABELELE: {", ".join(sorted(missing))}')
    print(f'OK: {len(required)} tabele principale.')
    departments=c.execute(text('SELECT name FROM departments ORDER BY name')).scalars().all()
    print(f'Departamente inițiale ({len(departments)}): {", ".join(departments)}')
    diff=c.execute(text('SELECT COUNT(*) FROM profile_hours_summary WHERE cache_difference_minutes <> 0')).scalar_one()
    if diff:
        raise SystemExit(f'NECONCORDANȚĂ: {diff} profiluri au totaluri de ore incorecte!')
    print('OK: totalurile din profil coincid cu pontajele aprobate.')
    constraint=c.execute(text("SELECT 1 FROM pg_constraint WHERE conname='ex_time_entries_active_overlap'")).scalar_one_or_none()
    if not constraint:
        raise SystemExit('LIPSEȘTE constrângerea anti-suprapunere a intervalelor!')
    print('OK: verificarea de suprapunere a intervalelor este instalată.')
