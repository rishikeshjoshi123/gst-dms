-- =============================================================
-- Migration 00020: Matter Uniqueness + Org-Wide Fuzzy Match RPC
-- =============================================================

-- 1. Prevent race-condition duplicate matter creation.
--    Ensures at most one active matter per (org, client, financial_year).
--    ON CONFLICT will raise an error which callers should handle gracefully
--    (re-fetch the existing matter and use it instead).
CREATE UNIQUE INDEX IF NOT EXISTS idx_matters_unique_client_fy
  ON matters(org_id, client_id, financial_year)
  WHERE deleted_at IS NULL;

-- 2. Org-wide fuzzy reference number match (used by Phase A1 of the assignment engine).
--    Unlike the existing fuzzy_match_reference() which is scoped to a single matter,
--    this RPC searches across the entire org so we can find the correct matter
--    without knowing it upfront.
CREATE OR REPLACE FUNCTION org_wide_fuzzy_match_reference(
  p_org_id         uuid,
  p_reference_number text
)
RETURNS TABLE (
  id               uuid,
  matter_id        uuid,
  reference_number text,
  sim_score        real
)
LANGUAGE sql STABLE
AS $$
  SELECT
    d.id,
    d.matter_id,
    d.reference_number,
    similarity(d.reference_number, p_reference_number) AS sim_score
  FROM documents d
  WHERE d.org_id = p_org_id
    AND d.reference_number IS NOT NULL
    AND d.deleted_at IS NULL
    AND similarity(d.reference_number, p_reference_number) > 0.5
  ORDER BY sim_score DESC
  LIMIT 10;
$$;

-- 3. One-time backfill: normalize legacy FY strings that do not match YYYY-YY format.
--    Only updates rows matching the known bad patterns to avoid touching clean data.

-- Pattern: "FY22-23" → "2022-23"
UPDATE matters
  SET financial_year = '20' || substring(financial_year FROM 3 FOR 2)
                      || '-' || substring(financial_year FROM 6 FOR 2)
  WHERE financial_year ~ '^FY\d{2}-\d{2}$';

-- Pattern: "FY 2022-23" → "2022-23"  
UPDATE matters
  SET financial_year = substring(financial_year FROM 4)
  WHERE financial_year ~ '^FY\s\d{4}-\d{2}$';

-- Pattern: "2022-2023" → "2022-23"
UPDATE matters
  SET financial_year = substring(financial_year FROM 1 FOR 4)
                      || '-' || substring(financial_year FROM 8 FOR 2)
  WHERE financial_year ~ '^\d{4}-\d{4}$';
