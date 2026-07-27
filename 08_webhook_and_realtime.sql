-- ============================================
-- PHASE 3, Step 2: Database Webhook for SMS
-- Triggers send-sms Edge Function when a new
-- dispatch row is inserted.
-- ============================================

-- Enable the http extension for webhooks
CREATE EXTENSION IF NOT EXISTS http;

-- Create the webhook trigger
-- This fires AFTER a new dispatch is inserted
-- and calls the send-sms Edge Function via pg_net
CREATE OR REPLACE FUNCTION trigger_send_sms_webhook()
RETURNS TRIGGER AS $$
DECLARE
  anon_key TEXT;
  supabase_url TEXT;
BEGIN
  -- Get Supabase config from app.settings
  supabase_url := current_setting('app.settings.supabase_url', true);
  anon_key := current_setting('app.settings.anon_key', true);

  -- Only proceed if config is available
  IF supabase_url IS NOT NULL AND anon_key IS NOT NULL THEN
    -- Call send-sms Edge Function with the dispatch record
    -- (same payload shape a Supabase Database Webhook would send)
    PERFORM net.http_post(
      url := supabase_url || '/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || anon_key
      ),
      body := jsonb_build_object(
        'type', 'INSERT',
        'record', jsonb_build_object(
          'id', NEW.id,
          'incident_id', NEW.incident_id,
          'responder_id', NEW.responder_id,
          'status', NEW.status,
          'dispatched_at', NEW.dispatched_at::text
        )
      )
    );
  END IF;

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
