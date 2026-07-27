-- ============================================
-- PHASE 9: Unit Tests — sync_incident_status()
-- Self-contained: creates test user, incident, dispatch
-- ============================================

-- Create temp test user
INSERT INTO users (uid, email, full_name, contact_number, barangay, role, is_approved)
VALUES ('11111111-1111-1111-1111-111111111111', 'test@test.com', 'Test User', '09000000000', 'Magsaysay', 'resident', true)
ON CONFLICT (uid) DO NOTHING;

-- Create incident
INSERT INTO incidents (type, description, latitude, longitude, location, reporter_id, status, barangay)
VALUES ('other', 'TEST-sync', 6.7569, 125.3469,
  ST_SetSRID(ST_MakePoint(125.3469, 6.7569), 4326)::geography,
  '11111111-1111-1111-1111-111111111111', 'verified', 'Magsaysay');

-- Create dispatch
INSERT INTO dispatches (incident_id, responder_id, status, dispatched_at)
SELECT id, '11111111-1111-1111-1111-111111111111', 'pending', now()
FROM incidents WHERE description = 'TEST-sync';

-- TEST 1: pending → accepted → incident becomes 'dispatched'
UPDATE dispatches SET status = 'accepted'
WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync');

SELECT 'test1: accepted → dispatched' AS test, i.status AS got,
  CASE WHEN i.status = 'dispatched' THEN 'PASS' ELSE 'FAIL' END AS result
FROM incidents i WHERE i.description = 'TEST-sync';

-- TEST 2: accepted → enRoute → incident becomes 'inProgress'
UPDATE dispatches SET status = 'enRoute'
WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync');

SELECT 'test2: enRoute → inProgress' AS test, i.status AS got,
  CASE WHEN i.status = 'inProgress' THEN 'PASS' ELSE 'FAIL' END AS result
FROM incidents i WHERE i.description = 'TEST-sync';

-- TEST 3: enRoute → resolved → incident becomes 'resolved'
UPDATE dispatches SET status = 'resolved'
WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync');

SELECT 'test3: resolved → resolved' AS test, i.status AS got,
  CASE WHEN i.status = 'resolved' THEN 'PASS' ELSE 'FAIL' END AS result
FROM incidents i WHERE i.description = 'TEST-sync';

-- Cleanup
DELETE FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync');
DELETE FROM incidents WHERE description = 'TEST-sync';
DELETE FROM users WHERE uid = '11111111-1111-1111-1111-111111111111';