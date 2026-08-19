-- =============================================================
-- Migration 00024: Set Replica Identity FULL for more tables
-- =============================================================
-- Similar to migration 00023, staged_documents and notifications
-- need REPLICA IDENTITY FULL so their RLS policies (which check org_id)
-- can be evaluated correctly on UPDATE events where org_id isn't modified.

ALTER TABLE staged_documents REPLICA IDENTITY FULL;
ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER TABLE deadlines REPLICA IDENTITY FULL;
