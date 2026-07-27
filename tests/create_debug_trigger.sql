CREATE OR REPLACE FUNCTION match_responders_debug()
RETURNS TRIGGER AS $$
DECLARE
  matched_responder RECORD;
  dispatch_id UUID;
  responder_count INTEGER;
BEGIN
  IF NEW.status != 'reported' THEN
    RAISE NOTICE 'match_responders: skipping, status=%', NEW.status;
    RETURN NEW;
  END IF;

  RAISE NOTICE 'match_responders: processing incident %, location=%, lat=%, lng=%', NEW.id, NEW.location, NEW.latitude, NEW.longitude;

  SELECT COUNT(*) INTO responder_count
  FROM users u
  JOIN barangays b ON b.name = u.barangay
  WHERE u.role = 'responder'
    AND u.is_approved = true
    AND u.responder_status = 'available';

  RAISE NOTICE 'match_responders: found % available responders total', responder_count;

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
        3000
      )
    ORDER BY distance_km ASC
    LIMIT 5
  LOOP
    INSERT INTO dispatches (incident_id, responder_id, status, dispatched_at)
    VALUES (NEW.id, matched_responder.uid, 'pending', now())
    RETURNING id INTO dispatch_id;

    RAISE NOTICE 'match_responders: DISPATCHED to responder % (%.1f km away)', matched_responder.uid, matched_responder.distance_km;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
