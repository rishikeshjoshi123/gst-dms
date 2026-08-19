-- The assignment algorithm derives a suggested matter from AI-extracted
-- metadata plus existing documents, links, clients, and matters. That
-- suggestion must not double as the user's explicit upload destination.
-- Keeping them separate lets the UI present matter intake without mixing in
-- global triage.
ALTER TABLE staged_documents
  ADD COLUMN IF NOT EXISTS intake_matter_id uuid REFERENCES matters(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_staged_documents_intake_matter
  ON staged_documents(org_id, intake_matter_id, created_at DESC)
  WHERE status IN ('pending_assignment', 'analyzing', 'ready_to_assign', 'failed');
