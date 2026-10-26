"""Department for general meetings (ședințe generale), available to every member.

Revision ID: 0008_general_meeting
Revises: 0007_hours_entries
"""
from alembic import op

revision = "0008_general_meeting"
down_revision = "0007_hours_entries"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
    INSERT INTO departments (name, slug, description) VALUES
        ('Ședință generală', 'sedinta-generala', 'Ore de la ședințele generale ale clubului')
    ON CONFLICT (slug) DO NOTHING
    """)


def downgrade():
    raise RuntimeError("Downgrade distructiv dezactivat. Restaurează un backup sau creează o migrare explicită.")