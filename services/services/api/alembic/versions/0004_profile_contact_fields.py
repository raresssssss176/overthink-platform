"""Profile contact fields from the app sketch.

Revision ID: 0004_profile_contact_fields
Revises: 0003_email_verification_security
"""
from alembic import op
import sqlalchemy as sa

revision = "0004_profile_contact_fields"
down_revision = "0003_email_verification_security"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("profiles", sa.Column("phone", sa.Text(), nullable=True))
    op.add_column("profiles", sa.Column("position", sa.Text(), nullable=True))
    op.add_column("profiles", sa.Column("gender", sa.Text(), nullable=True))


def downgrade():
    op.drop_column("profiles", "gender")
    op.drop_column("profiles", "position")
    op.drop_column("profiles", "phone")
