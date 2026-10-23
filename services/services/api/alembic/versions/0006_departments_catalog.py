"""Department catalog: Tehnic, Creativ, Actorie, Producție, Marketing, Estetic.

Revision ID: 0006_departments_catalog
Revises: 0005_roles_permissions
"""
from alembic import op

revision = "0006_departments_catalog"
down_revision = "0005_roles_permissions"
branch_labels = None
depends_on = None


def upgrade():
    # Rename the seeded "Regie și scenariu" to "Creativ" (same slot, new name).
    op.execute("""
    UPDATE departments SET name = 'Creativ', slug = 'creativ'
    WHERE slug = 'regie-scenariu'
      AND NOT EXISTS (SELECT 1 FROM departments WHERE slug = 'creativ')
    """)
    # Split "Producție și marketing" into "Producție" and a separate "Marketing".
    op.execute("""
    UPDATE departments SET name = 'Producție', slug = 'productie'
    WHERE slug = 'productie-marketing'
      AND NOT EXISTS (SELECT 1 FROM departments WHERE slug = 'productie')
    """)
    # Insert whatever is still missing. Existing rows are left untouched.
    op.execute("""
    INSERT INTO departments (name, slug) VALUES
        ('Tehnic', 'tehnic'),
        ('Creativ', 'creativ'),
        ('Actorie', 'actorie'),
        ('Producție', 'productie'),
        ('Marketing', 'marketing'),
        ('Estetic', 'estetic')
    ON CONFLICT (slug) DO NOTHING
    """)


def downgrade():
    raise RuntimeError("Downgrade distructiv dezactivat. Restaurează un backup sau creează o migrare explicită.")
