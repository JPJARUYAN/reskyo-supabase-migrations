-- ============================================
-- PHASE 9: Unit Tests — match_responders trigger
-- Self-contained: creates test user, incident
-- ============================================

-- Create temp test user (reporter)
INSERT INTO users (uid, email, full_name, contact_number, barangay, role, is_approved)
VALUES ('11111111-1111-1111-1111-111111111111', 'testreporter@test.com', 'Test Reporter', '09000000000', 'Magsaysay', 'resident', true)
ON CONFLICT (uid) DO NOTHING;

-- Create incident at Digos City center (should match responders within 3km)
INSERT INTO incidents (type, description, latitude, longitude, location, reporter_id, status, barangay)
VALUES ('other', 'TEST-match', 6.7569, 125.3469,
  ST_SetSRID(ST_MakePoint(125.3469, 6.7569), 4326)::geography,
  '11111111-1111-1111-1111-111111111111', 'reported', 'Magsaysay');

-- Check dispatches created by trigger
SELECT
  'test: match_responders creates dispatches' AS test,
  COUNT(*) AS dispatch_count,
  CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL (no responders in DB or outside 3km)' END AS result
FROM dispatches
WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-match');

-- Check dispatched responders are valid (if any)
SELECT
  'test: dispatched responders valid' AS test,
  d.responder_id,
  u.full_name,
  u.role,
  u.is_approved,
  u.responder_status,
  CASE WHEN u.role = 'responder' AND u.is_approved = true THEN 'PASS' ELSE 'FAIL' END AS result
FROM dispatches d
JOIN users u ON u.uid = d.responder_id
WHERE d.incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-match');

-- Cleanup
DELETE FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-match');
DELETE FROM incidents WHERE description = 'TEST-match';
DELETE FROM users WHERE uid = '11111111-1111-1111-1111-111111111111';