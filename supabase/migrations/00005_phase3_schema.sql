-- =============================================================
-- Migration 00005: Phase 3 Schema — Matters & Documents Upgrade
-- =============================================================

-- =============================================================
-- MATTERS: Add matter_code + enforce financial_year
-- =============================================================

ALTER TABLE matters
  ADD COLUMN matter_code text UNIQUE;

-- financial_year already exists but is nullable — enforce it going forward
-- (existing NULL rows would need backfilling in production; dev DB is empty)
ALTER TABLE matters
  ALTER COLUMN financial_year SET NOT NULL,
  ALTER COLUMN financial_year SET DEFAULT '';

-- Auto-generate matter codes via a trigger function
CREATE OR REPLACE FUNCTION generate_matter_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  client_name_val text;
  consonants      text;
  abbr            text;
  fy_raw          text;
  fy_short        text;
  seq             int;
BEGIN
  -- Get client name
  SELECT name INTO client_name_val FROM clients WHERE id = NEW.client_id;

  -- Build 3-char abbreviation: strip vowels + non-alpha, take first 3, uppercase
  consonants := upper(regexp_replace(client_name_val, '[AaEeIiOoUu\s\W0-9]', '', 'g'));
  abbr := left(consonants, 3);
  -- Fallback: if fewer than 3 consonants, use first 3 alphanumeric chars
  IF length(abbr) < 3 THEN
    abbr := upper(left(regexp_replace(client_name_val, '[^A-Za-z0-9]', '', 'g'), 3));
  END IF;
  -- Pad with X if still short
  abbr := rpad(abbr, 3, 'X');

  -- Compress financial year: "2023-24" → digits only → "202324" → "2324"
  fy_raw := regexp_replace(NEW.financial_year, '[^0-9]', '', 'g');
  IF length(fy_raw) >= 6 THEN
    fy_short := substring(fy_raw FROM 3 FOR 2) || substring(fy_raw FROM 5 FOR 2);
  ELSE
    fy_short := fy_raw;
  END IF;

  -- Sequence: count existing matters for same org with same abbr+fy prefix
  SELECT COUNT(*) + 1 INTO seq
  FROM matters
  WHERE org_id = NEW.org_id
    AND matter_code LIKE abbr || '-' || fy_short || '-%';

  NEW.matter_code := abbr || '-' || fy_short || '-' || lpad(seq::text, 2, '0');
  RETURN NEW;
END;
$$;

CREATE TRIGGER matters_generate_code
  BEFORE INSERT ON matters
  FOR EACH ROW
  WHEN (NEW.matter_code IS NULL)
  EXECUTE FUNCTION generate_matter_code();

-- =============================================================
-- DOCUMENTS: Add Phase 4 processing columns
-- =============================================================

-- Document classification (AI decides — proceeding or supporting)
ALTER TABLE documents
  ADD COLUMN document_class      text CHECK (document_class IN ('proceeding', 'supporting')),
  ADD COLUMN document_category   text,
  ADD COLUMN confidence_scores   jsonb DEFAULT '{}',
  ADD COLUMN review_reason       text,
  ADD COLUMN source              text CHECK (source IN ('direct', 'inbox')) DEFAULT 'direct';
-- extraction_profile_id added in migration 00006 when extraction_profiles table exists

-- Note: needs_review is handled by existing doc_status enum value 'needs_review'
-- Note: raw_metadata jsonb already exists — we'll use it for extracted_data

-- =============================================================
-- DOCUMENT LINKS: Add missing link types
-- =============================================================

-- PostgreSQL allows adding but not removing enum values
ALTER TYPE link_type ADD VALUE IF NOT EXISTS 'supersedes';
ALTER TYPE link_type ADD VALUE IF NOT EXISTS 'appeals_to';
ALTER TYPE link_type ADD VALUE IF NOT EXISTS 'exhibit';
ALTER TYPE link_type ADD VALUE IF NOT EXISTS 'attachment_to';
ALTER TYPE link_type ADD VALUE IF NOT EXISTS 'references_doc';
-- Note: original values (arises_from, challenges, summarizes) are kept intact
-- to not break existing data; new code will use the new values above.

-- =============================================================
-- SUPPORTING DOCUMENTS: Deprecate for new uploads
-- =============================================================

-- Keep the supporting_documents table intact (no data loss, RLS still works).
-- All NEW uploads will go through documents.document_class = 'supporting'.
-- This comment marks the table as soft-deprecated for new application code.
COMMENT ON TABLE supporting_documents IS
  'DEPRECATED for new uploads as of migration 00005. '
  'All new documents (proceeding + supporting) use the documents table '
  'with document_class column. This table is retained for historical data.';

-- =============================================================
-- STAGED DOCUMENTS: Add AI suggestion columns
-- =============================================================

ALTER TABLE staged_documents
  ADD COLUMN suggested_client_id  uuid REFERENCES clients(id),
  ADD COLUMN suggested_matter_id  uuid REFERENCES matters(id),
  ADD COLUMN suggestion_reason    text,    -- e.g. "GSTIN match: 27AABCH..."
  ADD COLUMN confidence_scores    jsonb DEFAULT '{}',
  ADD COLUMN extracted_gstin      text,
  ADD COLUMN extracted_fy         text,
  ADD COLUMN document_text        text;    -- extracted text for embedding after assignment

-- =============================================================
-- INDEXES
-- =============================================================

CREATE INDEX idx_documents_document_class ON documents(document_class);
CREATE INDEX idx_documents_matter_class   ON documents(matter_id, document_class);
CREATE INDEX idx_documents_needs_review   ON documents(org_id, status) WHERE status = 'needs_review';
CREATE INDEX idx_matters_matter_code      ON matters(matter_code);
CREATE INDEX idx_matters_org_fy           ON matters(org_id, financial_year);
