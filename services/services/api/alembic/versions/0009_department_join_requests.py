"""Department join requests: coordinators ask for a volunteer to join their department,
an administrator approves or rejects.

Revision ID: 0009_department_join_requests
Revises: 0008_general_meeting
"""
from alembic import op

revision = "0009_department_join_requests"
down_revision = "0008_general_meeting"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("""
    CREATE TABLE IF NOT EXISTS department_join_requests (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
        department_id uuid NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
        requested_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
        status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
        reviewed_by uuid REFERENCES profiles(id) ON DELETE RESTRICT,
        reviewed_at timestamptz,
        decision_reason text,
        created_at timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT ck_join_request_review CHECK (
            (status = 'pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
            OR (status IN ('approved', 'rejected') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
        ),
        CONSTRAINT ck_join_request_not_self CHECK (requested_by <> user_id)
    )
    """)
    op.execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS uq_join_request_pending
        ON department_join_requests (user_id, department_id)
        WHERE status = 'pending'
    """)


def downgrade():
    raise RuntimeError("Downgrade distructiv dezactivat. Restaurează un backup sau creează o migrare explicită.")