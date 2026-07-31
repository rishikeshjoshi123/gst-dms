-- =============================================================
-- Migration 00016: Enable Realtime for additional tables
-- =============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE wiki_sections;
ALTER PUBLICATION supabase_realtime ADD TABLE document_links;
ALTER PUBLICATION supabase_realtime ADD TABLE case_notes;
