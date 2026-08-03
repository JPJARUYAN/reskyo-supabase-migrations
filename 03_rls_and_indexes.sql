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
-- TABLE PRIVILEGES (required for API access)
-- RLS policies only filter rows; roles still need
-- GRANT on the tables themselves.
-- ============================================
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;

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
