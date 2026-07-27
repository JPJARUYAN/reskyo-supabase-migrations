DO $$
DECLARE
  v_auth_uid UUID;
  v_incident_id UUID;
  v_dispatch_count INTEGER;
  rec RECORD;
BEGIN
  -- Cleanup
  DELETE FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-psql');
  DELETE FROM incidents WHERE description = 'TEST-psql';
  DELETE FROM users WHERE email LIKE 'psql_direct%@test.com';
  DELETE FROM auth.users WHERE email LIKE 'psql_direct%@test.com';

  v_auth_uid := gen_random_uuid();

  -- Create auth user (triggers may auto-insert into public.users)
  INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES (v_auth_uid, 'authenticated', 'authenticated', 'psql_direct_' || left(v_auth_uid::text,8) || '@test.com', crypt('test', gen_salt('bf')), now(), now(), now());

  RAISE NOTICE 'Step 1: Created auth user %', v_auth_uid;

  -- Check if auto-inserted, if not insert manually
  IF NOT EXISTS (SELECT 1 FROM users WHERE uid = v_auth_uid) THEN
    INSERT INTO users (uid, email, full_name, contact_number, barangay, role, is_approved, responder_status)
    VALUES (v_auth_uid, 'psql_direct_' || left(v_auth_uid::text,8) || '@test.com', 'PSQL Test', '09999999999', 'Magsaysay', 'responder', true, 'available');
    RAISE NOTICE 'Step 2: Manually inserted responder';
  ELSE
    UPDATE users SET role = 'responder', is_approved = true, responder_status = 'available', barangay = 'Magsaysay'
    WHERE uid = v_auth_uid;
    RAISE NOTICE 'Step 2: Updated auto-inserted user to responder';
  END IF;

  RAISE NOTICE '  Responder ready: %', (SELECT responder_status FROM users WHERE uid = v_auth_uid);

  -- Insert incident (trigger should fire!)
  INSERT INTO incidents (type, description, latitude, longitude, reporter_id, status, barangay)
  VALUES ('other', 'TEST-psql', 6.7569, 125.3469, v_auth_uid, 'reported', 'Magsaysay')
  RETURNING id INTO v_incident_id;

  RAISE NOTICE 'Step 3: Inserted incident %', v_incident_id;

  SELECT COUNT(*) INTO v_dispatch_count FROM dispatches WHERE incident_id = v_incident_id;
  RAISE NOTICE 'Step 4: Dispatches created: %', v_dispatch_count;

  IF v_dispatch_count > 0 THEN
    RAISE NOTICE '=== RESULT: PASS ===';
  ELSE
    RAISE NOTICE '=== RESULT: FAIL ===';
    FOR rec IN
      SELECT u.uid, b.name, b.centroid_lat, b.centroid_lng,
        haversine_km(6.7569, 125.3469, b.centroid_lat, b.centroid_lng) AS dist_km,
        ST_DWithin(
          ST_SetSRID(ST_MakePoint(b.centroid_lng, b.centroid_lat), 4326)::geography,
          (SELECT location FROM incidents WHERE id = v_incident_id),
          3000
        ) AS within_3km
      FROM users u JOIN barangays b ON b.name = u.barangay
      WHERE u.role = 'responder' AND u.is_approved = true AND u.responder_status = 'available'
    LOOP
      RAISE NOTICE '  uid=%, dist=%.2fkm, within_3km=%', rec.uid, rec.dist_km, rec.within_3km;
    END LOOP;
  END IF;

  DELETE FROM dispatches WHERE incident_id = v_incident_id;
  DELETE FROM incidents WHERE id = v_incident_id;
  DELETE FROM users WHERE uid = v_auth_uid;
  DELETE FROM auth.users WHERE id = v_auth_uid;
  RAISE NOTICE 'Cleanup done';
END $$;
