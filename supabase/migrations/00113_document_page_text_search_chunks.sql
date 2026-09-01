-- Private, version-bound page text and changed chunk authority.  This is not a
-- Search reader: only trusted processing/index workers can write or read it.
BEGIN;

CREATE FUNCTION public.document_page_text_ocr_words_are_safe(p_words jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $$
  SELECT p_words IS NULL OR p_words = 'null'::jsonb OR (
    jsonb_typeof(p_words) = 'array' AND jsonb_array_length(p_words) <= 2000
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_words) word(value)
      WHERE jsonb_typeof(word.value) <> 'object'
        OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(word.value) key)
           IS DISTINCT FROM ARRAY['height','text','width','x','y']::text[]
        OR jsonb_typeof(word.value->'text') <> 'string' OR char_length(word.value->>'text') NOT BETWEEN 1 AND 256
        OR NOT pg_input_is_valid(word.value->>'x','numeric') OR NOT (word.value->>'x')::numeric BETWEEN 0 AND 1
        OR NOT pg_input_is_valid(word.value->>'y','numeric') OR NOT (word.value->>'y')::numeric BETWEEN 0 AND 1
        OR NOT pg_input_is_valid(word.value->>'width','numeric') OR NOT (word.value->>'width')::numeric BETWEEN 0 AND 1
        OR NOT pg_input_is_valid(word.value->>'height','numeric') OR NOT (word.value->>'height')::numeric BETWEEN 0 AND 1
    )
  )
$$;

CREATE TABLE public.document_page_text_artifacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  processing_run_id uuid NOT NULL REFERENCES public.document_processing_runs(id) ON DELETE CASCADE,
  source_analysis_run_id uuid NOT NULL REFERENCES public.source_analysis_runs(id) ON DELETE RESTRICT,
  state text NOT NULL CHECK (state IN ('ready', 'not_indexable')),
  page_count integer NOT NULL CHECK (page_count > 0 AND page_count <= 200),
  content_fingerprint text CHECK (content_fingerprint ~ '^[a-f0-9]{64}$'),
  safe_error_code text CHECK (safe_error_code IS NULL OR safe_error_code ~ '^[a-z][a-z0-9_]{0,99}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_page_text_artifacts_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_page_text_artifacts_document_org_fkey FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE CASCADE,
  CONSTRAINT document_page_text_artifacts_version_org_fkey FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE CASCADE,
  CONSTRAINT document_page_text_artifacts_current_version_unique UNIQUE (org_id, document_id, document_version_id),
  CONSTRAINT document_page_text_artifacts_terminal_shape CHECK (
    (state = 'ready' AND content_fingerprint IS NOT NULL AND safe_error_code IS NULL)
    OR (state = 'not_indexable' AND content_fingerprint IS NULL AND safe_error_code IS NOT NULL)
  )
);

CREATE TABLE public.document_page_text_pages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  artifact_id uuid NOT NULL,
  page_number integer NOT NULL CHECK (page_number BETWEEN 1 AND 200),
  page_text text NOT NULL CHECK (char_length(page_text) BETWEEN 1 AND 8000 AND page_text !~ E'[\\x00-\\x1F\\x7F]'),
  ocr_words jsonb CHECK (public.document_page_text_ocr_words_are_safe(ocr_words)),
  page_content_hash text NOT NULL CHECK (page_content_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_page_text_pages_artifact_org_fkey FOREIGN KEY (org_id, artifact_id)
    REFERENCES public.document_page_text_artifacts(org_id, id) ON DELETE CASCADE,
  CONSTRAINT document_page_text_pages_artifact_page_unique UNIQUE (artifact_id, page_number)
);

CREATE TABLE public.search_document_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  artifact_id uuid NOT NULL,
  ordinal integer NOT NULL CHECK (ordinal > 0 AND ordinal <= 20000),
  page_start integer NOT NULL CHECK (page_start BETWEEN 1 AND 200),
  page_end integer NOT NULL CHECK (page_end >= page_start AND page_end <= 200),
  char_start integer NOT NULL CHECK (char_start >= 0),
  char_end integer NOT NULL CHECK (char_end > char_start AND char_end - char_start <= 4000),
  content text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 4000 AND content !~ E'[\\x00-\\x1F\\x7F]'),
  content_hash text NOT NULL CHECK (content_hash ~ '^[a-f0-9]{64}$'),
  search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple', content)) STORED,
  embedding vector(768),
  embedding_model text CHECK (embedding_model IS NULL OR embedding_model ~ '^[A-Za-z0-9._:-]{1,200}$'),
  embedding_version text CHECK (embedding_version IS NULL OR embedding_version ~ '^[A-Za-z0-9._:-]{1,200}$'),
  input_tokens integer CHECK (input_tokens IS NULL OR input_tokens >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT search_document_chunks_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT search_document_chunks_document_org_fkey FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_chunks_version_org_fkey FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_chunks_artifact_org_fkey FOREIGN KEY (org_id, artifact_id)
    REFERENCES public.document_page_text_artifacts(org_id, id) ON DELETE CASCADE,
  -- Ordinal is presentation order and may shift as source text changes. The
  -- reusable identity is the exact immutable source locator plus content.
  CONSTRAINT search_document_chunks_source_locator_unique
    UNIQUE (org_id, artifact_id, page_start, char_start, char_end, content_hash),
  CONSTRAINT search_document_chunks_embedding_shape CHECK (
    (embedding IS NULL AND embedding_model IS NULL AND embedding_version IS NULL AND input_tokens IS NULL)
    OR (embedding IS NOT NULL AND embedding_model IS NOT NULL AND embedding_version IS NOT NULL AND input_tokens IS NOT NULL)
  )
);
CREATE INDEX search_document_chunks_current_idx ON public.search_document_chunks(org_id, document_id, document_version_id);

CREATE TABLE public.search_document_chunk_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  artifact_id uuid,
  processing_run_id uuid NOT NULL REFERENCES public.document_processing_runs(id) ON DELETE CASCADE,
  state text NOT NULL CHECK (state IN ('indexed', 'not_indexable', 'failed')),
  changed_chunk_count integer NOT NULL DEFAULT 0 CHECK (changed_chunk_count >= 0),
  safe_error_code text CHECK (safe_error_code IS NULL OR safe_error_code ~ '^[a-z][a-z0-9_]{0,99}$'),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT search_document_chunk_runs_document_org_fkey FOREIGN KEY (org_id, document_id)
    REFERENCES public.documents(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_chunk_runs_version_org_fkey FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_chunk_runs_artifact_org_fkey FOREIGN KEY (org_id, artifact_id)
    REFERENCES public.document_page_text_artifacts(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_chunk_runs_processing_unique UNIQUE (processing_run_id)
);

CREATE OR REPLACE FUNCTION public.invalidate_document_page_text_search_storage()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF NEW.record_state <> 'active'::public.document_record_state OR NEW.deleted_at IS NOT NULL
     OR NEW.current_version_id IS DISTINCT FROM OLD.current_version_id THEN
    DELETE FROM public.document_page_text_artifacts WHERE org_id = OLD.org_id AND document_id = OLD.id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER documents_invalidate_page_text_search_storage
  AFTER UPDATE OF record_state, deleted_at, current_version_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.invalidate_document_page_text_search_storage();

CREATE FUNCTION public.write_current_document_page_text_artifact(
  p_processing_run_id uuid, p_processing_lease_token uuid,
  p_source_analysis_run_id uuid, p_source_analysis_lease_token uuid,
  p_document_version_id uuid, p_pages jsonb
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE; document_row public.documents%ROWTYPE;
DECLARE version_row public.document_versions%ROWTYPE; source_row public.source_analysis_runs%ROWTYPE;
DECLARE v_artifact_id uuid; expected_pages integer; pages_valid boolean := false; artifact_hash text;
BEGIN
  IF p_processing_run_id IS NULL OR p_processing_lease_token IS NULL
     OR p_source_analysis_run_id IS NULL OR p_source_analysis_lease_token IS NULL OR p_document_version_id IS NULL
     OR jsonb_typeof(p_pages) <> 'array' THEN RETURN QUERY SELECT 'invalid_request'::text; RETURN; END IF;
  SELECT * INTO run_row FROM public.document_processing_runs WHERE id=p_processing_run_id FOR UPDATE;
  SELECT * INTO document_row FROM public.documents WHERE id=run_row.document_id AND org_id=run_row.org_id FOR UPDATE;
  SELECT * INTO version_row FROM public.document_versions WHERE id=p_document_version_id AND org_id=run_row.org_id FOR KEY SHARE;
  SELECT * INTO source_row FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id AND org_id=run_row.org_id FOR KEY SHARE;
  IF run_row.id IS NULL OR document_row.id IS NULL OR version_row.id IS NULL OR source_row.id IS NULL
     OR run_row.scope NOT IN ('extract'::public.document_processing_scope,'full'::public.document_processing_scope)
     OR run_row.state <> 'running'::public.document_processing_state
     OR run_row.lease_token IS DISTINCT FROM p_processing_lease_token OR run_row.lease_expires_at <= now()
     OR run_row.document_version_id IS DISTINCT FROM version_row.id
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR document_row.record_state <> 'active'::public.document_record_state OR document_row.deleted_at IS NOT NULL
     OR version_row.document_id IS DISTINCT FROM document_row.id OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state
     OR source_row.analysis_kind <> 'ai_extraction'::public.source_analysis_kind
     OR source_row.analysis_state <> 'running'::public.source_analysis_provenance_state
     OR source_row.lease_token IS DISTINCT FROM p_source_analysis_lease_token OR source_row.lease_expires_at <= now()
     OR source_row.idempotency_key IS DISTINCT FROM 'ai_extraction.' || run_row.id::text THEN
    RETURN QUERY SELECT 'processing_lease_invalid'::text; RETURN;
  END IF;
  expected_pages := version_row.page_count;
  SELECT count(*) = expected_pages AND count(DISTINCT value->>'page_number') = expected_pages
    AND bool_and(jsonb_typeof(value)='object' AND value ? 'page_number' AND value ? 'text'
      AND value->>'page_number' IN (SELECT page_number::text FROM generate_series(1, expected_pages) page_number)
      AND jsonb_typeof(value->'text')='string' AND char_length(value->>'text') BETWEEN 1 AND 8000
      AND value->>'text' !~ E'[\\x00-\\x1F\\x7F]'
      AND (NOT value ? 'ocr_words' OR public.document_page_text_ocr_words_are_safe(value->'ocr_words')))
  INTO pages_valid FROM jsonb_array_elements(p_pages) AS input(value);
  IF pages_valid IS DISTINCT FROM true THEN
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,safe_error_code)
    VALUES(run_row.org_id,run_row.document_id,version_row.id,run_row.id,source_row.id,'not_indexable',expected_pages,'page_text_unavailable')
    ON CONFLICT (org_id,document_id,document_version_id) DO UPDATE SET processing_run_id=EXCLUDED.processing_run_id,
      source_analysis_run_id=EXCLUDED.source_analysis_run_id,state='not_indexable',content_fingerprint=NULL,
      safe_error_code='page_text_unavailable',updated_at=now() RETURNING id INTO v_artifact_id;
    DELETE FROM public.document_page_text_pages AS page WHERE page.artifact_id = v_artifact_id;
    DELETE FROM public.search_document_chunks AS chunk WHERE chunk.org_id = run_row.org_id
      AND chunk.document_id = run_row.document_id AND chunk.document_version_id = version_row.id;
    INSERT INTO public.search_document_chunk_runs(
      org_id,document_id,document_version_id,artifact_id,processing_run_id,state,changed_chunk_count,safe_error_code
    ) VALUES (
      run_row.org_id,run_row.document_id,version_row.id,NULL,run_row.id,'not_indexable',0,'page_text_unavailable'
    ) ON CONFLICT (processing_run_id) DO UPDATE SET state='not_indexable',artifact_id=NULL,
      changed_chunk_count=0,safe_error_code='page_text_unavailable',updated_at=now();
    RETURN QUERY SELECT 'not_indexable'::text; RETURN;
  END IF;
  SELECT encode(extensions.digest(convert_to(string_agg(value->>'text','' ORDER BY (value->>'page_number')::integer),'utf8'),'sha256'),'hex')
    INTO artifact_hash FROM jsonb_array_elements(p_pages) AS input(value);
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
  VALUES(run_row.org_id,run_row.document_id,version_row.id,run_row.id,source_row.id,'ready',expected_pages,artifact_hash)
  ON CONFLICT (org_id,document_id,document_version_id) DO UPDATE SET processing_run_id=EXCLUDED.processing_run_id,
    source_analysis_run_id=EXCLUDED.source_analysis_run_id,state='ready',page_count=EXCLUDED.page_count,
    content_fingerprint=EXCLUDED.content_fingerprint,safe_error_code=NULL,updated_at=now() RETURNING id INTO v_artifact_id;
  DELETE FROM public.document_page_text_pages AS page WHERE page.artifact_id = v_artifact_id;
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,page_content_hash)
  SELECT run_row.org_id,v_artifact_id,(value->>'page_number')::integer,value->>'text',
    CASE WHEN value ? 'ocr_words' THEN value->'ocr_words' ELSE NULL END,
    encode(extensions.digest(convert_to(value->>'text','utf8'),'sha256'),'hex')
  FROM jsonb_array_elements(p_pages) AS input(value);
  RETURN QUERY SELECT 'written'::text;
END $$;

CREATE FUNCTION public.get_document_search_page_text_reprocess_input(p_processing_run_id uuid, p_lease_token uuid)
RETURNS TABLE(code text, pages jsonb, existing_content_hashes jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE; artifact_row public.document_page_text_artifacts%ROWTYPE;
BEGIN
  SELECT * INTO run_row FROM public.document_processing_runs WHERE id=p_processing_run_id FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.state <> 'running'::public.document_processing_state
    OR run_row.lease_token IS DISTINCT FROM p_lease_token OR run_row.lease_expires_at <= now() THEN
    RETURN QUERY SELECT 'stale_lease'::text,NULL::jsonb,NULL::jsonb; RETURN; END IF;
  SELECT a.* INTO artifact_row FROM public.document_page_text_artifacts a JOIN public.documents d
    ON d.id=a.document_id AND d.org_id=a.org_id
    JOIN public.source_analysis_runs source_run ON source_run.id=a.source_analysis_run_id AND source_run.org_id=a.org_id
    JOIN public.document_version_analysis_bindings binding ON binding.org_id=a.org_id
      AND binding.document_version_id=a.document_version_id AND binding.source_analysis_run_id=source_run.id
    WHERE a.org_id=run_row.org_id AND a.document_id=run_row.document_id
    AND a.document_version_id=run_row.document_version_id AND a.state='ready' AND d.current_version_id=a.document_version_id
    AND d.record_state='active'::public.document_record_state AND d.deleted_at IS NULL
    AND source_run.analysis_state='validated'::public.source_analysis_provenance_state FOR KEY SHARE;
  IF artifact_row.id IS NULL THEN RETURN QUERY SELECT 'not_indexable'::text,NULL::jsonb,NULL::jsonb; RETURN; END IF;
  RETURN QUERY SELECT 'ready'::text,
    (SELECT jsonb_agg(jsonb_build_object('page_number',page_number,'text',page_text) ORDER BY page_number)
      FROM public.document_page_text_pages WHERE artifact_id=artifact_row.id),
    (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'page_number',page_start,'char_start',char_start,'char_end',char_end,'content_hash',content_hash
    )),'[]'::jsonb) FROM public.search_document_chunks
      WHERE org_id=run_row.org_id AND document_id=run_row.document_id AND document_version_id=run_row.document_version_id);
END $$;

CREATE FUNCTION public.write_current_document_search_page_chunks(p_processing_run_id uuid, p_lease_token uuid, p_chunks jsonb)
RETURNS TABLE(code text, changed_chunk_count integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE; document_row public.documents%ROWTYPE;
DECLARE artifact_row public.document_page_text_artifacts%ROWTYPE; changed_count integer := 0; valid_chunks boolean := false;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL OR jsonb_typeof(p_chunks) <> 'array' THEN
    RETURN QUERY SELECT 'invalid_request'::text,0; RETURN; END IF;
  SELECT * INTO run_row FROM public.document_processing_runs WHERE id=p_processing_run_id FOR UPDATE;
  SELECT * INTO document_row FROM public.documents WHERE id=run_row.document_id AND org_id=run_row.org_id FOR UPDATE;
  SELECT a.* INTO artifact_row FROM public.document_page_text_artifacts AS a
    JOIN public.source_analysis_runs AS source_run ON source_run.id=a.source_analysis_run_id AND source_run.org_id=a.org_id
    JOIN public.document_version_analysis_bindings AS binding ON binding.org_id=a.org_id
      AND binding.document_version_id=a.document_version_id AND binding.source_analysis_run_id=source_run.id
    WHERE a.org_id=run_row.org_id AND a.document_id=run_row.document_id
      AND a.document_version_id=run_row.document_version_id AND source_run.analysis_state='validated'::public.source_analysis_provenance_state
    FOR KEY SHARE;
  IF run_row.id IS NULL OR run_row.state<>'running'::public.document_processing_state OR run_row.lease_token IS DISTINCT FROM p_lease_token
    OR run_row.lease_expires_at<=now() OR document_row.id IS NULL OR document_row.current_version_id IS DISTINCT FROM run_row.document_version_id
    OR document_row.record_state<>'active'::public.document_record_state OR document_row.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text,0; RETURN; END IF;
  IF artifact_row.id IS NULL OR artifact_row.state <> 'ready' THEN
    DELETE FROM public.search_document_chunks WHERE org_id=run_row.org_id AND document_id=run_row.document_id;
    INSERT INTO public.search_document_chunk_runs(org_id,document_id,document_version_id,artifact_id,processing_run_id,state,safe_error_code)
      VALUES(run_row.org_id,run_row.document_id,run_row.document_version_id,NULL,run_row.id,'not_indexable','page_text_unavailable')
      ON CONFLICT (processing_run_id) DO UPDATE SET state='not_indexable',artifact_id=NULL,changed_chunk_count=0,safe_error_code='page_text_unavailable',updated_at=now();
    RETURN QUERY SELECT 'not_indexable'::text,0; RETURN; END IF;
  SELECT coalesce(bool_and(jsonb_typeof(value)='object' AND pg_input_is_valid(value->>'ordinal','integer')
    AND pg_input_is_valid(value->>'page_number','integer') AND pg_input_is_valid(value->>'char_start','integer')
    AND pg_input_is_valid(value->>'char_end','integer') AND (value->>'ordinal')::integer>0
    AND value->>'page_number' IN (SELECT page_number::text FROM generate_series(1, artifact_row.page_count) page_number)
    AND (value->>'char_start')::integer>=0 AND (value->>'char_end')::integer>(value->>'char_start')::integer
    AND char_length(value->>'content') BETWEEN 1 AND 4000 AND value->>'content' !~ E'[\\x00-\\x1F\\x7F]'
    AND value->>'content_hash'=encode(extensions.digest(convert_to(value->>'content','utf8'),'sha256'),'hex')
    AND EXISTS (
      SELECT 1 FROM public.document_page_text_pages AS page
      WHERE page.org_id=run_row.org_id AND page.artifact_id=artifact_row.id
        AND page.page_number=(value->>'page_number')::integer
        AND (value->>'char_end')::integer <= char_length(page.page_text)
        AND value->>'content' = substring(
          page.page_text FROM (value->>'char_start')::integer + 1
          FOR (value->>'char_end')::integer - (value->>'char_start')::integer
        )
    )
    AND (value->>'embedding' IS NULL OR (pg_input_is_valid(value->>'embedding','vector') AND vector_dims((value->>'embedding')::vector)=768
      AND value->>'embedding_model' = 'gemini-embedding-001' AND value->>'embedding_version' = 'gemini-embedding-001-768-v1'
      AND pg_input_is_valid(value->>'input_tokens','integer') AND (value->>'input_tokens')::integer>=0))), false)
    INTO valid_chunks FROM jsonb_array_elements(p_chunks) input(value);
  IF NOT valid_chunks
     OR (SELECT count(DISTINCT value->>'ordinal') FROM jsonb_array_elements(p_chunks) input(value)) <> jsonb_array_length(p_chunks)
     OR (SELECT count(DISTINCT ((value->>'page_number') || ':' || (value->>'char_start') || ':' || (value->>'char_end') || ':' || (value->>'content_hash')))
         FROM jsonb_array_elements(p_chunks) input(value)) <> jsonb_array_length(p_chunks) THEN
    RETURN QUERY SELECT 'invalid_request'::text,0; RETURN;
  END IF;
  SELECT count(*) INTO changed_count FROM jsonb_array_elements(p_chunks) input(value)
  WHERE NOT EXISTS (SELECT 1 FROM public.search_document_chunks c WHERE c.org_id=run_row.org_id AND c.document_id=run_row.document_id
    AND c.document_version_id=run_row.document_version_id AND c.page_start=(value->>'page_number')::integer
    AND c.char_start=(value->>'char_start')::integer AND c.char_end=(value->>'char_end')::integer
    AND c.content_hash=value->>'content_hash');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_chunks) input(value) WHERE NOT EXISTS
      (SELECT 1 FROM public.search_document_chunks c WHERE c.org_id=run_row.org_id AND c.document_id=run_row.document_id
       AND c.document_version_id=run_row.document_version_id AND c.page_start=(value->>'page_number')::integer
       AND c.char_start=(value->>'char_start')::integer AND c.char_end=(value->>'char_end')::integer
       AND c.content_hash=value->>'content_hash') AND value->>'embedding' IS NULL) THEN
    RETURN QUERY SELECT 'invalid_request'::text,0; RETURN; END IF;
  DELETE FROM public.search_document_chunks AS chunk WHERE chunk.org_id=run_row.org_id AND chunk.document_id=run_row.document_id
    AND chunk.document_version_id=run_row.document_version_id AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_chunks) input(value)
      WHERE chunk.page_start=(value->>'page_number')::integer AND chunk.char_start=(value->>'char_start')::integer
        AND chunk.char_end=(value->>'char_end')::integer AND chunk.content_hash=value->>'content_hash'
    );
  INSERT INTO public.search_document_chunks(org_id,document_id,document_version_id,artifact_id,ordinal,page_start,page_end,char_start,char_end,content,content_hash,embedding,embedding_model,embedding_version,input_tokens)
  SELECT run_row.org_id,run_row.document_id,run_row.document_version_id,artifact_row.id,(value->>'ordinal')::integer,(value->>'page_number')::integer,(value->>'page_number')::integer,
    (value->>'char_start')::integer,(value->>'char_end')::integer,value->>'content',value->>'content_hash',
    CASE WHEN value->>'embedding' IS NULL THEN NULL ELSE (value->>'embedding')::vector END,value->>'embedding_model',value->>'embedding_version',
    CASE WHEN value->>'input_tokens' IS NULL THEN NULL ELSE (value->>'input_tokens')::integer END FROM jsonb_array_elements(p_chunks) input(value)
  ON CONFLICT (org_id,artifact_id,page_start,char_start,char_end,content_hash) DO UPDATE SET ordinal=EXCLUDED.ordinal,
    page_end=EXCLUDED.page_end,content=EXCLUDED.content,embedding=coalesce(EXCLUDED.embedding,search_document_chunks.embedding),
    embedding_model=coalesce(EXCLUDED.embedding_model,search_document_chunks.embedding_model),embedding_version=coalesce(EXCLUDED.embedding_version,search_document_chunks.embedding_version),
    input_tokens=coalesce(EXCLUDED.input_tokens,search_document_chunks.input_tokens),updated_at=now();
  INSERT INTO public.search_document_chunk_runs(org_id,document_id,document_version_id,artifact_id,processing_run_id,state,changed_chunk_count)
    VALUES(run_row.org_id,run_row.document_id,run_row.document_version_id,artifact_row.id,run_row.id,'indexed',changed_count)
    ON CONFLICT (processing_run_id) DO UPDATE SET state='indexed',artifact_id=EXCLUDED.artifact_id,changed_chunk_count=EXCLUDED.changed_chunk_count,safe_error_code=NULL,updated_at=now();
  RETURN QUERY SELECT 'indexed'::text,changed_count;
END $$;

-- The historical matter job may initiate work, but it must not write a
-- metadata vector around the leased page-chunk authority.  This creates the
-- same identifier-only durable intent consumed by documentLifecycleEvent.
CREATE FUNCTION public.enqueue_current_document_search_reindex(
  p_org_id uuid, p_document_id uuid, p_request_key text
) RETURNS TABLE(code text, processing_run_id uuid, outbox_event_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE document_row public.documents%ROWTYPE; version_row public.document_versions%ROWTYPE;
DECLARE event_id uuid; run_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_document_id IS NULL OR p_request_key IS NULL
     OR p_request_key !~ '^[A-Za-z0-9._:-]{1,160}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid; RETURN; END IF;
  SELECT * INTO document_row FROM public.documents WHERE id=p_document_id AND org_id=p_org_id FOR UPDATE;
  SELECT * INTO version_row FROM public.document_versions WHERE id=document_row.current_version_id AND org_id=p_org_id FOR KEY SHARE;
  IF document_row.id IS NULL OR version_row.id IS NULL OR document_row.record_state<>'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL OR version_row.state<>'current'::public.document_version_state
     OR version_row.validation_state<>'valid'::public.document_version_validation_state THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::uuid; RETURN; END IF;
  INSERT INTO public.outbox_events(org_id,aggregate_type,aggregate_id,event_kind,payload,idempotency_key)
  VALUES(p_org_id,'document',document_row.id,'document.reprocess_requested.v1',
    jsonb_build_object('document_id',document_row.id::text,'version_id',version_row.id::text,'scope','search_index'),
    'matter_reindex.'||p_request_key||'.'||document_row.id::text||'.'||version_row.id::text)
  ON CONFLICT (org_id,idempotency_key) DO NOTHING;
  SELECT id INTO event_id FROM public.outbox_events WHERE org_id=p_org_id
    AND idempotency_key='matter_reindex.'||p_request_key||'.'||document_row.id::text||'.'||version_row.id::text FOR UPDATE;
  INSERT INTO public.document_processing_runs(org_id,document_id,document_version_id,scope,idempotency_key,outbox_event_id,state,stage)
  VALUES(p_org_id,document_row.id,version_row.id,'search_index'::public.document_processing_scope,
    'matter_reindex.'||p_request_key||'.'||document_row.id::text||'.'||version_row.id::text,event_id,'queued'::public.document_processing_state,'queued'::public.document_processing_stage)
  ON CONFLICT (org_id,idempotency_key) DO NOTHING;
  SELECT id INTO run_id FROM public.document_processing_runs WHERE org_id=p_org_id
    AND idempotency_key='matter_reindex.'||p_request_key||'.'||document_row.id::text||'.'||version_row.id::text;
  RETURN QUERY SELECT CASE WHEN run_id IS NULL THEN 'invalid_request' ELSE 'queued' END::text,run_id,event_id;
END $$;

ALTER TABLE public.document_page_text_artifacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_page_text_artifacts FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_page_text_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_page_text_pages FORCE ROW LEVEL SECURITY;
ALTER TABLE public.search_document_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_document_chunks FORCE ROW LEVEL SECURITY;
ALTER TABLE public.search_document_chunk_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_document_chunk_runs FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.document_page_text_artifacts, public.document_page_text_pages, public.search_document_chunks, public.search_document_chunk_runs FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.document_page_text_ocr_words_are_safe(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.write_current_document_page_text_artifact(uuid,uuid,uuid,uuid,uuid,jsonb), public.get_document_search_page_text_reprocess_input(uuid,uuid), public.write_current_document_search_page_chunks(uuid,uuid,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_current_document_search_reindex(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_current_document_page_text_artifact(uuid,uuid,uuid,uuid,uuid,jsonb), public.get_document_search_page_text_reprocess_input(uuid,uuid), public.write_current_document_search_page_chunks(uuid,uuid,jsonb), public.enqueue_current_document_search_reindex(uuid,uuid,text) TO service_role;
COMMIT;
