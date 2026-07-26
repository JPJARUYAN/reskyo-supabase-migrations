# RESKYO Supabase Setup

## How to run these migrations

1. Go to https://supabase.com/dashboard
2. Select your `reskyo-digos` project
3. Click **SQL Editor** in the left sidebar
4. Click **New query**
5. Open and paste each file IN ORDER, clicking **Run** after each one:

| Order | File | What it does |
|-------|------|-------------|
| 1 | `01_enable_postgis.sql` | Enables PostGIS for geospatial queries |
| 2 | `02_create_tables.sql` | Creates all 5 tables + auto-geom trigger |
| 3 | `03_rls_and_indexes.sql` | Security policies + performance indexes |
| 4 | `04_functions_and_seed.sql` | Nearby incidents function + 26 Digos City barangays |
| 5 | `05_storage.sql` | Storage policies for incident photos |

## Then create the Storage bucket manually:

1. Go to **Storage** in the left sidebar
2. Click **New bucket**
3. Name: `incident-photos`
4. Toggle **Public** to ON
5. Click **Create bucket**
6. Then run `05_storage.sql` in the SQL Editor

## After all SQL is run, verify:

1. Go to **Table Editor** — you should see: users, incidents, dispatches, sms_logs, barangays
2. Go to **Storage** — you should see: incident-photos bucket
3. Go to **Authentication** → Users — create an admin user to test the web dashboard
