-- ============================================
-- PHASE 6: FCM Push Notification Trigger
-- Sends push notification to responder when
-- a new dispatch is created.
-- ============================================

-- Enable http extension (if not already)
CREATE EXTENSION IF NOT EXISTS http;

-- Function to send push notification when dispatch is created
CREATE OR REPLACE FUNCTION trigger_send_push_notification()
RETURNS TRIGGER AS $$
DECLARE
  responder_fcm TEXT;
  anon_key TEXT;
  supabase_url TEXT;
BEGIN
  -- Get the responder's FCM token
  SELECT fcm_token INTO responder_fcm
  FROM users
  WHERE uid = NEW.responder_id;

  -- Get Supabase config
  supabase_url := current_setting('app.settings.supabase_url', true);
  anon_key := current_setting('app.settings.anon_key', true);

  -- If token exists, send push via Edge Function
  IF responder_fcm IS NOT NULL AND responder_fcm != '' THEN
    IF supabase_url IS NOT NULL AND anon_key IS NOT NULL THEN
      PERFORM net.http_post(
        url := supabase_url || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || anon_key
        ),
        body := jsonb_build_object(
          'fcm_token', responder_fcm,
          'title', 'RESKYO - New Dispatch',
          'body', 'You have a new emergency dispatch assignment',
          'dispatch_id', NEW.id::text
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trg_send_push ON dispatches;
CREATE TRIGGER trg_send_push
  AFTER INSERT ON dispatches
  FOR EACH ROW
  EXECUTE FUNCTION trigger_send_push_notification();
