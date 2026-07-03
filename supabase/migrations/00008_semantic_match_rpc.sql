-- Add semantic match RPC for finding similar documents
CREATE OR REPLACE FUNCTION match_documents (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_matter_id uuid
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
  WHERE documents.matter_id = p_matter_id
    AND documents.embedding IS NOT NULL
    AND 1 - (documents.embedding <=> query_embedding) > match_threshold
    AND documents.deleted_at IS NULL
  ORDER BY documents.embedding <=> query_embedding
  LIMIT match_count;
$$;
