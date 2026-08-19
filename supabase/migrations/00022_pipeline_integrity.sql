-- Prevent duplicate active clients with same GSTIN in an org
CREATE UNIQUE INDEX IF NOT EXISTS idx_clients_unique_org_gstin
  ON clients(org_id, gstin)
  WHERE deleted_at IS NULL AND gstin IS NOT NULL;

-- Update fuzzy match RPC to join matters and clients and ensure they are alive
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
  SELECT d.id, d.matter_id, d.reference_number,
         similarity(d.reference_number, p_reference_number) AS sim_score
  FROM documents d
  JOIN matters m ON d.matter_id = m.id
  JOIN clients c ON m.client_id = c.id
  WHERE d.org_id = p_org_id
    AND d.reference_number IS NOT NULL
    AND d.deleted_at IS NULL
    AND m.deleted_at IS NULL
    AND c.deleted_at IS NULL
    AND similarity(d.reference_number, p_reference_number) > 0.5
  ORDER BY sim_score DESC
  LIMIT 10;
$$;
