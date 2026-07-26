-- ============================================
-- PHASE 4, Step 3: Snap-to-node helper function
-- Used by compute-route Edge Function
-- ============================================

CREATE OR REPLACE FUNCTION snap_to_nearest_node(
  input_lat DOUBLE PRECISION,
  input_lng DOUBLE PRECISION
)
RETURNS TABLE (
  id INTEGER,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  distance_meters DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    rn.id,
    rn.latitude,
    rn.longitude,
    haversine_km(input_lat, input_lng, rn.latitude, rn.longitude) * 1000 AS distance_meters
  FROM road_nodes rn
  ORDER BY rn.location <-> ST_SetSRID(ST_MakePoint(input_lng, input_lat), 4326)::geography
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;
