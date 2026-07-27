-- Run all migrations on local Supabase first
-- Execute: supabase db query --local --file tests/setup_local.sql

\ir ../01_enable_postgis.sql
\ir ../02_create_tables.sql
\ir ../03_rls_and_indexes.sql
\ir ../04_functions_and_seed.sql
\ir ../06_match_responders.sql
\ir ../07_sync_incident_status.sql
\ir ../09_snap_to_node.sql
\ir ../10_fcm_push.sql
