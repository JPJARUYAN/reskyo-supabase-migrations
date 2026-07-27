-- Create a test responder first, then check if the trigger query finds them
-- Run this AFTER the script creates auth users but BEFORE cleanup
-- Usage: Insert responder manually, run this query, see if it matches

-- First verify: insert a test incident and check if location gets auto-populated
INSERT INTO incidents (type, description, latitude, longitude, reporter_id, status, barangay) VALUES ('other', 'TEST-debug', 6.7569, 125.3469, (SELECT uid FROM users LIMIT 1), 'reported', 'Magsaysay');

-- Check if location was auto-populated by the BEFORE INSERT trigger
SELECT id, latitude, longitude, location IS NOT NULL AS has_location FROM incidents WHERE description = 'TEST-debug';

-- Now run the exact query the match_responders trigger uses
SELECT u.uid, b.name, haversine_km(6.7569, 125.3469, b.centroid_lat, b.centroid_lng) AS dist_km FROM users u JOIN barangays b ON b.name = u.barangay WHERE u.role = 'responder' AND u.is_approved = true AND u.responder_status = 'available' AND ST_DWithin(ST_SetSRID(ST_MakePoint(b.centroid_lng, b.centroid_lat), 4326)::geography, (SELECT location FROM incidents WHERE description = 'TEST-debug'), 3000) ORDER BY dist_km;

-- Check if dispatches were created
SELECT COUNT(*) AS dispatch_count FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-debug');

-- Cleanup
DELETE FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-debug');
DELETE FROM incidents WHERE description = 'TEST-debug';