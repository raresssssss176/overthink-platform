"""E-mail verification OTP invalidation and PostgreSQL-backed auth rate events.

Revision ID: 0003_email_verification_security
Revises: 0002_auth_lockout
"""
from alembic import op
import sqlalchemy as sa

revision = "0003_email_verification_security"
down_revision = "0002_auth_lockout"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "auth_tokens",
        sa.Column("invalidated_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "auth_tokens",
        sa.Column("attempt_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_check_constraint(
        "ck_auth_tokens_attempt_count_nonnegative",
        "auth_tokens",
        "attempt_count >= 0",
    )
    op.create_index(
        "idx_auth_tokens_active_v2",
        "auth_tokens",
        ["user_id", "purpose", "expires_at"],
        postgresql_where=sa.text("used_at IS NULL AND invalidated_at IS NULL"),
    )

    op.create_table(
        "auth_rate_limit_events",
        sa.Column("id", sa.Uuid(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("action", sa.Text(), nullable=False),
        sa.Column("email_digest", sa.String(length=64), nullable=True),
        sa.Column("ip_digest", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.CheckConstraint(
            "email_digest IS NOT NULL OR ip_digest IS NOT NULL",
            name="ck_auth_rate_event_key",
        ),
        sa.CheckConstraint(
            "email_digest IS NULL OR email_digest ~ '^[a-f0-9]{64}$'",
            name="ck_auth_rate_email_digest",
        ),
        sa.CheckConstraint(
            "ip_digest IS NULL OR ip_digest ~ '^[a-f0-9]{64}$'",
            name="ck_auth_rate_ip_digest",
        ),
    )
    op.create_index(
        "idx_auth_rate_email",
        "auth_rate_limit_events",
        ["action", "email_digest", "created_at"],
    )
    op.create_index(
        "idx_auth_rate_ip",
        "auth_rate_limit_events",
        ["action", "ip_digest", "created_at"],
    )


def downgrade():
    op.drop_index("idx_auth_rate_ip", table_name="auth_rate_limit_events")
    op.drop_index("idx_auth_rate_email", table_name="auth_rate_limit_events")
    op.drop_table("auth_rate_limit_events")
    op.drop_index("idx_auth_tokens_active_v2", table_name="auth_tokens")
    op.drop_constraint("ck_auth_tokens_attempt_count_nonnegative", "auth_tokens", type_="check")
    op.drop_column("auth_tokens", "attempt_count")
    op.drop_column("auth_tokens", "invalidated_at")
