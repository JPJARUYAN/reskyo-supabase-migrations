-- ============================================
-- PHASE 3, Step 1: match_responders()
-- Geofencing-Based Nearest Responder Dispatch
-- (Chapter III, 3.2.1)
--
-- Runs AFTER INSERT on incidents.
-- Uses PostGIS ST_DWithin for geofence boundary,
-- haversine_km for proximity ranking.
-- ============================================

CREATE OR REPLACE FUNCTION match_responders()
RETURNS TRIGGER AS $$
DECLARE
  matched_responder RECORD;
  dispatch_id UUID;
BEGIN
  -- Only auto-match for reported incidents
  IF NEW.status != 'reported' THEN
    RETURN NEW;
  END IF;

  -- Find available, approved responders within 3km geofence
  -- ST_DWithin uses geography cast for meter-based distance
  FOR matched_responder IN
    SELECT
      u.uid,
      haversine_km(NEW.latitude, NEW.longitude, b.centroid_lat, b.centroid_lng) AS distance_km
    FROM users u
    JOIN barangays b ON b.name = u.barangay
    WHERE u.role = 'responder'
      AND u.is_approved = true
      AND u.responder_status = 'available'
      AND ST_DWithin(
        ST_SetSRID(ST_MakePoint(b.centroid_lng, b.centroid_lat), 4326)::geography,
        NEW.location,
        3000  -- 3km geofence radius in meters
      )
    ORDER BY distance_km ASC
    LIMIT 5  -- Max 5 responders per incident
  LOOP
    -- Insert dispatch for each matched responder
    INSERT INTO dispatches (incident_id, responder_id, status, dispatched_at)
    VALUES (NEW.id, matched_responder.uid, 'pending', now())
    RETURNING id INTO dispatch_id;

    -- Log for debugging (visible in Supabase logs)
    RAISE NOTICE 'Dispatched to responder % (%.1f km away)',
      matched_responder.uid, matched_responder.distance_km;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS trg_match_responders ON incidents;
CREATE TRIGGER trg_match_responders
  AFTER INSERT ON incidents
  FOR EACH ROW
  EXECUTE FUNCTION match_responders();
