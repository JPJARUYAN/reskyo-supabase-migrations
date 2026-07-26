-- ============================================
-- CLEANUP: Drop old tables before re-running Phase 2
-- ONLY run this if you already ran Phase 1 SQL files
-- Run in Supabase SQL Editor → New query → Run
-- ============================================

-- Drop triggers first
DROP TRIGGER IF EXISTS trg_update_incident_geom ON incidents;
DROP TRIGGER IF EXISTS trg_update_incident_location ON incidents;
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions
DROP FUNCTION IF EXISTS update_incident_geom();
DROP FUNCTION IF EXISTS update_incident_location();
DROP FUNCTION IF EXISTS handle_new_user();
DROP FUNCTION IF EXISTS get_nearby_incidents(double precision, double precision, double precision);
DROP FUNCTION IF EXISTS haversine_km(double precision, double precision, double precision, double precision);
DROP FUNCTION IF EXISTS rank_responders_by_proximity(double precision, double precision, integer);
DROP FUNCTION IF EXISTS auth_user_role();
DROP FUNCTION IF EXISTS auth_user_approved();

-- Drop tables (in order due to foreign keys)
DROP TABLE IF EXISTS sms_logs CASCADE;
DROP TABLE IF EXISTS dispatches CASCADE;
DROP TABLE IF EXISTS incidents CASCADE;
DROP TABLE IF EXISTS road_edges CASCADE;
DROP TABLE IF EXISTS road_nodes CASCADE;
DROP TABLE IF EXISTS barangays CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Drop storage policies
DROP POLICY IF EXISTS "Users can upload incident photos" ON storage.objects;
DROP POLICY IF EXISTS "Public can view incident photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own incident photos" ON storage.objects;
