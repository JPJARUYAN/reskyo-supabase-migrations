-- ============================================
-- MATCH RESPONDERS TRIGGER TEST
-- Run via: Supabase Studio SQL Editor (http://127.0.0.1:54323)
-- ============================================

-- Step 1: Create auth users via API first (script does this), then insert
-- This test assumes auth users already exist from the PowerShell script

-- Step 2: Verify responders exist
DO $$
DECLARE
  v_responder_count INTEGER;
  v_magsaysay_count INTEGER;
  v_incident_id UUID;
  v_dispatch_count INTEGER;
  v_incident_status TEXT;
BEGIN
  -- Count available responders
  SELECT COUNT(*) INTO v_responder_count
  FROM users WHERE role = 'responder' AND is_approved = true AND responder_status = 'available';
  RAISE NOTICE 'Available responders: %', v_responder_count;

  -- Count Magsaysay barangay
  SELECT COUNT(*) INTO v_magsaysay_count
  FROM barangays WHERE name = 'Magsaysay';
  RAISE NOTICE 'Magsaysay in barangays: %', v_magsaysay_count;

  -- Test the exact ST_DWithin logic
  IF v_responder_count > 0 AND v_magsaysay_count > 0 THEN
    RAISE NOTICE 'ST_DWithin test: %', (
      SELECT ST_DWithin(
        ST_SetSRID(ST_MakePoint(b.centroid_lng, b.centroid_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(125.3469, 6.7569), 4326)::geography,
        3000
      )
      FROM barangays b WHERE b.name = 'Magsaysay'
    );
  END IF;

  -- Insert test incident (should trigger match_responders)
  INSERT INTO incidents (type, description, latitude, longitude, reporter_id, status, barangay)
  SELECT 'other', 'TEST-trigger', 6.7569, 125.3469, uid, 'reported', 'Magsaysay'
  FROM users WHERE role = 'responder' LIMIT 1
  RETURNING id INTO v_incident_id;

  RAISE NOTICE 'Inserted incident: %', v_incident_id;

  -- Check if dispatches were created by trigger
  SELECT COUNT(*) INTO v_dispatch_count
  FROM dispatches WHERE incident_id = v_incident_id;
  RAISE NOTICE 'Dispatches created by trigger: %', v_dispatch_count;

  -- Check incident status
  SELECT status INTO v_incident_status
  FROM incidents WHERE id = v_incident_id;
  RAISE NOTICE 'Incident status: %', v_incident_status;

  -- Final result
  IF v_dispatch_count > 0 THEN
    RAISE NOTICE 'RESULT: PASS - match_responders trigger created % dispatches', v_dispatch_count;
  ELSE
    RAISE NOTICE 'RESULT: FAIL - no dispatches created';
    -- Debug: check what the trigger query would return
    RAISE NOTICE 'DEBUG: Available responders in Magsaysay:';
    FOR rec IN
      SELECT u.uid, u.barangay, b.name AS bname, b.centroid_lat, b.centroid_lng,
        ST_DWithin(
          ST_SetSRID(ST_MakePoint(b.centroid_lng, b.centroid_lat), 4326)::geography,
          ST_SetSRID(ST_MakePoint(125.3469, 6.7569), 4326)::geography,
          3000
        ) AS within_3km
      FROM users u
      JOIN barangays b ON b.name = u.barangay
      WHERE u.role = 'responder' AND u.is_approved = true AND u.responder_status = 'available'
    LOOP
      RAISE NOTICE '  Responder: %, barangay: %, centroid: %,% , within_3km: %',
        rec.uid, rec.bname, rec.centroid_lat, rec.centroid_lng, rec.within_3km;
    END LOOP;
  END IF;

  -- Cleanup
  DELETE FROM dispatches WHERE incident_id = v_incident_id;
  DELETE FROM incidents WHERE id = v_incident_id;
  RAISE NOTICE 'Cleanup done';
END $$;
