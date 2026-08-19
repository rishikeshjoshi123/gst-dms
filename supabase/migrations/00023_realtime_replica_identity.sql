-- =============================================================
-- Migration 00023: Set Replica Identity FULL for Realtime Filters
-- =============================================================
-- Supabase Realtime requires REPLICA IDENTITY FULL on tables if you are 
-- filtering UPDATE events on a column that is not being updated in the query.
-- Otherwise, the column is not included in the WAL event, and the filter fails.

ALTER TABLE documents REPLICA IDENTITY FULL;
ALTER TABLE case_notes REPLICA IDENTITY FULL;
ALTER TABLE wiki_sections REPLICA IDENTITY FULL;
