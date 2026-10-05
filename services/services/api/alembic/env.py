"""Migrații Alembic. Conexiunea este exclusiv din DATABASE_URL (root/.env)."""
import os
from pathlib import Path
from logging.config import fileConfig

from alembic import context
from dotenv import load_dotenv
from sqlalchemy import create_engine, pool

ROOT = Path(__file__).resolve().parents[3]
load_dotenv(ROOT / '.env')
config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)
url = os.environ.get('DATABASE_URL')
if not url:
    raise RuntimeError('Lipsește DATABASE_URL: completează fișierul .env de la rădăcina proiectului.')

if context.is_offline_mode():
    context.configure(url=url, literal_binds=True, dialect_opts={'paramstyle': 'named'})
    with context.begin_transaction():
        context.run_migrations()
else:
    engine = create_engine(url, poolclass=pool.NullPool, future=True)
    with engine.connect() as connection:
        context.configure(connection=connection)
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()
