"""Hours: tasks, shared codes, manual entries without start/end times, whole hours.

Revision ID: 0007_hours_entries
Revises: 0006_departments_catalog
"""
from alembic import op

revision = "0007_hours_entries"
down_revision = "0006_departments_catalog"
branch_labels = None
depends_on = None


def upgrade():
    # Tasks belong to an event (activity). Volunteers can add a task while submitting hours.
    op.execute("""
    CREATE TABLE IF NOT EXISTS activity_tasks (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        activity_id uuid NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
        name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
        created_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
        created_at timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT uq_activity_task_name UNIQUE (activity_id, name)
    )
    """)

    # One shared code, many volunteers. Each redemption creates its own time entry.
    op.execute("""
    CREATE TABLE IF NOT EXISTS shared_hour_codes (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        code_digest char(64) NOT NULL UNIQUE CHECK (code_digest ~ '^[a-f0-9]{64}$'),
        activity_id uuid NOT NULL REFERENCES activities(id) ON DELETE RESTRICT,
        task_id uuid REFERENCES activity_tasks(id) ON DELETE RESTRICT,
        department_id uuid REFERENCES departments(id) ON DELETE RESTRICT,
        work_date date NOT NULL,
        minutes integer NOT NULL CHECK (minutes BETWEEN 60 AND 720 AND minutes % 60 = 0),
        description text NOT NULL DEFAULT '',
        created_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
        created_at timestamptz NOT NULL DEFAULT now(),
        expires_at timestamptz NOT NULL,
        cancelled_at timestamptz,
        CONSTRAINT ck_shared_code_expiry CHECK (expires_at > created_at)
    )
    """)

    op.execute("""
    CREATE TABLE IF NOT EXISTS shared_hour_code_redemptions (
        code_id uuid NOT NULL REFERENCES shared_hour_codes(id) ON DELETE RESTRICT,
        user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
        time_entry_id uuid NOT NULL UNIQUE REFERENCES time_entries(id) ON DELETE RESTRICT,
        redeemed_at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (code_id, user_id)
    )
    """)

    op.execute("ALTER TABLE time_entries ADD COLUMN IF NOT EXISTS task_id uuid REFERENCES activity_tasks(id) ON DELETE RESTRICT")
    op.execute("ALTER TABLE time_entries ADD COLUMN IF NOT EXISTS shared_code_id uuid REFERENCES shared_hour_codes(id) ON DELETE RESTRICT")

    # Replace the source/status constraints so that manual entries need no start/end times.
    op.execute("ALTER TABLE time_entries DROP CONSTRAINT IF EXISTS time_entries_source_check")
    op.execute("ALTER TABLE time_entries DROP CONSTRAINT IF EXISTS ck_time_entry_source")
    op.execute("ALTER TABLE time_entries DROP CONSTRAINT IF EXISTS ck_time_entry_review")
    op.execute("""
    ALTER TABLE time_entries ADD CONSTRAINT time_entries_source_check
        CHECK (source IN ('manual', 'code', 'shared_code'))
    """)
    op.execute("""
    ALTER TABLE time_entries ADD CONSTRAINT ck_time_entry_source CHECK (
        (source = 'manual' AND activity_id IS NOT NULL AND activity_code_id IS NULL AND shared_code_id IS NULL)
        OR (source = 'code' AND activity_id IS NOT NULL AND activity_code_id IS NOT NULL
            AND shared_code_id IS NULL AND status IN ('approved', 'voided'))
        OR (source = 'shared_code' AND activity_id IS NOT NULL AND shared_code_id IS NOT NULL
            AND activity_code_id IS NULL AND status IN ('approved', 'voided'))
    )
    """)
    op.execute("""
    ALTER TABLE time_entries ADD CONSTRAINT ck_time_entry_review CHECK (
        (status IN ('pending', 'needs_changes') AND reviewed_at IS NULL AND reviewed_by IS NULL)
        OR (status = 'approved' AND (source IN ('code', 'shared_code') OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)))
        OR (status IN ('rejected', 'voided') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL
            AND nullif(btrim(rejection_reason), '') IS NOT NULL)
    )
    """)
    op.execute("ALTER TABLE time_entries DROP CONSTRAINT IF EXISTS ck_time_entry_whole_hours")
    op.execute("ALTER TABLE time_entries ADD CONSTRAINT ck_time_entry_whole_hours CHECK (duration_minutes % 60 = 0)")

    # Who may approve hours: coordinators (for their departments) and admins (all).
    op.execute("""
    INSERT INTO role_permissions (role, permission) VALUES
        ('coordinator', 'hours.review'),
        ('admin', 'hours.review')
    ON CONFLICT DO NOTHING
    """)


def downgrade():
    raise RuntimeError("Downgrade distructiv dezactivat. Restaurează un backup sau creează o migrare explicită.")