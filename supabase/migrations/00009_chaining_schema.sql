-- 00009_chaining_schema.sql
-- Updates for Phase 7 Chain Placement Algorithm

-- 1. Enable pg_trgm for fuzzy matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 2. Modify document_links table
ALTER TABLE document_links
  ALTER COLUMN to_doc_id DROP NOT NULL;

ALTER TABLE document_links
  ADD COLUMN match_method text; -- e.g., 'exact_reference', 'fuzzy_reference', 'progression_inference', 'pending'

-- 3. Add integrity constraint
ALTER TABLE document_links
  ADD CONSTRAINT pending_link_integrity CHECK (
    (to_doc_id IS NOT NULL) OR (pending_ref_number IS NOT NULL)
  );
