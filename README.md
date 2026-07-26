# RESKYO Supabase Setup

## How to run these migrations

1. Go to https://supabase.com/dashboard
2. Select your `reskyo-digos` project
3. Click **SQL Editor** in the left sidebar
4. Click **New query**
5. Open and paste each file IN ORDER, clicking **Run** after each one:

### Phase 1-2: Database Schema
| Order | File | What it does |
|-------|------|-------------|
| 0 | `00_cleanup.sql` | Drop old tables (only if re-running) |
| 1 | `01_enable_postgis.sql` | Enables PostGIS for geospatial queries |
| 2 | `02_create_tables.sql` | Creates all 7 tables + auto-location triggers |
| 3 | `03_rls_and_indexes.sql` | RBAC security policies + GiST indexes |
| 4 | `04_functions_and_seed.sql` | Haversine function + nearby incidents + 26 Digos City barangays |
| 5 | `05_storage.sql` | Storage policies for incident photos |

### Phase 3: Backend Logic
| Order | File | What it does |
|-------|------|-------------|
| 6 | `06_match_responders.sql` | Auto-match responders within 3km geofence |
| 7 | `07_sync_incident_status.sql` | Auto-update incident status from dispatch changes |
| 8 | `08_webhook_and_realtime.sql` | Webhook trigger + enable Realtime on incidents/dispatches |

## Then create the Storage bucket manually:

1. Go to **Storage** in the left sidebar
2. Click **New bucket**
3. Name: `incident-photos`
4. Toggle **Public** to ON
5. Click **Create bucket**
6. Then run `05_storage.sql` in the SQL Editor

## Phase 3: Deploy Edge Function (send-sms)

### Prerequisites
- Install Supabase CLI: `npm install -g supabase`
- Login: `supabase login`
- Link project: `supabase link --project-ref iurepkmnnyrxuqqzmfvy`

### Deploy
```bash
cd supabase_migration/edge_functions
supabase functions deploy send-sms
```

### Set Secrets
```bash
supabase secrets set SMS_GATEWAY_URL=http://YOUR_GATEWAY_IP:8080/message
supabase secrets set SMS_GATEWAY_API_KEY=your_api_key
```

### Setup Webhook in Dashboard
1. Go to **Database** → **Webhooks** → **Create webhook**
2. Name: `send-sms-on-dispatch`
3. Table: `dispatches`
4. Events: `INSERT`
5. Type: HTTP Request
6. Method: POST
7. URL: `https://iurepkmnnyrxuqqzmfvy.supabase.co/functions/v1/send-sms`
8. Headers: `Authorization: Bearer <your-anon-key>`

## After all SQL is run, verify:

1. Go to **Table Editor** — you should see: users, incidents, dispatches, sms_logs, barangays, road_nodes, road_edges
2. Go to **Storage** — you should see: incident-photos bucket
3. Go to **Authentication** → Users — create an admin user to test the web dashboard
4. Go to **Database** → **Replication** — confirm incidents and dispatches are enabled for Realtime
