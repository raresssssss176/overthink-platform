"""Profile fields (from 0004, idempotent), roles, permission catalog,
delegation rules, expiring grants and department coordinators.

Revision ID: 0005_roles_permissions
Revises: 0004_profile_contact_fields
"""
from alembic import op

revision = "0005_roles_permissions"
down_revision = "0004_profile_contact_fields"
branch_labels = None
depends_on = None


def upgrade():
    # ------------------------------------------------------------------
    # Part A: content of 0004, written so it is safe whether 0004 was
    # applied in its old form (column "position") or its new form.
    # ------------------------------------------------------------------
    op.execute("""
    DO $$
    BEGIN
        IF EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = current_schema()
                     AND table_name = 'profiles' AND column_name = 'position')
           AND NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema = current_schema()
                     AND table_name = 'profiles' AND column_name = 'acronym') THEN
            ALTER TABLE profiles RENAME COLUMN position TO acronym;
        END IF;
    END $$;
    """)
    op.execute("ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone text")
    op.execute("ALTER TABLE profiles ADD COLUMN IF NOT EXISTS acronym text")
    op.execute("ALTER TABLE profiles ADD COLUMN IF NOT EXISTS gender text")
    op.execute("ALTER TABLE profiles ADD COLUMN IF NOT EXISTS requested_department_ids uuid[] NOT NULL DEFAULT '{}'")
    op.execute("ALTER TABLE profiles DROP CONSTRAINT IF EXISTS ck_profiles_gender")
    op.execute("""
    ALTER TABLE profiles ADD CONSTRAINT ck_profiles_gender
        CHECK (gender IS NULL OR gender IN ('masculin', 'feminin', 'altul'))
    """)
    op.execute("ALTER TABLE profiles DROP CONSTRAINT IF EXISTS ck_profiles_acronym_length")
    op.execute("""
    ALTER TABLE profiles ADD CONSTRAINT ck_profiles_acronym_length
        CHECK (acronym IS NULL OR length(btrim(acronym)) BETWEEN 1 AND 30)
    """)
    op.execute("ALTER TABLE profiles DROP CONSTRAINT IF EXISTS ck_profiles_phone_format")
    op.execute("""
    ALTER TABLE profiles ADD CONSTRAINT ck_profiles_phone_format
        CHECK (phone IS NULL OR phone ~ '^\\+?[0-9]{8,15}$')
    """)

    # ------------------------------------------------------------------
    # Part B: permission catalog. New permissions are rows, not code.
    # ------------------------------------------------------------------
    op.execute("""
    CREATE TABLE IF NOT EXISTS permission_types (
        code text PRIMARY KEY CHECK (code ~ '^[a-z]+(\\.[a-z_]+)+$'),
        label text NOT NULL CHECK (length(btrim(label)) BETWEEN 2 AND 120),
        description text,
        is_active boolean NOT NULL DEFAULT true,
        created_at timestamptz NOT NULL DEFAULT now()
    )
    """)
    op.execute("""
    INSERT INTO permission_types (code, label, description) VALUES
        ('hours.submit', 'Adaugă ore proprii', 'Trimite pontaje manuale sau cu cod'),
        ('attendance.mark', 'Pune absențe', 'Marchează prezența la evenimente'),
        ('calendar.create', 'Creează evenimente', 'Adaugă evenimente în calendar'),
        ('members.manage', 'Gestionează voluntari', 'Scoate sau editează voluntari din echipă'),
        ('teams.view', 'Vizualizează echipele', 'Vede toate echipele clubului'),
        ('roles.manage', 'Gestionează coordonatori', 'Promovează sau scoate coordonatori'),
        ('database.access', 'Acces la baza de date', 'Acces operațional la baza de date'),
        ('members.review', 'Revizuiește cereri', 'Aprobă sau respinge cererile de aderare'),
        ('hours.review', 'Verifică ore', 'Aprobă sau respinge pontajele manuale'),
        ('hours.generate_codes', 'Generează coduri de ore', 'Creează coduri pentru pontaj automat'),
        ('calendar.manage', 'Gestionează calendarul', 'Editează și anulează evenimente'),
        ('teams.manage', 'Gestionează echipe', 'Administrează echipele din departament'),
        ('reports.view', 'Vizualizează rapoarte', 'Acces la rapoarte'),
        ('permissions.manage', 'Gestionează permisiuni', 'Acordă permisiuni'),
        ('projects.manage', 'Gestionează proiecte', 'Administrează proiectele')
    ON CONFLICT (code) DO NOTHING
    """)

    # Intrinsic permissions of each role (what the role can do by itself).
    op.execute("""
    CREATE TABLE IF NOT EXISTS role_permissions (
        role text NOT NULL CHECK (role IN ('volunteer', 'coordinator', 'admin')),
        permission text NOT NULL REFERENCES permission_types(code) ON DELETE RESTRICT,
        PRIMARY KEY (role, permission)
    )
    """)
    op.execute("""
    INSERT INTO role_permissions (role, permission) VALUES
        ('volunteer', 'hours.submit'),
        ('coordinator', 'hours.submit'),
        ('coordinator', 'calendar.create'),
        ('coordinator', 'attendance.mark'),
        ('coordinator', 'members.manage'),
        ('coordinator', 'teams.view'),
        ('admin', 'hours.submit'),
        ('admin', 'calendar.create'),
        ('admin', 'attendance.mark'),
        ('admin', 'members.manage'),
        ('admin', 'teams.view'),
        ('admin', 'roles.manage'),
        ('admin', 'database.access')
    ON CONFLICT DO NOTHING
    """)

    # Which role may delegate which permission to volunteers (as grants).
    op.execute("""
    CREATE TABLE IF NOT EXISTS delegation_rules (
        granter_role text NOT NULL CHECK (granter_role IN ('coordinator', 'admin')),
        permission text NOT NULL REFERENCES permission_types(code) ON DELETE RESTRICT,
        PRIMARY KEY (granter_role, permission)
    )
    """)
    op.execute("""
    INSERT INTO delegation_rules (granter_role, permission) VALUES
        ('coordinator', 'calendar.create'),
        ('coordinator', 'attendance.mark'),
        ('admin', 'calendar.create'),
        ('admin', 'attendance.mark')
    ON CONFLICT DO NOTHING
    """)

    # ------------------------------------------------------------------
    # Part C: grants become expiring and reference the catalog.
    # ------------------------------------------------------------------
    op.execute("""
    DO $$
    DECLARE c record;
    BEGIN
        FOR c IN
            SELECT conname FROM pg_constraint
            WHERE conrelid = 'permission_grants'::regclass
              AND contype = 'c'
              AND pg_get_constraintdef(oid) LIKE '%members.review%'
        LOOP
            EXECUTE format('ALTER TABLE permission_grants DROP CONSTRAINT %I', c.conname);
        END LOOP;
    END $$;
    """)
    op.execute("ALTER TABLE permission_grants DROP CONSTRAINT IF EXISTS fk_permission_grants_type")
    op.execute("""
    ALTER TABLE permission_grants
        ADD CONSTRAINT fk_permission_grants_type
        FOREIGN KEY (permission) REFERENCES permission_types(code) ON DELETE RESTRICT
    """)
    op.execute("ALTER TABLE permission_grants ADD COLUMN IF NOT EXISTS expires_at timestamptz")
    op.execute("UPDATE permission_grants SET expires_at = created_at + interval '48 hours' WHERE expires_at IS NULL")
    op.execute("ALTER TABLE permission_grants ALTER COLUMN expires_at SET NOT NULL")
    op.execute("ALTER TABLE permission_grants DROP CONSTRAINT IF EXISTS ck_grant_expiry")
    op.execute("""
    ALTER TABLE permission_grants
        ADD CONSTRAINT ck_grant_expiry
        CHECK (expires_at > created_at AND expires_at <= created_at + interval '30 days')
    """)
    op.execute("ALTER TABLE permission_grants DROP CONSTRAINT IF EXISTS ck_grant_no_self_grant")
    op.execute("ALTER TABLE permission_grants ADD CONSTRAINT ck_grant_no_self_grant CHECK (granted_by <> user_id)")
    op.execute("""
    CREATE INDEX IF NOT EXISTS ix_permission_grants_active
        ON permission_grants (user_id, permission)
        WHERE revoked_at IS NULL
    """)

    # ------------------------------------------------------------------
    # Part D: one coordinator per department.
    # ------------------------------------------------------------------
    op.execute("""
    ALTER TABLE departments
        ADD COLUMN IF NOT EXISTS coordinator_user_id uuid REFERENCES profiles(id) ON DELETE SET NULL
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_departments_coordinator ON departments (coordinator_user_id)")


def downgrade():
    raise RuntimeError("Downgrade distructiv dezactivat. Restaurează un backup sau creează o migrare explicită.")
