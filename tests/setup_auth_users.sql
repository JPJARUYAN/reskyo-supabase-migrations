-- Step 1: Create test auth users (run via Studio SQL Editor)
-- This bypasses the FK by creating real auth.users entries

-- Create first test user (reporter for match_responders test)
SELECT * FROM auth.users LIMIT 0;

-- We'll use the auth.admin API instead - run these via curl:
-- curl -X POST http://127.0.0.1:54321/auth/v1/admin/users \
--   -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMkI3MDk5Mn0.IIH4l0g46lg-4DqFaH2g0J1XhP6uHjR7R2dVH8pWJk" \
--   -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMkI3MDk5Mn0.IIH4l0g46lg-4DqFaH2g0J1XhP6uHjR7R2dVH8pWJk" \
--   -H "Content-Type: application/json" \
--   -d '{"email":"testreporter@test.com","password":"testpass123","email_confirm":true}'

-- After creating users, run the setup files with the real UIDs
