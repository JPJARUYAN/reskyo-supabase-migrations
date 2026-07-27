# Phase 9 — Local SQL Test Instructions

## Prerequisites
- Docker running
- `supabase start` already executed from this directory

## Step-by-step

### Step 1: Set up local schema (ONE TIME)
Open **Supabase Studio** at http://127.0.0.1:54323
1. Go to **SQL Editor** (left sidebar)
2. Paste the entire contents of `tests/setup_local_full.sql`
3. Click **Run**
4. Wait for "Success" — schema is now created

### Step 2: Haversine tests (5 tests)
```powershell
supabase db query --local --file tests/test_haversine.sql
```

### Step 3: match_responders trigger test
```powershell
supabase db query --local --file tests/setup_match_test.sql
supabase db query --local --file tests/setup_match_incident.sql
supabase db query --local --file tests/test_match_check.sql
```

### Step 4: sync_incident_status trigger test
```powershell
supabase db query --local --file tests/setup_sync_user.sql
supabase db query --local --file tests/setup_sync_incident.sql
supabase db query --local --file tests/setup_sync_dispatch.sql
supabase db query --local --file tests/sync_step1.sql
supabase db query --local --file tests/sync_step2.sql
supabase db query --local --file tests/sync_step3.sql
supabase db query --local --file tests/test_sync_status_check.sql
```

### Step 5: Cleanup
```powershell
supabase db query --local --file tests/cleanup_step1.sql
supabase db query --local --file tests/cleanup_step2.sql
supabase db query --local --file tests/cleanup_step3.sql
```

### Stop local stack
```powershell
supabase stop
```
