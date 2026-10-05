"""Add temporary login lockout field to existing Overthink V1 schema.
Revision ID: 0002_auth_lockout
Revises: 0001_overthink_v1
"""
from alembic import op
import sqlalchemy as sa
revision='0002_auth_lockout'
down_revision='0001_overthink_v1'
branch_labels=None
depends_on=None

def upgrade():
    op.add_column('auth_credentials',sa.Column('locked_until',sa.DateTime(timezone=True),nullable=True))

def downgrade():
    op.drop_column('auth_credentials','locked_until')
