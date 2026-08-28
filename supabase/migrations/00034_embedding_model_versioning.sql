-- Version document embeddings so vectors from different models are never
-- compared as though they occupy the same vector space.

ALTER TABLE documents
  ADD COLUMN embedding_model text,
  ADD COLUMN embedding_version text;

UPDATE documents
SET
  embedding_model = 'text-embedding-004',
  embedding_version = 'legacy-text-embedding-004-768-v1'
WHERE embedding IS NOT NULL;

CREATE INDEX idx_documents_embedding_version
  ON documents (org_id, embedding_model, embedding_version)
  WHERE embedding IS NOT NULL AND deleted_at IS NULL;

CREATE OR REPLACE FUNCTION match_documents_v2 (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_matter_id uuid,
  p_embedding_model text,
  p_embedding_version text
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
    AND (auth.role() = 'service_role' OR is_org_member(documents.org_id))
    AND documents.embedding_model = p_embedding_model
    AND documents.embedding_version = p_embedding_version
    AND documents.embedding IS NOT NULL
    AND 1 - (documents.embedding <=> query_embedding) > match_threshold
    AND documents.deleted_at IS NULL
  ORDER BY documents.embedding <=> query_embedding
  LIMIT LEAST(match_count, 30);
$$;

CREATE OR REPLACE FUNCTION match_all_documents_v2 (
  query_embedding vector(768),
  match_threshold float,
  match_count int,
  p_org_id uuid,
  p_embedding_model text,
  p_embedding_version text
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
    AND (auth.role() = 'service_role' OR is_org_member(documents.org_id))
    AND documents.embedding_model = p_embedding_model
    AND documents.embedding_version = p_embedding_version
    AND documents.embedding IS NOT NULL
    AND 1 - (documents.embedding <=> query_embedding) > match_threshold
    AND documents.deleted_at IS NULL
  ORDER BY documents.embedding <=> query_embedding
  LIMIT LEAST(match_count, 30);
$$;

-- The usage table stores prices per one million input/output tokens. Gemini
-- Embedding is currently billed by input tokens; outputs are not charged.
INSERT INTO model_pricing (
  model_name,
  input_price_per_1m,
  output_price_per_1m
) VALUES (
  'gemini-embedding-001',
  0.15,
  0.0
)
ON CONFLICT (model_name) DO UPDATE SET
  input_price_per_1m = EXCLUDED.input_price_per_1m,
  output_price_per_1m = EXCLUDED.output_price_per_1m,
  updated_at = now();

-- Correct the stale Gemini 1.5-era seed values attached to the 2.5 model name.
UPDATE model_pricing
SET
  input_price_per_1m = 0.15,
  output_price_per_1m = 0.60,
  updated_at = now()
WHERE model_name = 'gemini-2.5-flash';
