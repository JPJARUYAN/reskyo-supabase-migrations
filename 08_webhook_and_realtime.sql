-- ============================================
-- PHASE 3, Step 2: Database Webhook for SMS
-- Triggers send-sms Edge Function when a new
-- dispatch row is inserted.
-- ============================================

-- Enable the http extension for webhooks
CREATE EXTENSION IF NOT EXISTS http;

-- Create the webhook trigger
-- This fires AFTER a new dispatch is inserted
-- and calls the send-sms Edge Function
CREATE OR REPLACE FUNCTION trigger_send_sms_webhook()
RETURNS TRIGGER AS $$
BEGIN
  -- The webhook is configured via Supabase Dashboard:
  -- Database → Webhooks → Create webhook
  -- OR via this SQL approach using pg_net/http
  --
  -- For now, we log that a dispatch was created
  -- The actual webhook is set up in Supabase Dashboard
  RAISE NOTICE 'New dispatch created: % for incident %',
    NEW.id, NEW.incident_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_send_sms_webhook ON dispatches;
CREATE TRIGGER trg_send_sms_webhook
  AFTER INSERT ON dispatches
  FOR EACH ROW
  EXECUTE FUNCTION trigger_send_sms_webhook();

-- ============================================
-- PHASE 3, Step 5: Enable Realtime
-- ============================================

-- Enable Realtime on incidents table
ALTER PUBLICATION supabase_realtime ADD TABLE incidents;

-- Enable Realtime on dispatches table
ALTER PUBLICATION supabase_realtime ADD TABLE dispatches;
