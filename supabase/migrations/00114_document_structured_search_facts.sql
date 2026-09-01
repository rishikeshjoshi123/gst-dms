-- Private, current, source-backed structured Search facts.  This is a
-- producer-only authority: Search readers and query parsing remain deferred.
BEGIN;

CREATE TABLE public.search_document_structured_facts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  fact_family text NOT NULL CHECK (fact_family IN (
    'document_type', 'party', 'gstin', 'financial_year', 'deadline', 'amount'
  )),
  field_path text NOT NULL,
  semantic_candidate_key text NOT NULL,
  normalized_text text,
  value_date date,
  amount_paise bigint,
  resolution public.document_effective_metadata_resolution NOT NULL,
  winning_document_field_candidate_id uuid NOT NULL,
  winning_document_field_decision_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT search_document_structured_facts_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT search_document_structured_facts_document_org_fkey
    FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_structured_facts_version_org_fkey
    FOREIGN KEY (org_id, document_version_id) REFERENCES public.document_versions(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_document_structured_facts_candidate_org_fkey
    FOREIGN KEY (org_id, winning_document_field_candidate_id)
    REFERENCES public.document_field_candidates(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT search_document_structured_facts_decision_org_fkey
    FOREIGN KEY (org_id, winning_document_field_decision_id)
    REFERENCES public.document_field_decisions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT search_document_structured_facts_identity_unique
    UNIQUE (org_id, document_version_id, fact_family, field_path, semantic_candidate_key),
  CONSTRAINT search_document_structured_facts_value_shape CHECK (
    (fact_family IN ('document_type', 'party', 'gstin', 'financial_year')
      AND normalized_text IS NOT NULL AND value_date IS NULL AND amount_paise IS NULL)
    OR (fact_family = 'deadline'
      AND normalized_text IS NULL AND value_date IS NOT NULL AND amount_paise IS NULL)
    OR (fact_family = 'amount'
      AND normalized_text IS NULL AND value_date IS NULL AND amount_paise IS NOT NULL AND amount_paise >= 0)
  )
);

CREATE INDEX search_document_structured_facts_current_lookup_idx
  ON public.search_document_structured_facts (org_id, fact_family, normalized_text, value_date, amount_paise, document_id);

-- The selected field paths are the only currently materialized, source-bound
-- scalar candidates that have an approved Search meaning.  In particular,
-- candidate legal provisions lack a canonical act and provision kind, and the
-- legacy extraction party list has no candidate authority, so neither is
-- projected here.
CREATE FUNCTION public.read_current_document_structured_search_facts(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  fact_family text,
  field_path text,
  semantic_candidate_key text,
  normalized_text text,
  value_date date,
  amount_paise bigint,
  resolution public.document_effective_metadata_resolution,
  winning_document_field_candidate_id uuid,
  winning_document_field_decision_id uuid
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  WITH source AS (
    SELECT
      effective.document_id,
      effective.document_version_id,
      effective.field_path,
      effective.semantic_candidate_key,
      effective.value_type,
      effective.normalized_value,
      effective.resolution,
      effective.winning_document_field_candidate_id,
      effective.winning_document_field_decision_id,
      effective.normalized_value #>> '{}' AS scalar_value
    FROM public.document_effective_metadata AS effective
    JOIN public.documents AS document
      ON document.org_id = effective.org_id
      AND document.id = effective.document_id
      AND document.current_version_id = effective.document_version_id
      AND document.record_state = 'active'::public.document_record_state
      AND document.deleted_at IS NULL
    JOIN public.document_versions AS version
      ON version.org_id = effective.org_id
      AND version.id = effective.document_version_id
      AND version.document_id = effective.document_id
      AND version.state = 'current'::public.document_version_state
      AND version.validation_state = 'valid'::public.document_version_validation_state
    WHERE effective.org_id = p_org_id
      AND effective.document_id = ANY(p_document_ids)
      -- A cleared or rejected winner remains authoritative, but contributes no
      -- value.  There is deliberately no legacy-column fallback in this path.
      AND effective.normalized_value IS NOT NULL
      AND jsonb_typeof(effective.normalized_value) = 'string'
  ), candidates AS (
    SELECT
      source.*,
      CASE
        WHEN field_path = 'document.type' AND value_type = 'code'
          AND scalar_value ~ '^[A-Za-z0-9][A-Za-z0-9 _-]{0,63}$'
          THEN 'document_type'
        WHEN field_path = 'document.client_name' AND value_type = 'text'
          AND char_length(scalar_value) BETWEEN 1 AND 1024
          THEN 'party'
        WHEN field_path = 'document.gstin' AND value_type = 'code'
          AND upper(scalar_value) ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$'
          THEN 'gstin'
        WHEN field_path = 'document.financial_year' AND value_type = 'code'
          AND scalar_value ~ '^(19|20)[0-9]{2}-[0-9]{2}$'
          THEN 'financial_year'
        WHEN field_path = 'deadline.due_date' AND value_type = 'date'
          AND scalar_value ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
          AND pg_input_is_valid(scalar_value, 'date')
          THEN 'deadline'
        WHEN field_path ~ '^financial\.(tax|interest|penalty|fee|pre_deposit|total_demand|amount_in_dispute|amount_relief)$'
          AND value_type = 'decimal'
          -- Decimal source candidates are rupees.  Paise must be exact; SQL
          -- numeric is used only after rejecting fractions smaller than paise
          -- and values outside bigint storage.
          AND scalar_value ~ '^(0|[1-9][0-9]{0,17})(\.[0-9]{1,2})?$'
          AND scalar_value::numeric <= 92233720368547758.07::numeric
          THEN 'amount'
        ELSE NULL
      END AS fact_family
    FROM source
  ), normalized AS (
    SELECT
      candidates.*,
      CASE
        WHEN fact_family = 'document_type' THEN upper(scalar_value)
        WHEN fact_family = 'party' THEN lower(regexp_replace(btrim(scalar_value), '\s+', ' ', 'g'))
        WHEN fact_family = 'gstin' THEN upper(scalar_value)
        WHEN fact_family = 'financial_year' THEN scalar_value
        ELSE NULL
      END AS normalized_text,
      CASE WHEN fact_family = 'deadline' THEN scalar_value::date ELSE NULL END AS value_date,
      CASE WHEN fact_family = 'amount' THEN (scalar_value::numeric * 100)::bigint ELSE NULL END AS amount_paise
    FROM candidates
    WHERE fact_family IS NOT NULL
  ), deduplicated AS (
    SELECT DISTINCT ON (
      document_id, document_version_id, fact_family, field_path,
      coalesce(normalized_text, value_date::text, amount_paise::text)
    ) *
    FROM normalized
    ORDER BY
      document_id, document_version_id, fact_family, field_path,
      coalesce(normalized_text, value_date::text, amount_paise::text), semantic_candidate_key
  )
  SELECT document_id, document_version_id, fact_family, field_path,
    semantic_candidate_key, normalized_text, value_date, amount_paise,
    resolution, winning_document_field_candidate_id, winning_document_field_decision_id
  FROM deduplicated
$$;

CREATE FUNCTION public.search_document_structured_fact_lineage_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE expected record;
BEGIN
  SELECT * INTO expected
  FROM public.read_current_document_structured_search_facts(NEW.org_id, ARRAY[NEW.document_id]) AS fact
  WHERE fact.document_version_id = NEW.document_version_id
    AND fact.fact_family = NEW.fact_family
    AND fact.field_path = NEW.field_path
    AND fact.semantic_candidate_key = NEW.semantic_candidate_key;
  IF expected.document_id IS NULL
     OR expected.document_version_id IS DISTINCT FROM NEW.document_version_id
     OR expected.fact_family IS DISTINCT FROM NEW.fact_family
     OR expected.field_path IS DISTINCT FROM NEW.field_path
     OR expected.semantic_candidate_key IS DISTINCT FROM NEW.semantic_candidate_key
     OR expected.normalized_text IS DISTINCT FROM NEW.normalized_text
     OR expected.value_date IS DISTINCT FROM NEW.value_date
     OR expected.amount_paise IS DISTINCT FROM NEW.amount_paise
     OR expected.resolution IS DISTINCT FROM NEW.resolution
     OR expected.winning_document_field_candidate_id IS DISTINCT FROM NEW.winning_document_field_candidate_id
     OR expected.winning_document_field_decision_id IS DISTINCT FROM NEW.winning_document_field_decision_id THEN
    RAISE EXCEPTION 'structured Search fact must equal one current source-backed effective document value';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER search_document_structured_facts_lineage_guard
  BEFORE INSERT OR UPDATE ON public.search_document_structured_facts
  FOR EACH ROW EXECUTE FUNCTION public.search_document_structured_fact_lineage_guard();

CREATE FUNCTION public.invalidate_current_document_structured_search_facts(
  p_org_id uuid,
  p_document_id uuid
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  DELETE FROM public.search_document_structured_facts
  WHERE org_id = p_org_id AND document_id = p_document_id
$$;

CREATE FUNCTION public.document_invalidate_structured_search_facts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.record_state <> 'active'::public.document_record_state
     OR NEW.deleted_at IS NOT NULL
     OR NEW.current_version_id IS DISTINCT FROM OLD.current_version_id THEN
    PERFORM public.invalidate_current_document_structured_search_facts(OLD.org_id, OLD.id);
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER documents_invalidate_structured_search_facts
  AFTER UPDATE OF record_state, deleted_at, current_version_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.document_invalidate_structured_search_facts();

CREATE FUNCTION public.document_effective_metadata_invalidate_structured_search_facts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE affected record;
BEGIN
  IF TG_OP = 'INSERT' THEN
    FOR affected IN SELECT DISTINCT org_id, document_id FROM new_document_effective_metadata LOOP
      PERFORM public.invalidate_current_document_structured_search_facts(affected.org_id, affected.document_id);
    END LOOP;
  ELSE
    FOR affected IN SELECT DISTINCT org_id, document_id FROM old_document_effective_metadata LOOP
      PERFORM public.invalidate_current_document_structured_search_facts(affected.org_id, affected.document_id);
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER document_effective_metadata_structured_search_facts_delete
  AFTER DELETE ON public.document_effective_metadata
  REFERENCING OLD TABLE AS old_document_effective_metadata
  FOR EACH STATEMENT EXECUTE FUNCTION public.document_effective_metadata_invalidate_structured_search_facts();

CREATE TRIGGER document_effective_metadata_structured_search_facts_insert
  AFTER INSERT ON public.document_effective_metadata
  REFERENCING NEW TABLE AS new_document_effective_metadata
  FOR EACH STATEMENT EXECUTE FUNCTION public.document_effective_metadata_invalidate_structured_search_facts();

CREATE FUNCTION public.write_current_document_structured_search_facts(
  p_processing_run_id uuid,
  p_lease_token uuid,
  p_projection_fingerprint text
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE;
DECLARE document_row public.documents%ROWTYPE;
DECLARE projection_row record;
BEGIN
  IF p_processing_run_id IS NULL OR p_lease_token IS NULL
     OR p_projection_fingerprint IS NULL OR p_projection_fingerprint !~ '^[a-f0-9]{64}$' THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO run_row FROM public.document_processing_runs
  WHERE id = p_processing_run_id FOR UPDATE;
  SELECT * INTO document_row FROM public.documents
  WHERE id = run_row.document_id AND org_id = run_row.org_id FOR UPDATE;
  IF run_row.id IS NULL OR document_row.id IS NULL
     OR run_row.scope <> 'search_index'::public.document_processing_scope
     OR run_row.state <> 'running'::public.document_processing_state
     OR run_row.lease_token IS DISTINCT FROM p_lease_token
     OR run_row.lease_expires_at <= now()
     OR document_row.current_version_id IS DISTINCT FROM run_row.document_version_id
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'version_not_current'::text; RETURN;
  END IF;
  SELECT * INTO projection_row FROM public.read_current_document_search_index_projection(
    run_row.org_id, ARRAY[run_row.document_id]
  );
  IF projection_row.document_id IS NULL
     OR projection_row.document_version_id IS DISTINCT FROM run_row.document_version_id
     OR projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
    -- A is the authoritative metadata-plus-facts fence.  Unlike legacy B it
    -- also changes for a correction to a structured-only field, so cancel the
    -- leased run here before the legacy completion could otherwise accept B.
    UPDATE public.document_processing_runs AS run
    SET state = 'cancelled'::public.document_processing_state,
        stage = 'ready'::public.document_processing_stage,
        started_at = NULL,
        completed_at = NULL,
        failed_at = NULL,
        safe_error_code = 'search_projection_changed',
        lease_token = NULL,
        lease_expires_at = NULL,
        heartbeat_at = now()
    WHERE run.id = run_row.id;
    RETURN QUERY SELECT 'projection_changed'::text; RETURN;
  END IF;
  DELETE FROM public.search_document_structured_facts
  WHERE org_id = run_row.org_id AND document_id = run_row.document_id;
  INSERT INTO public.search_document_structured_facts(
    org_id, document_id, document_version_id, fact_family, field_path,
    semantic_candidate_key, normalized_text, value_date, amount_paise,
    resolution, winning_document_field_candidate_id, winning_document_field_decision_id
  )
  SELECT run_row.org_id, document_id, document_version_id, fact_family, field_path,
    semantic_candidate_key, normalized_text, value_date, amount_paise,
    resolution, winning_document_field_candidate_id, winning_document_field_decision_id
  FROM public.read_current_document_structured_search_facts(run_row.org_id, ARRAY[run_row.document_id]);
  RETURN QUERY SELECT 'indexed'::text;
END $$;

-- Mirror the non-mutating argument checks in the established completion
-- authority.  The structured writer runs first so it needs this gate: an
-- invalid provider envelope must leave both the lease and fact projection
-- untouched rather than relying on a later completion rejection.
CREATE FUNCTION public.search_index_completion_input_is_valid(
  p_outcome text,
  p_embedding vector(768),
  p_embedding_model text,
  p_embedding_version text,
  p_input_tokens integer,
  p_projection_fingerprint text
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT p_outcome IN ('indexed', 'not_indexable', 'failed')
    AND (
      (p_outcome = 'indexed'
        AND p_embedding IS NOT NULL
        AND vector_dims(p_embedding) = 768
        AND p_embedding_model = 'gemini-embedding-001'
        AND p_embedding_version = 'gemini-embedding-001-768-v1'
        AND p_input_tokens IS NOT NULL AND p_input_tokens >= 0
        AND p_projection_fingerprint ~ '^[a-f0-9]{64}$')
      OR (p_outcome = 'not_indexable'
        AND p_embedding IS NULL AND p_embedding_model IS NULL
        AND p_embedding_version IS NULL AND p_input_tokens IS NULL
        AND p_projection_fingerprint ~ '^[a-f0-9]{64}$')
      OR (p_outcome = 'failed'
        AND p_embedding IS NULL AND p_embedding_model IS NULL
        AND p_embedding_version IS NULL AND p_input_tokens IS NULL)
    )
$$;

-- Fold the structured effective values into the existing projection fence.
-- This keeps a worker that read before a correction/clear from completing a
-- metadata vector or structured fact write after that current truth changed.
ALTER FUNCTION public.read_current_document_search_index_projection(uuid, uuid[])
  RENAME TO read_current_search_projection_pre_facts;
REVOKE ALL ON FUNCTION public.read_current_search_projection_pre_facts(uuid, uuid[])
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.read_current_document_search_index_projection(
  p_org_id uuid,
  p_document_ids uuid[]
)
RETURNS TABLE (
  document_id uuid,
  document_version_id uuid,
  doc_type text,
  reference_number text,
  summary text,
  financial_years text[],
  issued_by text,
  projection_fingerprint text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT projection.document_id, projection.document_version_id, projection.doc_type,
    projection.reference_number, projection.summary, projection.financial_years,
    projection.issued_by,
    encode(extensions.digest(jsonb_build_object(
      'metadata_fingerprint', projection.projection_fingerprint,
      'structured_facts', coalesce(facts.value, '[]'::jsonb)
    )::text, 'sha256'), 'hex') AS projection_fingerprint
  FROM public.read_current_search_projection_pre_facts(
    p_org_id, p_document_ids
  ) AS projection
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'fact_family', fact.fact_family,
      'field_path', fact.field_path,
      'semantic_candidate_key', fact.semantic_candidate_key,
      'normalized_text', fact.normalized_text,
      'value_date', fact.value_date,
      'amount_paise', fact.amount_paise,
      'resolution', fact.resolution,
      'candidate_id', fact.winning_document_field_candidate_id,
      'decision_id', fact.winning_document_field_decision_id
    ) ORDER BY fact.fact_family, fact.field_path,
      coalesce(fact.normalized_text, fact.value_date::text, fact.amount_paise::text),
      fact.semantic_candidate_key), '[]'::jsonb) AS value
    FROM public.read_current_document_structured_search_facts(
      p_org_id, ARRAY[projection.document_id]
    ) AS fact
  ) AS facts
$$;

ALTER FUNCTION public.finish_document_search_index_reprocess_work(
  uuid, uuid, text, vector, text, text, integer, text
) RENAME TO finish_search_index_reprocess_pre_facts;
REVOKE ALL ON FUNCTION public.finish_search_index_reprocess_pre_facts(
  uuid, uuid, text, vector, text, text, integer, text
) FROM PUBLIC, anon, authenticated, service_role;

-- Keep the metadata item/run writer on the pre-facts projection. The public
-- projection deliberately includes structured facts for A; this private B
-- writer is the only legacy metadata completion consumer and prevents dynamic
-- function-name resolution from comparing A with the old metadata fingerprint.
CREATE FUNCTION public.upsert_document_metadata_search_storage_legacy_b(
  p_org_id uuid,
  p_document_id uuid,
  p_document_version_id uuid,
  p_projection_fingerprint text,
  p_processing_run_id uuid DEFAULT NULL,
  p_state text DEFAULT 'indexed',
  p_attempt_count integer DEFAULT 0,
  p_safe_error_code text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE document_row public.documents%ROWTYPE;
DECLARE matter_row public.matters%ROWTYPE;
DECLARE version_row public.document_versions%ROWTYPE;
DECLARE projection_row record;
DECLARE item_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_document_id IS NULL OR p_document_version_id IS NULL
     OR p_state NOT IN ('indexed', 'not_indexable', 'failed')
     OR p_attempt_count IS NULL OR p_attempt_count < 0
     OR (p_state IN ('indexed', 'not_indexable')
       AND (p_projection_fingerprint IS NULL OR p_projection_fingerprint !~ '^[a-f0-9]{64}$'))
     OR (p_state = 'failed' AND p_projection_fingerprint IS NOT NULL)
     OR (p_safe_error_code IS NOT NULL AND p_safe_error_code !~ '^[a-z][a-z0-9_]{0,99}$') THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO document_row FROM public.documents AS document
  WHERE document.org_id=p_org_id AND document.id=p_document_id FOR UPDATE;
  SELECT * INTO matter_row FROM public.matters AS matter
  WHERE matter.org_id=p_org_id AND matter.id=document_row.matter_id FOR KEY SHARE;
  SELECT * INTO version_row FROM public.document_versions AS version
  WHERE version.org_id=p_org_id AND version.id=p_document_version_id FOR KEY SHARE;
  IF document_row.id IS NULL OR matter_row.id IS NULL OR version_row.id IS NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR document_row.record_state<>'active'::public.document_record_state OR document_row.deleted_at IS NOT NULL
     OR version_row.document_id IS DISTINCT FROM document_row.id
     OR version_row.state<>'current'::public.document_version_state
     OR version_row.validation_state<>'valid'::public.document_version_validation_state THEN
    RETURN QUERY SELECT 'version_not_current'::text; RETURN;
  END IF;
  IF p_state IN ('indexed', 'not_indexable') THEN
    SELECT * INTO projection_row FROM public.read_current_search_projection_pre_facts(
      p_org_id, ARRAY[p_document_id]
    );
    IF projection_row.document_id IS NULL OR projection_row.document_version_id IS DISTINCT FROM p_document_version_id THEN
      RETURN QUERY SELECT 'version_not_current'::text; RETURN;
    END IF;
    IF projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
      RETURN QUERY SELECT 'projection_changed'::text; RETURN;
    END IF;
    INSERT INTO public.search_items(
      org_id,client_id,matter_id,document_id,document_version_id,source_type,source_id,
      content_availability,title,metadata,content_version_id,content_fingerprint,indexed_at
    ) VALUES (
      p_org_id,matter_row.client_id,matter_row.id,document_row.id,version_row.id,'document_metadata',document_row.id,
      document_row.content_availability,left(coalesce(nullif(document_row.display_title,''),'Document'),500),
      jsonb_strip_nulls(jsonb_build_object('doc_type',projection_row.doc_type,
        'reference_number',projection_row.reference_number,
        'financial_years',coalesce(to_jsonb(projection_row.financial_years),'[]'::jsonb),
        'issued_by',projection_row.issued_by)),
      version_row.id,p_projection_fingerprint,now()
    ) ON CONFLICT (org_id,source_type,source_id) DO UPDATE SET
      client_id=EXCLUDED.client_id,matter_id=EXCLUDED.matter_id,document_id=EXCLUDED.document_id,
      document_version_id=EXCLUDED.document_version_id,visibility=EXCLUDED.visibility,
      content_availability=EXCLUDED.content_availability,title=EXCLUDED.title,metadata=EXCLUDED.metadata,
      content_version_id=EXCLUDED.content_version_id,content_fingerprint=EXCLUDED.content_fingerprint,
      indexing_version=EXCLUDED.indexing_version,indexed_at=EXCLUDED.indexed_at,updated_at=now()
    RETURNING id INTO item_id;
  ELSE
    SELECT item.id INTO item_id FROM public.search_items AS item
    WHERE item.org_id=p_org_id AND item.source_type='document_metadata' AND item.source_id=document_row.id
      AND item.document_version_id=version_row.id FOR KEY SHARE;
  END IF;
  INSERT INTO public.search_index_runs(
    org_id,search_item_id,document_id,document_version_id,source_type,source_id,processing_run_id,state,
    attempt_count,safe_error_code,content_fingerprint,started_at,completed_at,failed_at
  ) VALUES (
    p_org_id,item_id,document_row.id,version_row.id,'document_metadata',document_row.id,p_processing_run_id,p_state,
    p_attempt_count,p_safe_error_code,p_projection_fingerprint,now(),
    CASE WHEN p_state IN ('indexed','not_indexable') THEN now() ELSE NULL END,
    CASE WHEN p_state='failed' THEN now() ELSE NULL END
  ) ON CONFLICT (org_id,source_type,source_id) DO UPDATE SET
    search_item_id=EXCLUDED.search_item_id,document_id=EXCLUDED.document_id,document_version_id=EXCLUDED.document_version_id,
    processing_run_id=EXCLUDED.processing_run_id,state=EXCLUDED.state,attempt_count=EXCLUDED.attempt_count,
    safe_error_code=EXCLUDED.safe_error_code,content_fingerprint=EXCLUDED.content_fingerprint,
    indexing_version=EXCLUDED.indexing_version,started_at=EXCLUDED.started_at,completed_at=EXCLUDED.completed_at,
    failed_at=EXCLUDED.failed_at,updated_at=now();
  RETURN QUERY SELECT p_state::text;
END $$;

-- Recreate the pre-facts completion body with an explicit B reader and B
-- metadata storage writer. It otherwise preserves the legacy run transition,
-- retry, embedding, terminal replay, and projection-change behaviour.
CREATE OR REPLACE FUNCTION public.finish_search_index_reprocess_pre_facts(
  p_processing_run_id uuid,p_lease_token uuid,p_outcome text,p_embedding vector(768) DEFAULT NULL,
  p_embedding_model text DEFAULT NULL,p_embedding_version text DEFAULT NULL,p_input_tokens integer DEFAULT NULL,
  p_projection_fingerprint text DEFAULT NULL
) RETURNS TABLE(code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE run_row public.document_processing_runs%ROWTYPE;
DECLARE document_row public.documents%ROWTYPE;
DECLARE projection_row record;
DECLARE result record;
DECLARE storage_result record;
BEGIN
  IF p_outcome IN ('indexed','not_indexable')
     AND (p_projection_fingerprint IS NULL OR p_projection_fingerprint !~ '^[a-f0-9]{64}$') THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  SELECT * INTO run_row FROM public.document_processing_runs AS run WHERE run.id=p_processing_run_id FOR UPDATE;
  IF run_row.id IS NOT NULL AND run_row.scope='search_index'::public.document_processing_scope
     AND run_row.state='running'::public.document_processing_state
     AND run_row.lease_token IS NOT DISTINCT FROM p_lease_token AND run_row.lease_expires_at>now()
     AND p_outcome IN ('indexed','not_indexable') THEN
    SELECT * INTO document_row FROM public.documents AS document
    WHERE document.org_id=run_row.org_id AND document.id=run_row.document_id FOR UPDATE;
    SELECT * INTO projection_row FROM public.read_current_search_projection_pre_facts(
      run_row.org_id,ARRAY[run_row.document_id]
    );
    IF document_row.id IS NOT NULL AND projection_row.document_id IS NOT NULL
       AND projection_row.document_version_id=run_row.document_version_id
       AND projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
      UPDATE public.document_processing_runs AS run SET state='cancelled'::public.document_processing_state,
        stage='ready'::public.document_processing_stage,started_at=NULL,completed_at=NULL,failed_at=NULL,
        safe_error_code='search_projection_changed',lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now()
      WHERE run.id=run_row.id;
      RETURN QUERY SELECT 'projection_changed'::text; RETURN;
    END IF;
  END IF;
  SELECT * INTO result FROM public.finish_document_search_index_reprocess_work_unfingerprinted(
    p_processing_run_id,p_lease_token,p_outcome,p_embedding,p_embedding_model,p_embedding_version,p_input_tokens
  );
  IF result.code='not_indexable' THEN
    UPDATE public.documents AS document SET embedding=NULL,embedding_model=NULL,embedding_version=NULL,
      embedding_document_version_id=NULL
    WHERE document.org_id=run_row.org_id AND document.id=run_row.document_id
      AND document.current_version_id=run_row.document_version_id;
  END IF;
  IF result.code IN ('indexed','not_indexable') THEN
    SELECT * INTO storage_result FROM public.upsert_document_metadata_search_storage_legacy_b(
      run_row.org_id,run_row.document_id,run_row.document_version_id,p_projection_fingerprint,
      run_row.id,result.code,run_row.attempt_count,NULL
    );
    RETURN QUERY SELECT CASE WHEN storage_result.code=result.code THEN result.code ELSE storage_result.code END::text;
    RETURN;
  ELSIF result.code='failed' THEN
    PERFORM public.upsert_document_metadata_search_storage_legacy_b(
      run_row.org_id,run_row.document_id,run_row.document_version_id,NULL,run_row.id,
      'failed',run_row.attempt_count,'search_index_failed'
    );
  END IF;
  RETURN QUERY SELECT result.code::text;
END $$;

CREATE FUNCTION public.finish_document_search_index_reprocess_work(
  p_processing_run_id uuid,
  p_lease_token uuid,
  p_outcome text,
  p_embedding vector(768) DEFAULT NULL,
  p_embedding_model text DEFAULT NULL,
  p_embedding_version text DEFAULT NULL,
  p_input_tokens integer DEFAULT NULL,
  p_projection_fingerprint text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE fact_write record;
DECLARE completion record;
DECLARE legacy_projection record;
DECLARE run_state public.document_processing_state;
BEGIN
  IF NOT public.search_index_completion_input_is_valid(
    p_outcome, p_embedding, p_embedding_model, p_embedding_version,
    p_input_tokens, p_projection_fingerprint
  ) THEN
    RETURN QUERY SELECT 'invalid_request'::text; RETURN;
  END IF;
  -- Preserve the existing terminal replay contract before consulting the
  -- leased fact writer. A completed replay is a no-op, never a stale-write
  -- failure that could make delivery retry indefinitely.
  SELECT state INTO run_state FROM public.document_processing_runs
  WHERE id = p_processing_run_id FOR KEY SHARE;
  IF run_state IS DISTINCT FROM 'running'::public.document_processing_state THEN
    SELECT * INTO completion FROM public.finish_search_index_reprocess_pre_facts(
      p_processing_run_id, p_lease_token, p_outcome, p_embedding,
      p_embedding_model, p_embedding_version, p_input_tokens, p_projection_fingerprint
    );
    RETURN QUERY SELECT completion.code::text; RETURN;
  END IF;
  IF p_outcome IN ('indexed', 'not_indexable') THEN
    -- The worker received the combined metadata/fact fingerprint. Preserve it
    -- for the fact writer, but carry the corresponding legacy-only value into
    -- the established metadata/vector completion authority. Its own fence is
    -- intentionally unchanged and cannot compare a combined fingerprint.
    SELECT * INTO legacy_projection
    FROM public.read_current_search_projection_pre_facts(
      (SELECT org_id FROM public.document_processing_runs WHERE id = p_processing_run_id),
      ARRAY[(SELECT document_id FROM public.document_processing_runs WHERE id = p_processing_run_id)]
    );
    IF legacy_projection.document_id IS NULL THEN
      RETURN QUERY SELECT 'projection_changed'::text; RETURN;
    END IF;
    SELECT * INTO fact_write FROM public.write_current_document_structured_search_facts(
      p_processing_run_id, p_lease_token, p_projection_fingerprint
    );
    IF fact_write.code <> 'indexed' THEN
      RETURN QUERY SELECT fact_write.code::text; RETURN;
    END IF;
  END IF;
  SELECT * INTO completion FROM public.finish_search_index_reprocess_pre_facts(
    p_processing_run_id, p_lease_token, p_outcome, p_embedding,
    p_embedding_model, p_embedding_version, p_input_tokens,
    CASE WHEN p_outcome IN ('indexed', 'not_indexable')
      THEN legacy_projection.projection_fingerprint ELSE p_projection_fingerprint END
  );
  RETURN QUERY SELECT completion.code::text;
END $$;

-- The durable outbox lease is now the sole production Search writer.  Matter
-- reindex already enqueues that route; retain the old signature only so a
-- stale service integration fails closed instead of writing around it.
REVOKE ALL ON FUNCTION public.write_current_document_search_index_embedding(
  uuid, uuid, uuid, vector, text, text, integer, text
) FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.search_document_structured_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_document_structured_facts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.search_document_structured_facts
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.read_current_document_structured_search_facts(uuid,uuid[]),
  public.search_document_structured_fact_lineage_guard(),
  public.invalidate_current_document_structured_search_facts(uuid,uuid),
  public.document_invalidate_structured_search_facts(),
  public.document_effective_metadata_invalidate_structured_search_facts(),
  public.search_index_completion_input_is_valid(text,vector,text,text,integer,text),
  public.upsert_document_metadata_search_storage_legacy_b(uuid,uuid,uuid,text,uuid,text,integer,text),
  public.write_current_document_structured_search_facts(uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.read_current_document_search_index_projection(uuid,uuid[])
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(
  uuid,uuid,text,vector,text,text,integer,text
) FROM PUBLIC, anon, authenticated;
-- These SECURITY DEFINER implementation helpers are reachable only through
-- the leased public completion RPC above.  Keep an explicit tail revoke so a
-- later CREATE OR REPLACE cannot accidentally reopen a direct writer route.
REVOKE ALL ON FUNCTION public.upsert_document_metadata_search_storage_legacy_b(
  uuid,uuid,uuid,text,uuid,text,integer,text
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.finish_search_index_reprocess_pre_facts(
  uuid,uuid,text,vector,text,text,integer,text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.read_current_document_search_index_projection(uuid,uuid[])
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(
  uuid,uuid,text,vector,text,text,integer,text
) TO service_role;

COMMENT ON TABLE public.search_document_structured_facts IS
  'Private service-written current document Search facts, sourced only from exact effective candidate/decision lineage. Legal-reference act/kind and general party facts remain deferred until canonical domains exist.';
COMMENT ON FUNCTION public.write_current_document_structured_search_facts(uuid,uuid,text) IS
  'Internal leased writer for source-backed current structured Search facts. The exact current version and combined metadata/fact projection fingerprint must still match.';
COMMENT ON FUNCTION public.read_current_document_structured_search_facts(uuid,uuid[]) IS
  'Internal current effective fact normalizer. Amounts are exact INR paise only; non-exact decimals and bigint-overflow values are excluded.';

COMMIT;
