-- ============================================
-- PHASE 2, Step 7: Haversine Function + Helpers
-- Run AFTER 03_rls_and_indexes.sql
-- ============================================

-- ============================================
-- HAVERSINE DISTANCE FUNCTION (Chapter III, 3.2.2)
-- Returns distance in kilometers between two lat/lng points.
-- This is the citable, explicit implementation for defense.
-- ============================================
CREATE OR REPLACE FUNCTION haversine_km(
  lat1 DOUBLE PRECISION,
  lng1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lng2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  r DOUBLE PRECISION := 6371;  -- Earth radius in km
  dlat DOUBLE PRECISION;
  dlng DOUBLE PRECISION;
  a DOUBLE PRECISION;
BEGIN
  dlat := radians(lat2 - lat1);
  dlng := radians(lng2 - lng1);
  a := sin(dlat / 2)^2
     + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2)^2;
  RETURN r * 2 * atan2(sqrt(a), sqrt(1 - a));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================
-- GET NEARBY INCIDENTS
-- Uses PostGIS ST_DWithin for the radius filter (fast),
-- then haversine_km for exact distance display.
-- Called by: supabase.rpc('get_nearby_incidents', {
--   user_lat: ..., user_lng: ..., radius_km: 5.0
-- })
-- ============================================
CREATE OR REPLACE FUNCTION get_nearby_incidents(
  user_lat DOUBLE PRECISION,
  user_lng DOUBLE PRECISION,
  radius_km DOUBLE PRECISION DEFAULT 5.0
)
RETURNS TABLE (
  id UUID,
  type TEXT,
  description TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  address TEXT,
  reporter_id UUID,
  status TEXT,
  photo_url TEXT,
  barangay TEXT,
  created_at TIMESTAMPTZ,
  distance_km DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    i.id,
    i.type,
    i.description,
    i.latitude,
    i.longitude,
    i.address,
    i.reporter_id,
    i.status,
    i.photo_url,
    i.barangay,
    i.created_at,
    haversine_km(user_lat, user_lng, i.latitude, i.longitude) AS distance_km
  FROM incidents i
  WHERE ST_DWithin(
    i.location,
    ST_SetSRID(ST_MakePoint(user_lng, user_lat), 4326)::geography,
    radius_km * 1000
  )
  AND i.status NOT IN ('resolved', 'dismissed')
  ORDER BY distance_km ASC;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- RANK RESPONDERS BY PROXIMITY TO INCIDENT
-- Returns responders sorted by distance (nearest first).
-- Used by admin dispatch screen to suggest closest responder.
-- ============================================
CREATE OR REPLACE FUNCTION rank_responders_by_proximity(
  incident_lat DOUBLE PRECISION,
  incident_lng DOUBLE PRECISION,
  max_results INTEGER DEFAULT 5
)
RETURNS TABLE (
  uid UUID,
  full_name TEXT,
  contact_number TEXT,
  barangay TEXT,
  responder_status TEXT,
  distance_km DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    u.uid,
    u.full_name,
    u.contact_number,
    u.barangay,
    u.responder_status,
    haversine_km(incident_lat, incident_lng, u_responder_lat, u_responder_lng) AS distance_km
  FROM (
    SELECT
      uid,
      full_name,
      contact_number,
      barangay,
      responder_status,
      -- Use responder's barangay centroid as approximate location
      b.centroid_lat AS u_responder_lat,
      b.centroid_lng AS u_responder_lng
    FROM users u2
    JOIN barangays b ON b.name = u2.barangay
    WHERE u2.role = 'responder'
      AND u2.is_approved = true
      AND u2.responder_status = 'available'
  ) u
  ORDER BY distance_km ASC
  LIMIT max_results;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- AUTO-CREATE USER PROFILE ON SIGNUP
-- ============================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (uid, email, full_name, contact_number, barangay, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'contact_number', ''),
    COALESCE(NEW.raw_user_meta_data->>'barangay', ''),
    COALESCE(NEW.raw_user_meta_data->>'role', 'resident')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();

-- ============================================
-- SEED: Digos City 26 Barangays
-- ============================================
INSERT INTO barangays (name, centroid_lat, centroid_lng) VALUES
  ('Aplaya', 6.7265, 125.3729),
  ('Balabag', 6.7585, 125.3269),
  ('Baluntaya', 6.7148, 125.3589),
  ('Caladian', 6.7138, 125.3464),
  ('Calinan', 6.7549, 125.3189),
  ('Cagangohan', 6.7305, 125.3614),
  ('Cervantes', 6.7224, 125.3864),
  ('Concolon', 6.7399, 125.3399),
  ('Dacudao', 6.7814, 125.3124),
  ('Dakidali', 6.7674, 125.3089),
  ('Damires', 6.7859, 125.3369),
  ('Dawis', 6.7539, 125.3539),
  ('Dulangan', 6.7669, 125.3399),
  ('Goma', 6.7429, 125.3214),
  ('Hubang', 6.7149, 125.3734),
  ('Kapitan Elen', 6.7129, 125.3529),
  ('Kiblawan', 6.7694, 125.3539),
  ('Kinencita', 6.7729, 125.3199),
  ('Magsaysay', 6.7529, 125.3469),
  ('Managa', 6.7289, 125.3839),
  ('Marber', 6.7329, 125.3324),
  ('Ruparan', 6.7639, 125.3124),
  ('San Agustin', 6.7349, 125.3429),
  ('San Miguel', 6.7249, 125.3529),
  ('Tibal-og', 6.7619, 125.3324),
  ('Tungayan', 6.7449, 125.3639)
ON CONFLICT (name) DO NOTHING;
