-- Add semantic match RPC for finding similar documents across all matters in an org
CREATE OR REPLACE FUNCTION match_all_documents (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_org_id uuid
)
RETURNS TABLE (
  id uuid,
  reference_number text,
  similarity float
)
LANGUAGE sql STABLE
AS $$
  SELECT
    documents.id,
    documents.reference_number,
    1 - (documents.embedding <=> query_embedding) AS similarity
  FROM documents
  WHERE documents.org_id = p_org_id
    AND documents.embedding IS NOT NULL
    AND 1 - (documents.embedding <=> query_embedding) > match_threshold
    AND documents.deleted_at IS NULL
  ORDER BY documents.embedding <=> query_embedding
  LIMIT match_count;
$$;
