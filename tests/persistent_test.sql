-- SELF-CONTAINED TRIGGER TEST - no cleanup, leaves data for inspection
-- Run via: Supabase Studio SQL Editor at http://127.0.0.1:54323
-- OR via: docker exec psql

-- First: create auth users via PowerShell script, OR do it manually:
-- The auth users must exist before running this.

-- Step 1: Find or create responder
-- Check if any users exist
SELECT COUNT(*) AS total_users FROM users;
SELECT * FROM users LIMIT 5;

-- Step 2: Find auth user to use as reporter
-- Use any existing auth user uid for reporter_id
SELECT id FROM auth.users LIMIT 3;
