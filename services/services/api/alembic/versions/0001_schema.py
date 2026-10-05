"""Initial schema Overthink V1.

Revision ID: 0001_overthink_v1
Revises:
"""
from pathlib import Path

from alembic import op
import sqlalchemy as sa
import sqlparse

revision = '0001_overthink_v1'
down_revision = None
branch_labels = None
depends_on = None

ROOT = Path(__file__).resolve().parents[4]


def execute_sql_file(path: Path) -> None:
    # Fiecare instrucțiune separat: compatibil cu driverul psycopg 3 și funcțiile $$ plpgsql.
    source = path.read_text(encoding='utf-8')
    for statement in sqlparse.split(source):
        if statement.strip():
            op.execute(sa.text(statement))


def upgrade() -> None:
    execute_sql_file(ROOT / 'database' / '001_initial_schema.sql')
    execute_sql_file(ROOT / 'database' / 'seeds' / '002_departments.sql')


def downgrade() -> None:
    raise RuntimeError('Downgrade distructiv dezactivat. Restaurează un backup sau creează o migrare explicită.')
