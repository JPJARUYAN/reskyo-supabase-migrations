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
