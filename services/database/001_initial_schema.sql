-- OVERTHINK APP · PostgreSQL 17 · Migration 0001
-- Aplicati doar intr-o baza noua prin Alembic. Toate momentele sunt TIMESTAMPTZ (UTC la nivel API).
-- DATE pentru raportare foloseste fusul Europe/Bucharest, inclusiv la schimbarea orei.

CREATE TABLE departments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
    slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE profiles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name text NOT NULL CHECK (length(btrim(first_name)) BETWEEN 1 AND 100),
    last_name text NOT NULL CHECK (length(btrim(last_name)) BETWEEN 1 AND 100),
    email text NOT NULL CHECK (length(btrim(email)) BETWEEN 3 AND 254),
    email_normalized text GENERATED ALWAYS AS (lower(btrim(email))) STORED UNIQUE,
    birth_date date,
    school text,
    locality text,
    primary_department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
    profile_photo_key text,
    approved_minutes_cached integer NOT NULL DEFAULT 0 CHECK (approved_minutes_cached >= 0),
    account_status text NOT NULL DEFAULT 'email_unverified' CHECK (
        account_status IN ('email_unverified','pending','active','rejected','suspended','deleted')
    ),
    joined_at timestamptz,
    privacy_notice_version text,
    privacy_acknowledged_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CONSTRAINT ck_profile_deletion CHECK ((account_status = 'deleted') = (deleted_at IS NOT NULL))
);
CREATE INDEX idx_profiles_account_status ON profiles(account_status);
CREATE INDEX idx_profiles_primary_department ON profiles(primary_department_id);

CREATE TABLE auth_credentials (
    user_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    password_hash text NOT NULL CHECK (length(password_hash) > 20),
    email_verified_at timestamptz,
    password_changed_at timestamptz NOT NULL DEFAULT now(),
    failed_login_attempts integer NOT NULL DEFAULT 0 CHECK (failed_login_attempts >= 0),
    credentials_version integer NOT NULL DEFAULT 1 CHECK (credentials_version >= 1)
);

CREATE TABLE auth_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    purpose text NOT NULL CHECK (purpose IN ('verify_email','reset_password','change_email')),
    token_digest char(64) NOT NULL UNIQUE CHECK (token_digest ~ '^[a-f0-9]{64}$'),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_auth_token_expiry CHECK (expires_at > created_at)
);
CREATE INDEX idx_auth_tokens_user ON auth_tokens(user_id,purpose,expires_at) WHERE used_at IS NULL;

CREATE TABLE auth_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    refresh_token_digest char(64) NOT NULL UNIQUE CHECK (refresh_token_digest ~ '^[a-f0-9]{64}$'),
    device_label text,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    last_used_at timestamptz,
    revoked_at timestamptz,
    replaced_by uuid REFERENCES auth_sessions(id) ON DELETE SET NULL,
    CONSTRAINT ck_auth_session_expiry CHECK (expires_at > created_at),
    CONSTRAINT ck_auth_session_no_self_replacement CHECK (replaced_by IS NULL OR replaced_by <> id)
);
CREATE INDEX idx_auth_sessions_active ON auth_sessions(user_id,expires_at) WHERE revoked_at IS NULL;

CREATE TABLE membership_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    status text NOT NULL DEFAULT 'submitted' CHECK (status IN ('submitted','pending','approved','rejected','cancelled')),
    submitted_at timestamptz NOT NULL DEFAULT now(),
    last_reminder_at timestamptz,
    reminder_count integer NOT NULL DEFAULT 0 CHECK (reminder_count >= 0),
    reviewed_by uuid REFERENCES profiles(id) ON DELETE RESTRICT,
    reviewed_at timestamptz,
    decision_reason text,
    CONSTRAINT ck_reminder_after_submission CHECK (last_reminder_at IS NULL OR last_reminder_at >= submitted_at),
    CONSTRAINT ck_review_fields CHECK (
        (status IN ('submitted','pending') AND reviewed_by IS NULL AND reviewed_at IS NULL)
        OR (status IN ('approved','rejected') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)
        OR status = 'cancelled'
    ),
    CONSTRAINT ck_rejection_reason CHECK (status <> 'rejected' OR nullif(btrim(decision_reason),'') IS NOT NULL)
);
CREATE UNIQUE INDEX uq_membership_one_open_request ON membership_requests(user_id)
    WHERE status IN ('submitted','pending');
CREATE INDEX idx_membership_review_queue ON membership_requests(status,submitted_at);

-- Departamentul principal este profiles.primary_department_id; tabela de mai jos permite apartenente suplimentare.
CREATE TABLE member_departments (
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    department_id uuid NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    joined_at timestamptz NOT NULL DEFAULT now(),
    assigned_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
    PRIMARY KEY (user_id,department_id)
);

CREATE TABLE teams (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id uuid NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
    description text,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (department_id,name)
);

CREATE TABLE team_members (
    team_id uuid NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    role_in_team text,
    assigned_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
    joined_at timestamptz NOT NULL DEFAULT now(),
    left_at timestamptz,
    PRIMARY KEY (team_id,user_id),
    CONSTRAINT ck_team_dates CHECK (left_at IS NULL OR left_at >= joined_at)
);
CREATE INDEX idx_team_members_user ON team_members(user_id) WHERE left_at IS NULL;

CREATE TABLE user_roles (
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    role text NOT NULL CHECK (role IN ('volunteer','coordinator','admin')),
    assigned_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id,role)
);

-- Permission scope este explicit, cu FK verificabile (nu scope_id polimorfic fara FK).
CREATE TABLE projects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 200),
    description text,
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','completed','cancelled')),
    starts_on date,
    ends_on date,
    created_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_project_dates CHECK (starts_on IS NULL OR ends_on IS NULL OR ends_on >= starts_on)
);

CREATE TABLE permission_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    permission text NOT NULL CHECK (permission IN (
        'members.review','members.manage','hours.review','hours.generate_codes',
        'calendar.create','calendar.manage','teams.manage','reports.view','permissions.manage',
        'projects.manage'
    )),
    scope_type text NOT NULL CHECK (scope_type IN ('club','department','team','project')),
    department_id uuid REFERENCES departments(id) ON DELETE RESTRICT,
    team_id uuid REFERENCES teams(id) ON DELETE RESTRICT,
    project_id uuid REFERENCES projects(id) ON DELETE RESTRICT,
    granted_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    CONSTRAINT ck_grant_scope CHECK (
        (scope_type='club' AND department_id IS NULL AND team_id IS NULL AND project_id IS NULL)
        OR (scope_type='department' AND department_id IS NOT NULL AND team_id IS NULL AND project_id IS NULL)
        OR (scope_type='team' AND department_id IS NULL AND team_id IS NOT NULL AND project_id IS NULL)
        OR (scope_type='project' AND department_id IS NULL AND team_id IS NULL AND project_id IS NOT NULL)
    ),
    CONSTRAINT ck_revocation_after_grant CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE UNIQUE INDEX uq_permission_active ON permission_grants
    (user_id,permission,scope_type,department_id,team_id,project_id) NULLS NOT DISTINCT
    WHERE revoked_at IS NULL;
CREATE INDEX idx_permission_lookup ON permission_grants(user_id,permission,scope_type) WHERE revoked_at IS NULL;

CREATE TABLE project_members (
    project_id uuid NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    role_in_project text,
    assigned_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
    joined_at timestamptz NOT NULL DEFAULT now(),
    left_at timestamptz,
    PRIMARY KEY (project_id,user_id),
    CONSTRAINT ck_project_members_dates CHECK (left_at IS NULL OR left_at >= joined_at)
);
CREATE INDEX idx_project_members_user ON project_members(user_id) WHERE left_at IS NULL;

CREATE TABLE activities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
    description text,
    activity_type text,
    starts_at timestamptz,
    ends_at timestamptz,
    location_text text,
    organizer_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
    project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
    visibility text NOT NULL DEFAULT 'club' CHECK (visibility IN ('club','departments','teams','assigned')),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','cancelled','completed')),
    created_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_activity_dates CHECK (ends_at IS NULL OR (starts_at IS NOT NULL AND ends_at > starts_at))
);
CREATE INDEX idx_activities_published_future ON activities(starts_at) WHERE status='published';
CREATE INDEX idx_activities_unscheduled ON activities(created_at DESC)
    WHERE status='published' AND starts_at IS NULL;
CREATE INDEX idx_activities_project ON activities(project_id);

CREATE TABLE activity_departments (
    activity_id uuid NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    department_id uuid NOT NULL REFERENCES departments(id) ON DELETE RESTRICT,
    PRIMARY KEY (activity_id,department_id)
);
CREATE INDEX idx_activity_departments_dep ON activity_departments(department_id,activity_id);

CREATE TABLE activity_teams (
    activity_id uuid NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    team_id uuid NOT NULL REFERENCES teams(id) ON DELETE RESTRICT,
    PRIMARY KEY (activity_id,team_id)
);
CREATE INDEX idx_activity_teams_team ON activity_teams(team_id,activity_id);

CREATE TABLE activity_participants (
    activity_id uuid NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    role_in_activity text,
    participation_status text NOT NULL DEFAULT 'assigned' CHECK (participation_status IN ('assigned','confirmed','withdrawn')),
    attendance_status text NOT NULL DEFAULT 'unknown' CHECK (attendance_status IN ('unknown','present','absent','excused')),
    assigned_by uuid REFERENCES profiles(id) ON DELETE SET NULL,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (activity_id,user_id)
);
CREATE INDEX idx_activity_participants_user ON activity_participants(user_id,activity_id);

CREATE TABLE activity_codes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code_digest char(64) NOT NULL UNIQUE CHECK (code_digest ~ '^[a-f0-9]{64}$'),
    activity_id uuid NOT NULL REFERENCES activities(id) ON DELETE RESTRICT,
    assigned_user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    work_date date NOT NULL,
    granted_minutes integer NOT NULL CHECK (granted_minutes BETWEEN 1 AND 720),
    role_in_activity text,
    created_by uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    redeemed_by uuid REFERENCES profiles(id) ON DELETE RESTRICT,
    redeemed_at timestamptz,
    CONSTRAINT uq_activity_code_identity UNIQUE(id,assigned_user_id,activity_id,work_date,granted_minutes),
    CONSTRAINT uq_activity_code_one_per_participant UNIQUE(activity_id,assigned_user_id),
    CONSTRAINT ck_code_expiry CHECK(expires_at > created_at),
    CONSTRAINT ck_code_redemption CHECK ((redeemed_by IS NULL) = (redeemed_at IS NULL)),
    CONSTRAINT ck_code_redeemer CHECK (redeemed_by IS NULL OR redeemed_by = assigned_user_id),
    CONSTRAINT ck_no_self_issued_code CHECK (created_by <> assigned_user_id)
);
CREATE INDEX idx_codes_assigned_unredeemed ON activity_codes(assigned_user_id,expires_at)
    WHERE redeemed_at IS NULL;

CREATE TABLE time_entries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    activity_id uuid REFERENCES activities(id) ON DELETE RESTRICT,
    project_id uuid REFERENCES projects(id) ON DELETE RESTRICT,
    department_id uuid REFERENCES departments(id) ON DELETE RESTRICT,
    activity_name_snapshot text NOT NULL CHECK (length(btrim(activity_name_snapshot)) >= 2),
    role_in_activity text,
    work_date date NOT NULL,
    start_at timestamptz,
    end_at timestamptz,
    duration_minutes integer NOT NULL CHECK (duration_minutes BETWEEN 1 AND 720),
    description text NOT NULL DEFAULT '',
    source text NOT NULL CHECK (source IN ('manual','code')),
    activity_code_id uuid UNIQUE,
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','needs_changes','approved','rejected','voided')),
    reviewed_by uuid REFERENCES profiles(id) ON DELETE RESTRICT,
    reviewed_at timestamptz,
    rejection_reason text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_time_entry_code_member_activity FOREIGN KEY (activity_code_id,user_id,activity_id,work_date,duration_minutes)
        REFERENCES activity_codes(id,assigned_user_id,activity_id,work_date,granted_minutes) ON DELETE RESTRICT,
    CONSTRAINT ck_time_entry_interval CHECK (
        (start_at IS NULL AND end_at IS NULL) OR
        (start_at IS NOT NULL AND end_at IS NOT NULL AND end_at > start_at AND
         EXTRACT(EPOCH FROM (end_at-start_at)) = duration_minutes*60 AND
         work_date = (start_at AT TIME ZONE 'Europe/Bucharest')::date)
    ),
    CONSTRAINT ck_time_entry_source CHECK (
        (source='manual' AND activity_code_id IS NULL AND start_at IS NOT NULL AND end_at IS NOT NULL
            AND length(btrim(description)) >= 3)
        OR (source='code' AND activity_code_id IS NOT NULL AND activity_id IS NOT NULL AND status IN ('approved','voided'))
    ),
    CONSTRAINT ck_time_entry_review CHECK (
        (status IN ('pending','needs_changes') AND reviewed_at IS NULL AND reviewed_by IS NULL)
        OR (status='approved' AND (source='code' OR (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL)))
        OR (status IN ('rejected','voided') AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL
            AND nullif(btrim(rejection_reason),'') IS NOT NULL)
    ),
    CONSTRAINT ck_no_self_review CHECK (reviewed_by IS NULL OR reviewed_by <> user_id)
);
CREATE INDEX idx_time_entries_member_day ON time_entries(user_id,work_date,status);
CREATE INDEX idx_time_entries_pending ON time_entries(created_at) WHERE status='pending';
CREATE INDEX idx_time_entries_activity ON time_entries(activity_id);
CREATE INDEX idx_time_entries_project ON time_entries(project_id);

-- Evita suprapunerile exacte intre intervalele cu status activ (manual + code cu interval).
-- Pentru doua inregistrari 'code' fara interval, API trebuie sa verifice plafonul si dublurile.
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE time_entries ADD CONSTRAINT ex_time_entries_active_overlap
    EXCLUDE USING gist (
        user_id WITH =,
        tstzrange(start_at,end_at,'[)') WITH &&
    ) WHERE (status IN ('pending','approved') AND start_at IS NOT NULL)
    DEFERRABLE INITIALLY IMMEDIATE;

-- La introducerea unui pontaj prin cod se consuma codul atomic (si la acces SQL direct).
CREATE FUNCTION overthink_consume_activity_code() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='UPDATE' AND NEW.source <> OLD.source THEN
        RAISE EXCEPTION 'Sursa pontajului nu poate fi modificată';
    END IF;
    IF TG_OP='UPDATE' AND OLD.source='code' THEN
        IF NEW.user_id <> OLD.user_id OR NEW.activity_id IS DISTINCT FROM OLD.activity_id
           OR NEW.activity_code_id IS DISTINCT FROM OLD.activity_code_id
           OR NEW.work_date <> OLD.work_date OR NEW.duration_minutes <> OLD.duration_minutes
           OR NEW.source <> OLD.source THEN
            RAISE EXCEPTION 'Pontajul generat prin cod nu poate fi reasociat sau modificat ca durata';
        END IF;
    END IF;
    IF TG_OP='INSERT' AND NEW.source='code' THEN
        IF NEW.status <> 'approved' THEN
            RAISE EXCEPTION 'Un cod nou poate produce doar un pontaj aprobat';
        END IF;
        UPDATE activity_codes
        SET redeemed_by=NEW.user_id, redeemed_at=now()
        WHERE id=NEW.activity_code_id AND redeemed_at IS NULL AND expires_at > now();
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Codul este expirat, utilizat deja sau invalid';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_consume_activity_code BEFORE INSERT OR UPDATE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION overthink_consume_activity_code();

CREATE TABLE time_entry_feedback (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    time_entry_id uuid NOT NULL REFERENCES time_entries(id) ON DELETE CASCADE,
    author_id uuid NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 4000),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_time_entry_feedback ON time_entry_feedback(time_entry_id,created_at);

CREATE TABLE user_settings (
    user_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
    theme text NOT NULL DEFAULT 'system' CHECK (theme IN ('system','light','dark')),
    notify_email boolean NOT NULL DEFAULT true,
    notify_push boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
    action text NOT NULL CHECK (length(btrim(action)) >= 3),
    entity_type text NOT NULL CHECK (length(btrim(entity_type)) >= 2),
    entity_id uuid,
    metadata_safe_json jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(metadata_safe_json)='object'),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type,entity_id,created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor_id,created_at DESC);

-- NU se stocheaza parole, coduri brute, linkuri de resetare sau tokenuri in payload.
CREATE TABLE notification_outbox (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    recipient_user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
    recipient_email text,
    template text NOT NULL,
    payload_safe_json jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(payload_safe_json)='object'),
    status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sending','sent','failed')),
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    available_at timestamptz NOT NULL DEFAULT now(),
    sent_at timestamptz,
    last_error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT ck_outbox_recipient CHECK(recipient_user_id IS NOT NULL OR nullif(btrim(recipient_email),'') IS NOT NULL)
);
CREATE INDEX idx_outbox_unsent ON notification_outbox(status,available_at)
    WHERE status IN ('pending','failed');

-- Actualizare uniforma a updated_at. Toate operatiunile administrative se vor face in tranzactii.
CREATE FUNCTION overthink_touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_profiles_updated BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION overthink_touch_updated_at();
CREATE TRIGGER tr_teams_updated BEFORE UPDATE ON teams FOR EACH ROW EXECUTE FUNCTION overthink_touch_updated_at();
CREATE TRIGGER tr_projects_updated BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION overthink_touch_updated_at();
CREATE TRIGGER tr_activities_updated BEFORE UPDATE ON activities FOR EACH ROW EXECUTE FUNCTION overthink_touch_updated_at();
CREATE TRIGGER tr_time_entries_updated BEFORE UPDATE ON time_entries FOR EACH ROW EXECUTE FUNCTION overthink_touch_updated_at();
CREATE TRIGGER tr_user_settings_updated BEFORE UPDATE ON user_settings FOR EACH ROW EXECUTE FUNCTION overthink_touch_updated_at();

-- Contorizarea in profil se face atomic pe baza sursei oficiale time_entries.
-- INSERT/DELETE/UPDATE se reflecta fara calcule client-side. Revocarea aprobarii scade totalul.
CREATE FUNCTION overthink_sync_approved_minutes() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    old_minutes integer := 0;
    new_minutes integer := 0;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.user_id <> OLD.user_id THEN
            RAISE EXCEPTION 'Nu se permite schimbarea titularului pontajului';
        END IF;
        IF OLD.status='approved' THEN old_minutes := OLD.duration_minutes; END IF;
        IF NEW.status='approved' THEN new_minutes := NEW.duration_minutes; END IF;
    ELSIF TG_OP = 'INSERT' THEN
        IF NEW.status='approved' THEN new_minutes := NEW.duration_minutes; END IF;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.status='approved' THEN old_minutes := OLD.duration_minutes; END IF;
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF new_minutes <> 0 THEN
            UPDATE profiles SET approved_minutes_cached = approved_minutes_cached + new_minutes WHERE id = NEW.user_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF old_minutes <> 0 THEN
            UPDATE profiles SET approved_minutes_cached = approved_minutes_cached - old_minutes WHERE id = OLD.user_id;
        END IF;
        RETURN OLD;
    ELSE
        IF new_minutes <> old_minutes THEN
            UPDATE profiles SET approved_minutes_cached = approved_minutes_cached + new_minutes - old_minutes WHERE id = NEW.user_id;
        END IF;
        RETURN NEW;
    END IF;
END;
$$;
CREATE TRIGGER tr_approved_minutes AFTER INSERT OR UPDATE OR DELETE ON time_entries
    FOR EACH ROW EXECUTE FUNCTION overthink_sync_approved_minutes();

-- Sumarul oficial pentru rapoarte/reconciliere (fara presupunerea ca fiecare atelier este voluntariat).
CREATE VIEW profile_hours_summary AS
SELECT p.id AS user_id,
       COALESCE(SUM(t.duration_minutes) FILTER (WHERE t.status='approved'),0)::bigint AS approved_minutes,
       COALESCE(SUM(t.duration_minutes) FILTER (WHERE t.status='pending'),0)::bigint AS pending_minutes,
       p.approved_minutes_cached,
       p.approved_minutes_cached - COALESCE(SUM(t.duration_minutes) FILTER (WHERE t.status='approved'),0)::bigint
           AS cache_difference_minutes
FROM profiles p LEFT JOIN time_entries t ON t.user_id=p.id
GROUP BY p.id,p.approved_minutes_cached;
