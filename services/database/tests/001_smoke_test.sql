-- Ruleaza NUMAI pe o baza de dezvoltare, dupa migrare. Testul se incheie cu ROLLBACK.
BEGIN;
DO $$
DECLARE
    v_member uuid;
    v_reviewer uuid;
    v_entry uuid;
    v_activity uuid;
    v_code uuid;
    v_minutes integer;
    v_overlaps_blocked boolean := false;
    v_reuse_blocked boolean := false;
BEGIN
    INSERT INTO profiles(first_name,last_name,email,account_status)
    VALUES ('Voluntar','Smoke','smoke-volunteer@invalid.example','active') RETURNING id INTO v_member;
    INSERT INTO profiles(first_name,last_name,email,account_status)
    VALUES ('Admin','Smoke','smoke-admin@invalid.example','active') RETURNING id INTO v_reviewer;

    INSERT INTO time_entries(user_id,activity_name_snapshot,work_date,start_at,end_at,duration_minutes,
                             description,source,status,reviewed_by,reviewed_at)
    VALUES (v_member,'Test pontaj','2026-10-15','2026-10-15 10:00:00+03','2026-10-15 12:00:00+03',120,
            'Activitate de test','manual','approved',v_reviewer,now()) RETURNING id INTO v_entry;
    SELECT approved_minutes_cached INTO v_minutes FROM profiles WHERE id=v_member;
    IF v_minutes <> 120 THEN RAISE EXCEPTION 'Eroare: INSERT aprobat nu actualizeaza totalul'; END IF;

    UPDATE time_entries SET status='voided',reviewed_by=v_reviewer,reviewed_at=now(),
        rejection_reason='Anulare de test' WHERE id=v_entry;
    SELECT approved_minutes_cached INTO v_minutes FROM profiles WHERE id=v_member;
    IF v_minutes <> 0 THEN RAISE EXCEPTION 'Eroare: voided nu scade totalul'; END IF;

    INSERT INTO time_entries(user_id,activity_name_snapshot,work_date,start_at,end_at,duration_minutes,
                             description,source,status)
    VALUES(v_member,'Activitate in asteptare','2026-10-15',
            '2026-10-15 13:00:00+03','2026-10-15 14:00:00+03',60,'O activitate de test','manual','pending');
    SELECT approved_minutes_cached INTO v_minutes FROM profiles WHERE id=v_member;
    IF v_minutes <> 0 THEN RAISE EXCEPTION 'Eroare: pontajul pending creste totalul'; END IF;

    BEGIN
        INSERT INTO time_entries(user_id,activity_name_snapshot,work_date,start_at,end_at,duration_minutes,
                                 description,source,status)
        VALUES(v_member,'Interval suprapus','2026-10-15',
            '2026-10-15 13:30:00+03','2026-10-15 14:30:00+03',60,'Interval suprapus de test','manual','pending');
    EXCEPTION WHEN exclusion_violation THEN
        v_overlaps_blocked := true;
    END;
    IF NOT v_overlaps_blocked THEN RAISE EXCEPTION 'Eroare: interval suprapus acceptat'; END IF;
    -- Validarea automata: cod individual consumat atomic, totalul creste cu exact 90 minute.
    INSERT INTO activities(title,status,created_by) VALUES ('Atelier de test','published',v_reviewer)
        RETURNING id INTO v_activity;
    INSERT INTO activity_participants(activity_id,user_id,attendance_status)
        VALUES (v_activity,v_member,'present');
    INSERT INTO activity_codes(code_digest,activity_id,assigned_user_id,work_date,
                               granted_minutes,created_by,expires_at)
    VALUES (repeat('a',64),v_activity,v_member,'2026-10-15',90,v_reviewer,now()+interval '1 day')
        RETURNING id INTO v_code;
    INSERT INTO time_entries(user_id,activity_id,activity_name_snapshot,work_date,duration_minutes,
                             description,source,activity_code_id,status)
    VALUES(v_member,v_activity,'Atelier de test','2026-10-15',90,'','code',v_code,'approved');
    IF NOT EXISTS (SELECT 1 FROM activity_codes WHERE id=v_code AND redeemed_by=v_member AND redeemed_at IS NOT NULL)
    THEN RAISE EXCEPTION 'Eroare: codul nu a fost marcat consumat'; END IF;
    SELECT approved_minutes_cached INTO v_minutes FROM profiles WHERE id=v_member;
    IF v_minutes <> 90 THEN RAISE EXCEPTION 'Eroare: validarea prin cod nu a creditat 90 de minute'; END IF;
    -- Unicitatea activity_code_id impiedica a doua creditare.
    BEGIN
        INSERT INTO time_entries(user_id,activity_id,activity_name_snapshot,work_date,duration_minutes,
                                 description,source,activity_code_id,status)
        VALUES(v_member,v_activity,'Atelier de test','2026-10-15',90,'','code',v_code,'approved');
    EXCEPTION WHEN unique_violation OR raise_exception THEN
        v_reuse_blocked := true; -- BEFORE INSERT poate respinge codul deja consumat.
    END;
    IF NOT v_reuse_blocked THEN RAISE EXCEPTION 'Eroare: codul a putut fi refolosit'; END IF;

    IF EXISTS (SELECT 1 FROM profile_hours_summary WHERE user_id=v_member AND cache_difference_minutes<>0) THEN
        RAISE EXCEPTION 'Eroare: approved_minutes_cached diferit de totalul real';
    END IF;
    RAISE NOTICE 'PASS: cache, anulare, pending, anti-overlap, cod individual';
END;
$$;
ROLLBACK;
