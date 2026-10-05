"""Creează EXACT două conturi de admin, interactiv. Rulează după migrarea inițială.

Nu se stochează niciodată parole în fișiere, cod sau argumentele liniei de comandă.
E-mailurile introduse trebuie verificate de operator printr-un canal independent;
bootstrap marchează e-mailul ca verificat deoarece acesta este provisioning manual, de încredere.
"""
import os
import re
import sys
from getpass import getpass
from pathlib import Path

from argon2 import PasswordHasher, Type
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[3]
load_dotenv(ROOT / '.env')
url = os.getenv('DATABASE_URL')
if not url:
    raise SystemExit('Lipsește DATABASE_URL în .env')

ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4, hash_len=32, salt_len=16, type=Type.ID)


def collect_admin(position: int) -> dict[str,str]:
    print(f'\n=== Administrator {position}/2 ===')
    first_name = input('Prenume: ').strip()
    last_name = input('Nume: ').strip()
    email = input('E-mail (verificat separat de operator): ').strip().lower()
    if not first_name or not last_name or not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', email):
        raise ValueError('Numele și adresa de e-mail sunt obligatorii și trebuie să fie valide.')
    password = getpass('Parolă nouă (minimum 14 caractere): ')
    confirmation = getpass('Confirmă parola: ')
    if len(password) < 14 or password != confirmation:
        raise ValueError('Parola este prea scurtă sau confirmarea nu corespunde.')
    return {'first_name':first_name,'last_name':last_name,'email':email,'password_hash':ph.hash(password)}


def main():
    if input('Creezi cele două conturi inițiale de admin. Ești sigur? [scrie DA]: ').strip() != 'DA':
        raise SystemExit('Operațiune anulată.')
    admins = [collect_admin(1),collect_admin(2)]
    if admins[0]['email'] == admins[1]['email']:
        raise SystemExit('Administratorii trebuie să aibă e-mailuri distincte.')

    engine = create_engine(url, pool_pre_ping=True)
    with engine.begin() as conn:
        existing = conn.execute(text("SELECT count(*) FROM user_roles WHERE role='admin'")).scalar_one()
        if existing:
            raise SystemExit('Există deja administratori; bootstrap-ul inițial nu se rulează de două ori.')
        ids = []
        for data in admins:
            user_id = conn.execute(text('''
                INSERT INTO profiles(first_name,last_name,email,account_status,joined_at)
                VALUES (:first_name,:last_name,:email,'active',now()) RETURNING id
            '''),data).scalar_one()
            conn.execute(text('''
                INSERT INTO auth_credentials(user_id,password_hash,email_verified_at)
                VALUES (:uid,:hash,now())
            '''), {'uid':user_id,'hash':data['password_hash']})
            conn.execute(text("INSERT INTO user_roles(user_id,role) VALUES (:uid,'admin')"), {'uid':user_id})
            conn.execute(text('INSERT INTO user_settings(user_id) VALUES (:uid)'), {'uid':user_id})
            ids.append(user_id)
    print('\nAu fost create două conturi de administrator. ID-uri:')
    for uid in ids:
        print(f'- {uid}')
    print('Înainte de lansarea reală: activează autentificarea multifactor și limitele de încercări de login.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyboardInterrupt) as exc:
        sys.exit(f'Crearea administratorilor a fost anulată: {exc}')
