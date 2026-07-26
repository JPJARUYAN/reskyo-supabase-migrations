-- ============================================
-- PHASE 3, Step 4: sync_incident_status()
-- Auto-updates parent incident.status when
-- a dispatch status changes.
-- ============================================

CREATE OR REPLACE FUNCTION sync_incident_status()
RETURNS TRIGGER AS $$
BEGIN
  -- When dispatch is accepted, update incident to 'dispatched'
  IF NEW.status = 'accepted' AND OLD.status = 'pending' THEN
    UPDATE incidents
    SET status = 'dispatched',
        updated_at = now()
    WHERE id = NEW.incident_id;

  -- When responder is en route, update incident to 'inProgress'
  ELSIF NEW.status = 'enRoute' AND OLD.status = 'accepted' THEN
    UPDATE incidents
    SET status = 'inProgress',
        updated_at = now()
    WHERE id = NEW.incident_id;

  -- When responder arrives on scene, keep 'inProgress'
  ELSIF NEW.status = 'onScene' AND OLD.status = 'enRoute' THEN
    UPDATE incidents
    SET status = 'inProgress',
        updated_at = now()
    WHERE id = NEW.incident_id;

  -- When dispatch is resolved, check if ALL dispatches for this incident are resolved
  ELSIF NEW.status = 'resolved' THEN
    -- If no more active dispatches, mark incident as resolved
    IF NOT EXISTS (
      SELECT 1 FROM dispatches
      WHERE incident_id = NEW.incident_id
        AND status NOT IN ('resolved')
        AND id != NEW.id
    ) THEN
      UPDATE incidents
      SET status = 'resolved',
          updated_at = now()
      WHERE id = NEW.incident_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS trg_sync_incident_status ON dispatches;
CREATE TRIGGER trg_sync_incident_status
  AFTER UPDATE OF status ON dispatches
  FOR EACH ROW
  EXECUTE FUNCTION sync_incident_status();
