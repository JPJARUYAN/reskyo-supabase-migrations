-- ============================================
-- PHASE 2: Enable PostGIS extension
-- Run in Supabase SQL Editor â†’ New query â†’ Run
-- ============================================
CREATE EXTENSION IF NOT EXISTS postgis;


-- ============================================
-- PHASE 2, Step 1-2: Create all tables
-- Run AFTER 01_enable_postgis.sql
-- ============================================

-- ============================================
-- 1. USERS (linked to auth.users via uid FK)
-- ============================================
CREATE TABLE IF NOT EXISTS users (
  uid UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  contact_number TEXT NOT NULL,
  barangay TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('resident', 'responder', 'admin')),
  is_approved BOOLEAN NOT NULL DEFAULT false,
  photo_url TEXT,
  responder_status TEXT DEFAULT 'offline' CHECK (responder_status IN ('available', 'busy', 'offline')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================
-- 2. INCIDENTS
-- ============================================
CREATE TABLE IF NOT EXISTS incidents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN (
    'vehicularAccident', 'medicalEmergency', 'fire',
    'rescueOperation', 'other'
  )),
  description TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  address TEXT,
  reporter_id UUID NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'reported' CHECK (status IN (
    'reported', 'verified', 'dispatched', 'inProgress', 'resolved', 'dismissed'
  )),
  photo_url TEXT,
  verified_by UUID REFERENCES users(uid),
  barangay TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- PostGIS geography column for geospatial queries (Phase 2)
  location geography(Point, 4326)
);

-- ============================================
-- 3. DISPATCHES
-- ============================================
CREATE TABLE IF NOT EXISTS dispatches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  responder_id UUID NOT NULL REFERENCES users(uid) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'accepted', 'enRoute', 'onScene', 'resolved'
  )),
  dispatched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at TIMESTAMPTZ,
  en_route_at TIMESTAMPTZ,
  arrived_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  notes TEXT
);

-- ============================================
-- 4. SMS LOGS
-- ============================================
CREATE TABLE IF NOT EXISTS sms_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dispatch_id UUID NOT NULL REFERENCES dispatches(id) ON DELETE CASCADE,
  phone_number TEXT NOT NULL,
  message TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'sent',
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  error_message TEXT
);

-- ============================================
-- 5. BARANGAYS
-- ============================================
CREATE TABLE IF NOT EXISTS barangays (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  centroid_lat DOUBLE PRECISION NOT NULL,
  centroid_lng DOUBLE PRECISION NOT NULL,
  boundary GEOMETRY(Polygon, 4326)
);

-- ============================================
-- 6. ROAD NODES (for A* routing, Phase 4)
-- ============================================
CREATE TABLE IF NOT EXISTS road_nodes (
  id SERIAL PRIMARY KEY,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  node_type TEXT DEFAULT 'intersection' CHECK (node_type IN (
    'intersection', 'turn', 'landmark', 'barangay_center'
  )),
  label TEXT,
  location geography(Point, 4326)
);

-- ============================================
-- 7. ROAD EDGES (for A* routing, Phase 4)
-- ============================================
CREATE TABLE IF NOT EXISTS road_edges (
  id SERIAL PRIMARY KEY,
  from_node INTEGER NOT NULL REFERENCES road_nodes(id) ON DELETE CASCADE,
  to_node INTEGER NOT NULL REFERENCES road_nodes(id) ON DELETE CASCADE,
  distance_meters DOUBLE PRECISION NOT NULL,
  road_name TEXT,
  is_paved BOOLEAN DEFAULT true,
  weight DOUBLE PRECISION NOT NULL DEFAULT 1.0
);

-- ============================================
-- Auto-update location geography from lat/lng
-- ============================================
CREATE OR REPLACE FUNCTION update_incident_location()
RETURNS TRIGGER AS $$
BEGIN
  NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_incident_location ON incidents;
CREATE TRIGGER trg_update_incident_location
  BEFORE INSERT OR UPDATE ON incidents
  FOR EACH ROW
  EXECUTE FUNCTION update_incident_location();

CREATE OR REPLACE FUNCTION update_road_node_location()
RETURNS TRIGGER AS $$
BEGIN
  NEW.location := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_road_node_location ON road_nodes;
CREATE TRIGGER trg_update_road_node_location
  BEFORE INSERT OR UPDATE ON road_nodes
  FOR EACH ROW
  EXECUTE FUNCTION update_road_node_location();


-- ============================================
-- PHASE 2, Step 3-4: Row Level Security + RBAC
-- Run AFTER 02_create_tables.sql
-- ============================================

-- Enable RLS on every table (Phase 2, Step 3)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE dispatches ENABLE ROW LEVEL SECURITY;
ALTER TABLE sms_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE barangays ENABLE ROW LEVEL SECURITY;
ALTER TABLE road_nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE road_edges ENABLE ROW LEVEL SECURITY;

-- ============================================
-- HELPER: Check user role (avoids repeating subquery)
-- ============================================
CREATE OR REPLACE FUNCTION auth_user_role()
RETURNS TEXT AS $$
  SELECT role FROM users WHERE uid = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION auth_user_approved()
RETURNS BOOLEAN AS $$
  SELECT COALESCE(is_approved, false) FROM users WHERE uid = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================
-- USERS TABLE POLICIES
-- ============================================

-- All authenticated users can read profiles (needed for names, contact info)
CREATE POLICY "users_select_authenticated"
  ON users FOR SELECT
  TO authenticated
  USING (true);

-- Users can only update their own profile
CREATE POLICY "users_update_own"
  ON users FOR UPDATE
  TO authenticated
  USING (uid = auth.uid())
  WITH CHECK (uid = auth.uid());

-- Registration inserts (user creates their own profile)
CREATE POLICY "users_insert_own"
  ON users FOR INSERT
  TO authenticated
  WITH CHECK (uid = auth.uid());

-- Admins can update any user (approve responders, manage accounts)
CREATE POLICY "admin_update_all_users"
  ON users FOR UPDATE
  TO authenticated
  USING (auth_user_role() = 'admin')
  WITH CHECK (auth_user_role() = 'admin');

-- ============================================
-- INCIDENTS TABLE POLICIES (RBAC)
-- ============================================

-- Residents can SELECT only their own incidents
CREATE POLICY "residents_select_own_incidents"
  ON incidents FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

-- Responders can SELECT incidents assigned to them via dispatches
CREATE POLICY "responders_select_assigned_incidents"
  ON incidents FOR SELECT
  TO authenticated
  USING (
    auth_user_role() = 'responder'
    AND auth_user_approved() = true
    AND id IN (
      SELECT incident_id FROM dispatches
      WHERE responder_id = auth.uid()
    )
  );

-- Admins can SELECT all incidents (full visibility)
CREATE POLICY "admin_select_all_incidents"
  ON incidents FOR SELECT
  TO authenticated
  USING (auth_user_role() = 'admin');

-- Residents can INSERT incidents (they are the reporter)
CREATE POLICY "residents_insert_incidents"
  ON incidents FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- Residents can UPDATE their own incidents (e.g. add info)
CREATE POLICY "residents_update_own_incidents"
  ON incidents FOR UPDATE
  TO authenticated
  USING (reporter_id = auth.uid())
  WITH CHECK (reporter_id = auth.uid());

-- Admins can UPDATE any incident (verify, dismiss, change status)
CREATE POLICY "admin_update_all_incidents"
  ON incidents FOR UPDATE
  TO authenticated
  USING (auth_user_role() = 'admin')
  WITH CHECK (auth_user_role() = 'admin');

-- ============================================
-- DISPATCHES TABLE POLICIES (RBAC)
-- ============================================

-- Admins can SELECT all dispatches
CREATE POLICY "admin_select_all_dispatches"
  ON dispatches FOR SELECT
  TO authenticated
  USING (auth_user_role() = 'admin');

-- Responders can SELECT only their own dispatches
CREATE POLICY "responders_select_own_dispatches"
  ON dispatches FOR SELECT
  TO authenticated
  USING (
    responder_id = auth.uid()
    AND auth_user_role() = 'responder'
  );

-- Reporters can see dispatches for their incidents
CREATE POLICY "reporters_select_dispatches_for_own_incidents"
  ON dispatches FOR SELECT
  TO authenticated
  USING (
    incident_id IN (
      SELECT id FROM incidents WHERE reporter_id = auth.uid()
    )
  );

-- Admins can INSERT dispatches (assign responders)
CREATE POLICY "admin_insert_dispatches"
  ON dispatches FOR INSERT
  TO authenticated
  WITH CHECK (auth_user_role() = 'admin');

-- Admins can UPDATE any dispatch
CREATE POLICY "admin_update_all_dispatches"
  ON dispatches FOR UPDATE
  TO authenticated
  USING (auth_user_role() = 'admin')
  WITH CHECK (auth_user_role() = 'admin');

-- Responders can UPDATE only their own dispatch (accept, mark en route, etc.)
CREATE POLICY "responders_update_own_dispatches"
  ON dispatches FOR UPDATE
  TO authenticated
  USING (
    responder_id = auth.uid()
    AND auth_user_role() = 'responder'
  )
  WITH CHECK (
    responder_id = auth.uid()
  );

-- ============================================
-- SMS LOGS TABLE POLICIES
-- ============================================

-- Admins can view all SMS logs
CREATE POLICY "admin_select_all_sms_logs"
  ON sms_logs FOR SELECT
  TO authenticated
  USING (auth_user_role() = 'admin');

-- System can insert SMS logs
CREATE POLICY "authenticated_insert_sms_logs"
  ON sms_logs FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- ============================================
-- BARANGAYS TABLE POLICIES
-- ============================================

-- Everyone authenticated can read barangays
CREATE POLICY "authenticated_select_barangays"
  ON barangays FOR SELECT
  TO authenticated
  USING (true);

-- Admins can manage barangays
CREATE POLICY "admin_manage_barangays"
  ON barangays FOR ALL
  TO authenticated
  USING (auth_user_role() = 'admin')
  WITH CHECK (auth_user_role() = 'admin');

-- ============================================
-- ROAD NODES/EDGES TABLE POLICIES
-- ============================================

-- Everyone authenticated can read road data (needed for routing)
CREATE POLICY "authenticated_select_road_nodes"
  ON road_nodes FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "authenticated_select_road_edges"
  ON road_edges FOR SELECT
  TO authenticated
  USING (true);

-- Admins can manage road data
CREATE POLICY "admin_manage_road_nodes"
  ON road_nodes FOR ALL
  TO authenticated
  USING (auth_user_role() = 'admin')
  WITH CHECK (auth_user_role() = 'admin');

CREATE POLICY "admin_manage_road_edges"
  ON road_edges FOR ALL
  TO authenticated
  USING (auth_user_role() = 'admin')
  WITH CHECK (auth_user_role() = 'admin');

-- ============================================
-- PHASE 2, Step 6: Indexes
-- ============================================

-- Incident query indexes
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_reporter ON incidents(reporter_id);
CREATE INDEX IF NOT EXISTS idx_incidents_barangay ON incidents(barangay);
CREATE INDEX IF NOT EXISTS idx_incidents_created ON incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_status_created ON incidents(status, created_at DESC);

-- GiST index on incidents.location for fast radius lookups (Phase 2, Step 6)
CREATE INDEX IF NOT EXISTS idx_incidents_location_gist ON incidents USING GIST(location);

-- Dispatch query indexes
CREATE INDEX IF NOT EXISTS idx_dispatches_responder ON dispatches(responder_id);
CREATE INDEX IF NOT EXISTS idx_dispatches_incident ON dispatches(incident_id);
CREATE INDEX IF NOT EXISTS idx_dispatches_status ON dispatches(status);
CREATE INDEX IF NOT EXISTS idx_dispatches_responder_status ON dispatches(responder_id, status);

-- User query indexes
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_barangay ON users(barangay);
CREATE INDEX IF NOT EXISTS idx_users_role_approved ON users(role, is_approved);

-- SMS log indexes
CREATE INDEX IF NOT EXISTS idx_sms_logs_dispatch ON sms_logs(dispatch_id);

-- Road network indexes (Phase 4 prep)
CREATE INDEX IF NOT EXISTS idx_road_nodes_location_gist ON road_nodes USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_road_edges_from ON road_edges(from_node);
CREATE INDEX IF NOT EXISTS idx_road_edges_to ON road_edges(to_node);


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


-- ============================================
-- PHASE 3, Step 4: sync_incident_status()
-- Auto-updates parent incident.status when
-- a dispatch status changes.
-- ============================================

CREATE OR REPLACE FUNCTION sync_incident_status()
RETURNS TRIGGER AS $$
BEGIN
  -- When dispatch is accepted, update incident to 'dispatched'
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    UPDATE incidents
    SET status = 'dispatched',
        updated_at = now()
    WHERE id = NEW.incident_id;

  -- When responder is en route, update incident to 'inProgress'
  ELSIF NEW.status = 'enRoute' AND OLD.status = 'accepted' THEN
    UPDATE incidents
    SET status = 'inProgress',
        updated_at = now()
    WHERE id = NEW.incident_id;

  -- When responder arrives on scene, keep 'inProgress'
  ELSIF NEW.status = 'onScene' AND OLD.status = 'enRoute' THEN
    UPDATE incidents
    SET status = 'inProgress',
        updated_at = now()
    WHERE id = NEW.incident_id;

  -- When dispatch is resolved, check if ALL dispatches for this incident are resolved
  ELSIF NEW.status = 'resolved' THEN
    -- If no more active dispatches, mark incident as resolved
    IF NOT EXISTS (
      SELECT 1 FROM dispatches
      WHERE incident_id = NEW.incident_id
        AND status NOT IN ('resolved')
        AND id != NEW.id
    ) THEN
      UPDATE incidents
      SET status = 'resolved',
          updated_at = now()
      WHERE id = NEW.incident_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS trg_sync_incident_status ON dispatches;
CREATE TRIGGER trg_sync_incident_status
  AFTER UPDATE OF status ON dispatches
  FOR EACH ROW
  EXECUTE FUNCTION sync_incident_status();


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


-- ============================================
-- PHASE 6: FCM Push Notification Trigger
-- Sends push notification to responder when
-- a new dispatch is created.
-- ============================================

-- Enable http extension (if not already)
CREATE EXTENSION IF NOT EXISTS http;

-- Function to send push notification when dispatch is created
CREATE OR REPLACE FUNCTION trigger_send_push_notification()
RETURNS TRIGGER AS $$
DECLARE
  responder_fcm TEXT;
  anon_key TEXT;
  supabase_url TEXT;
BEGIN
  -- Get the responder's FCM token
  SELECT fcm_token INTO responder_fcm
  FROM users
  WHERE uid = NEW.responder_id;

  -- Get Supabase config
  supabase_url := current_setting('app.settings.supabase_url', true);
  anon_key := current_setting('app.settings.anon_key', true);

  -- If token exists, send push via Edge Function
  IF responder_fcm IS NOT NULL AND responder_fcm != '' THEN
    IF supabase_url IS NOT NULL AND anon_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := supabase_url || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || anon_key
        ),
        body := jsonb_build_object(
          'fcm_token', responder_fcm,
          'title', 'RESKYO - New Dispatch',
          'body', 'You have a new emergency dispatch assignment',
          'dispatch_id', NEW.id::text
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trg_send_push ON dispatches;
CREATE TRIGGER trg_send_push
  AFTER INSERT ON dispatches
  FOR EACH ROW
  EXECUTE FUNCTION trigger_send_push_notification();

