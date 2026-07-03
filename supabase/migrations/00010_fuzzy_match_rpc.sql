-- 00010_fuzzy_match_rpc.sql

CREATE OR REPLACE FUNCTION fuzzy_match_reference (
  p_matter_id uuid,
  p_reference_number text
)
RETURNS TABLE (
  id uuid,
  doc_type text,
  reference_number text,
  sim_score real
)
LANGUAGE sql STABLE
AS $$
  SELECT 
    id, 
    doc_type, 
    reference_number, 
    similarity(reference_number, p_reference_number) AS sim_score
  FROM documents
  WHERE matter_id = p_matter_id
    AND reference_number IS NOT NULL
    AND deleted_at IS NULL
    AND similarity(reference_number, p_reference_number) > 0.6
  ORDER BY sim_score DESC
  LIMIT 1;
$$;
