$ErrorActionPreference = "Stop"

$API = "http://127.0.0.1:54321"
$SERVICE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"
$headers = @{ "apikey" = $SERVICE_KEY; "Authorization" = "Bearer $SERVICE_KEY"; "Content-Type" = "application/json" }

function SQL($query) {
    $query | supabase db query --local 2>&1
}

# ─── Schema fixes (idempotent) ───
Write-Host "=== Applying schema fixes ==="
SQL "ALTER TABLE users ADD COLUMN IF NOT EXISTS fcm_token TEXT;"
SQL "ALTER TABLE users ADD COLUMN IF NOT EXISTS phone_verified BOOLEAN DEFAULT false;"

# ─── Create auth users ───
Write-Host "`n=== Creating auth users ==="
try {
    $r1 = Invoke-RestMethod -Uri "$API/auth/v1/admin/users" -Method POST -Headers $headers -Body '{"email":"testreporter@test.com","password":"testpass123","email_confirm":true}'
    $reporterId = $r1.id
    Write-Host "Reporter: $reporterId"
} catch {
    $existing = Invoke-RestMethod -Uri "$API/auth/v1/admin/users" -Method GET -Headers $headers
    $reporterId = ($existing.users | Where-Object { $_.email -eq "testreporter@test.com" }).id
    Write-Host "Reporter (existing): $reporterId"
}

try {
    $r2 = Invoke-RestMethod -Uri "$API/auth/v1/admin/users" -Method POST -Headers $headers -Body '{"email":"testresponder@test.com","password":"testpass123","email_confirm":true}'
    $responderId = $r2.id
    Write-Host "Responder: $responderId"
} catch {
    $existing = Invoke-RestMethod -Uri "$API/auth/v1/admin/users" -Method GET -Headers $headers
    $responderId = ($existing.users | Where-Object { $_.email -eq "testresponder@test.com" }).id
    Write-Host "Responder (existing): $responderId"
}

try {
    $r3 = Invoke-RestMethod -Uri "$API/auth/v1/admin/users" -Method POST -Headers $headers -Body '{"email":"testsyncuser@test.com","password":"testpass123","email_confirm":true}'
    $syncId = $r3.id
    Write-Host "Sync User: $syncId"
} catch {
    $existing = Invoke-RestMethod -Uri "$API/auth/v1/admin/users" -Method GET -Headers $headers
    $syncId = ($existing.users | Where-Object { $_.email -eq "testsyncuser@test.com" }).id
    Write-Host "Sync User (existing): $syncId"
}

# ─── Insert into public.users (no location column!) ───
Write-Host "`n=== Inserting users ==="
SQL "INSERT INTO users (uid, email, full_name, contact_number, barangay, role, is_approved, responder_status) VALUES ('$reporterId', 'testreporter@test.com', 'Test Reporter', '09000000000', 'Magsaysay', 'resident', true, 'offline') ON CONFLICT (uid) DO UPDATE SET role = 'resident', is_approved = true;"
SQL "INSERT INTO users (uid, email, full_name, contact_number, barangay, role, is_approved, responder_status) VALUES ('$responderId', 'testresponder@test.com', 'Test Responder', '09000000001', 'Magsaysay', 'responder', true, 'available') ON CONFLICT (uid) DO UPDATE SET role = 'responder', is_approved = true, responder_status = 'available';"
SQL "INSERT INTO users (uid, email, full_name, contact_number, barangay, role, is_approved, responder_status) VALUES ('$syncId', 'testsyncuser@test.com', 'Test Sync User', '09000000002', 'Magsaysay', 'resident', true, 'offline') ON CONFLICT (uid) DO UPDATE SET role = 'resident', is_approved = true;"

# ─── Verify users exist ───
Write-Host "`n=== Verifying users ==="
SQL "SELECT uid, email, role, is_approved, responder_status FROM users WHERE uid IN ('$reporterId', '$responderId', '$syncId');"

# ─── TEST 1: Haversine ───
Write-Host "`n=== TEST 1: Haversine (5 assertions) ==="
SQL "SELECT 'test1: same point = 0' AS test, CASE WHEN haversine_km(6.7569, 125.3469, 6.7569, 125.3469) = 0.0 THEN 'PASS' ELSE 'FAIL' END AS result, haversine_km(6.7569, 125.3469, 6.7569, 125.3469) AS actual_km UNION ALL SELECT 'test2: Digos-Mati ~99km', CASE WHEN haversine_km(6.7569, 125.3469, 6.9533, 126.2194) BETWEEN 90 AND 110 THEN 'PASS' ELSE 'FAIL' END, round(haversine_km(6.7569, 125.3469, 6.9533, 126.2194)::numeric, 1) UNION ALL SELECT 'test3: 1deg lat ~111km', CASE WHEN haversine_km(6.0, 125.0, 7.0, 125.0) BETWEEN 105 AND 117 THEN 'PASS' ELSE 'FAIL' END, round(haversine_km(6.0, 125.0, 7.0, 125.0)::numeric, 1) UNION ALL SELECT 'test4: symmetry', CASE WHEN abs(haversine_km(6.75, 125.34, 6.78, 125.38) - haversine_km(6.78, 125.38, 6.75, 125.34)) < 0.001 THEN 'PASS' ELSE 'FAIL' END, round(haversine_km(6.75, 125.34, 6.78, 125.38)::numeric, 3) UNION ALL SELECT 'test5: nearby barangays ~1km', CASE WHEN haversine_km(6.7529, 125.3469, 6.7539, 125.3539) BETWEEN 0.5 AND 3.0 THEN 'PASS' ELSE 'FAIL' END, round(haversine_km(6.7529, 125.3469, 6.7539, 125.3539)::numeric, 3);"

# ─── TEST 2: match_responders trigger ───
Write-Host "`n=== TEST 2: match_responders trigger ==="
SQL "INSERT INTO incidents (type, description, latitude, longitude, reporter_id, status, barangay) VALUES ('other', 'TEST-match', 6.7569, 125.3469, '$reporterId', 'reported', 'Magsaysay');"
SQL "SELECT 'match_test' AS test, COUNT(*) AS dispatch_count, CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END AS result FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-match');"

# ─── TEST 3: sync_incident_status trigger ───
Write-Host "`n=== TEST 3: sync_incident_status trigger ==="
SQL "INSERT INTO incidents (type, description, latitude, longitude, reporter_id, status, barangay) VALUES ('other', 'TEST-sync', 6.7569, 125.3469, '$syncId', 'verified', 'Magsaysay');"
SQL "INSERT INTO dispatches (incident_id, responder_id, status, dispatched_at) SELECT id, '$responderId', 'pending', now() FROM incidents WHERE description = 'TEST-sync';"

Write-Host "Step 1: pending -> accepted (should set incident to 'dispatched')"
SQL "UPDATE dispatches SET status = 'accepted' WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync') AND status = 'pending' RETURNING status;"
SQL "SELECT status FROM incidents WHERE description = 'TEST-sync';"

Write-Host "Step 2: accepted -> enRoute (should set incident to 'inProgress')"
SQL "UPDATE dispatches SET status = 'enRoute' WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync') AND status = 'accepted' RETURNING status;"
SQL "SELECT status FROM incidents WHERE description = 'TEST-sync';"

Write-Host "Step 3: enRoute -> resolved (should set incident to 'resolved')"
SQL "UPDATE dispatches SET status = 'resolved' WHERE incident_id IN (SELECT id FROM incidents WHERE description = 'TEST-sync') AND status = 'enRoute' RETURNING status;"
SQL "SELECT 'sync_final' AS test, description, status AS final_status, CASE WHEN status = 'resolved' THEN 'PASS' ELSE 'FAIL' END AS result FROM incidents WHERE description = 'TEST-sync';"

# ─── Cleanup ───
Write-Host "`n=== Cleanup ==="
SQL "DELETE FROM dispatches WHERE incident_id IN (SELECT id FROM incidents WHERE description IN ('TEST-sync', 'TEST-match'));"
SQL "DELETE FROM incidents WHERE description IN ('TEST-sync', 'TEST-match');"
SQL "DELETE FROM users WHERE uid IN ('$reporterId', '$responderId', '$syncId');"
Invoke-RestMethod -Uri "$API/auth/v1/admin/users/$reporterId" -Method DELETE -Headers $headers 2>$null | Out-Null
Invoke-RestMethod -Uri "$API/auth/v1/admin/users/$responderId" -Method DELETE -Headers $headers 2>$null | Out-Null
Invoke-RestMethod -Uri "$API/auth/v1/admin/users/$syncId" -Method DELETE -Headers $headers 2>$null | Out-Null
Write-Host "Done!"
