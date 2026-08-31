-- Private, current document-metadata Search storage. This deliberately keeps
-- no extracted content, object locators, embeddings, provider payloads, or
-- query text. The two service-only writers below retain the existing exact
-- document-version and projection-fingerprint fences before writing here.
BEGIN;

CREATE FUNCTION public.search_item_metadata_is_safe(p_metadata jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, public
AS $$
  SELECT jsonb_typeof(p_metadata) = 'object'
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_object_keys(p_metadata) AS key
      WHERE key NOT IN ('doc_type', 'reference_number', 'financial_years', 'issued_by')
    )
    AND (
      NOT p_metadata ? 'doc_type'
      OR (jsonb_typeof(p_metadata -> 'doc_type') = 'string'
          AND char_length(p_metadata ->> 'doc_type') BETWEEN 1 AND 200)
    )
    AND (
      NOT p_metadata ? 'reference_number'
      OR (jsonb_typeof(p_metadata -> 'reference_number') = 'string'
          AND char_length(p_metadata ->> 'reference_number') BETWEEN 1 AND 300)
    )
    AND (
      NOT p_metadata ? 'issued_by'
      OR (jsonb_typeof(p_metadata -> 'issued_by') = 'string'
          AND char_length(p_metadata ->> 'issued_by') BETWEEN 1 AND 300)
    )
    AND (
      NOT p_metadata ? 'financial_years'
      OR (
        jsonb_typeof(p_metadata -> 'financial_years') = 'array'
        AND jsonb_array_length(p_metadata -> 'financial_years') <= 32
        AND NOT EXISTS (
          SELECT 1
          FROM jsonb_array_elements(p_metadata -> 'financial_years') AS financial_year(value)
          WHERE jsonb_typeof(financial_year.value) <> 'string'
            OR char_length(financial_year.value #>> '{}') NOT BETWEEN 1 AND 32
        )
      )
    )
$$;

CREATE TABLE public.search_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  client_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  source_type text NOT NULL CHECK (source_type = 'document_metadata'),
  source_id uuid NOT NULL,
  visibility text NOT NULL DEFAULT 'organisation_members'
    CHECK (visibility = 'organisation_members'),
  content_availability public.document_content_availability NOT NULL,
  title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 500),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
    CHECK (public.search_item_metadata_is_safe(metadata)),
  content_version_id uuid NOT NULL,
  content_fingerprint text NOT NULL CHECK (content_fingerprint ~ '^[a-f0-9]{64}$'),
  indexing_version text NOT NULL DEFAULT 'document_metadata_v1'
    CHECK (indexing_version = 'document_metadata_v1'),
  indexed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT search_items_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT search_items_client_org_fkey
    FOREIGN KEY (org_id, client_id) REFERENCES public.clients(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_items_matter_org_fkey
    FOREIGN KEY (org_id, matter_id) REFERENCES public.matters(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_items_document_org_fkey
    FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_items_document_version_org_fkey
    FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_items_content_version_matches_document_version
    CHECK (content_version_id = document_version_id),
  CONSTRAINT search_items_document_metadata_source_matches_document
    CHECK (source_id = document_id),
  CONSTRAINT search_items_current_source_unique UNIQUE (org_id, source_type, source_id)
);

CREATE INDEX search_items_document_current_idx
  ON public.search_items(org_id, document_id, document_version_id);

CREATE TABLE public.search_index_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  search_item_id uuid,
  document_id uuid NOT NULL,
  document_version_id uuid NOT NULL,
  source_type text NOT NULL CHECK (source_type = 'document_metadata'),
  source_id uuid NOT NULL,
  processing_run_id uuid,
  state text NOT NULL CHECK (state IN ('indexed', 'not_indexable', 'failed')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  safe_error_code text CHECK (safe_error_code IS NULL OR safe_error_code ~ '^[a-z][a-z0-9_]{0,99}$'),
  content_fingerprint text CHECK (content_fingerprint IS NULL OR content_fingerprint ~ '^[a-f0-9]{64}$'),
  indexing_version text NOT NULL DEFAULT 'document_metadata_v1'
    CHECK (indexing_version = 'document_metadata_v1'),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT search_index_runs_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT search_index_runs_item_org_fkey
    FOREIGN KEY (org_id, search_item_id) REFERENCES public.search_items(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_index_runs_document_org_fkey
    FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_index_runs_document_version_org_fkey
    FOREIGN KEY (org_id, document_version_id)
    REFERENCES public.document_versions(org_id, id) ON DELETE CASCADE,
  CONSTRAINT search_index_runs_source_matches_document CHECK (source_id = document_id),
  CONSTRAINT search_index_runs_terminal_timestamps CHECK (
    (state IN ('indexed', 'not_indexable') AND started_at IS NOT NULL
      AND completed_at IS NOT NULL AND failed_at IS NULL)
    OR (state = 'failed' AND started_at IS NOT NULL
      AND completed_at IS NULL AND failed_at IS NOT NULL)
  ),
  CONSTRAINT search_index_runs_current_source_unique UNIQUE (org_id, source_type, source_id)
);

CREATE INDEX search_index_runs_document_current_idx
  ON public.search_index_runs(org_id, document_id, document_version_id);

CREATE FUNCTION public.search_item_document_lineage_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  document_row public.documents%ROWTYPE;
  matter_row public.matters%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
BEGIN
  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.org_id = NEW.org_id AND document.id = NEW.document_id
  FOR KEY SHARE;
  SELECT * INTO matter_row
  FROM public.matters AS matter
  WHERE matter.org_id = NEW.org_id AND matter.id = NEW.matter_id
  FOR KEY SHARE;
  SELECT * INTO version_row
  FROM public.document_versions AS version
  WHERE version.org_id = NEW.org_id AND version.id = NEW.document_version_id
  FOR KEY SHARE;

  IF document_row.id IS NULL OR matter_row.id IS NULL OR version_row.id IS NULL
     OR NEW.source_type <> 'document_metadata'
     OR NEW.source_id IS DISTINCT FROM document_row.id
     OR NEW.client_id IS DISTINCT FROM matter_row.client_id
     OR document_row.matter_id IS DISTINCT FROM matter_row.id
     OR version_row.document_id IS DISTINCT FROM document_row.id
     OR NEW.content_version_id IS DISTINCT FROM version_row.id
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RAISE EXCEPTION 'search item must describe one active current document version and its exact lineage';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER search_items_document_lineage_guard
  BEFORE INSERT OR UPDATE ON public.search_items
  FOR EACH ROW EXECUTE FUNCTION public.search_item_document_lineage_guard();

CREATE FUNCTION public.invalidate_document_metadata_search_storage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.record_state <> 'active'::public.document_record_state
     OR NEW.deleted_at IS NOT NULL
     OR NEW.current_version_id IS DISTINCT FROM OLD.current_version_id THEN
    DELETE FROM public.search_index_runs
    WHERE org_id = OLD.org_id AND document_id = OLD.id;
    DELETE FROM public.search_items
    WHERE org_id = OLD.org_id AND document_id = OLD.id;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER documents_invalidate_metadata_search_storage
  AFTER UPDATE OF record_state, deleted_at, current_version_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.invalidate_document_metadata_search_storage();

-- The shared Search projection overlays current effective metadata on the
-- legacy document scalar fields. Remove the private current item/run in the
-- same transaction as any overlay change, before the durable reindex can
-- recreate it. DELETE matters because effective-metadata recompute first
-- removes the prior projection rows; INSERT covers automatic, corrected,
-- rejected, and cleared rows (including their NULL values).
CREATE FUNCTION public.invalidate_current_document_metadata_search_storage(
  p_org_id uuid,
  p_document_id uuid,
  p_document_version_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  document_row public.documents%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
BEGIN
  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.org_id = p_org_id AND document.id = p_document_id
  FOR UPDATE;
  SELECT * INTO version_row
  FROM public.document_versions AS version
  WHERE version.org_id = p_org_id
    AND version.id = p_document_version_id
    AND version.document_id = p_document_id
  FOR KEY SHARE;
  IF document_row.id IS NULL OR version_row.id IS NULL
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RETURN;
  END IF;
  DELETE FROM public.search_index_runs
  WHERE org_id = document_row.org_id AND document_id = document_row.id;
  DELETE FROM public.search_items
  WHERE org_id = document_row.org_id AND document_id = document_row.id;
END $$;

CREATE FUNCTION public.document_effective_metadata_invalidate_search_storage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  affected record;
BEGIN
  IF TG_OP = 'INSERT' THEN
    FOR affected IN
      SELECT DISTINCT org_id, document_id, document_version_id
      FROM new_document_effective_metadata
      WHERE field_path IN (
        'document.type',
        'document.reference_number',
        'document.financial_year',
        'document.issued_by'
      )
    LOOP
      PERFORM public.invalidate_current_document_metadata_search_storage(
        affected.org_id, affected.document_id, affected.document_version_id
      );
    END LOOP;
  ELSE
    FOR affected IN
      SELECT DISTINCT org_id, document_id, document_version_id
      FROM old_document_effective_metadata
      WHERE field_path IN (
        'document.type',
        'document.reference_number',
        'document.financial_year',
        'document.issued_by'
      )
    LOOP
      PERFORM public.invalidate_current_document_metadata_search_storage(
        affected.org_id, affected.document_id, affected.document_version_id
      );
    END LOOP;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER document_effective_metadata_delete_invalidate_search_storage
  AFTER DELETE ON public.document_effective_metadata
  REFERENCING OLD TABLE AS old_document_effective_metadata
  FOR EACH STATEMENT EXECUTE FUNCTION public.document_effective_metadata_invalidate_search_storage();

CREATE TRIGGER document_effective_metadata_insert_invalidate_search_storage
  AFTER INSERT ON public.document_effective_metadata
  REFERENCING NEW TABLE AS new_document_effective_metadata
  FOR EACH STATEMENT EXECUTE FUNCTION public.document_effective_metadata_invalidate_search_storage();

-- These bounded scalar columns are the non-effective fallback values read by
-- the same projection; title, availability, and matter lineage are emitted
-- into the private item too. Any change waits for one fenced reindex rather
-- than serving a stale current item.
CREATE FUNCTION public.invalidate_document_metadata_search_storage_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NEW.doc_type IS DISTINCT FROM OLD.doc_type
     OR NEW.reference_number IS DISTINCT FROM OLD.reference_number
     OR NEW.summary IS DISTINCT FROM OLD.summary
     OR NEW.financial_year IS DISTINCT FROM OLD.financial_year
     OR NEW.issued_by IS DISTINCT FROM OLD.issued_by
     OR NEW.display_title IS DISTINCT FROM OLD.display_title
     OR NEW.content_availability IS DISTINCT FROM OLD.content_availability
     OR NEW.matter_id IS DISTINCT FROM OLD.matter_id THEN
    PERFORM public.invalidate_current_document_metadata_search_storage(
      OLD.org_id, OLD.id, OLD.current_version_id
    );
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER documents_invalidate_metadata_search_storage_projection
  AFTER UPDATE OF doc_type, reference_number, summary, financial_year, issued_by,
    display_title, content_availability, matter_id ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.invalidate_document_metadata_search_storage_projection();

-- The historical matters.client_id foreign key proves only that a client
-- exists. Make its organisation lineage explicit before any private Search
-- projection can depend on it, without changing the legacy FK delete policy.
CREATE FUNCTION public.matter_client_same_org_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  client_row public.clients%ROWTYPE;
BEGIN
  SELECT * INTO client_row
  FROM public.clients AS client
  WHERE client.id = NEW.client_id
  FOR KEY SHARE;
  IF client_row.id IS NULL OR client_row.org_id IS DISTINCT FROM NEW.org_id THEN
    RAISE EXCEPTION 'matter client must belong to the same organisation';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER matters_client_same_org_guard
  BEFORE INSERT OR UPDATE OF org_id, client_id ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.matter_client_same_org_guard();

-- Take every affected document lock before removing projections. A completion
-- based on the prior client either finishes first and is removed here, or
-- waits and re-derives the new lineage afterwards.
CREATE FUNCTION public.invalidate_matter_client_metadata_search_storage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  document_row record;
BEGIN
  IF NEW.client_id IS NOT DISTINCT FROM OLD.client_id THEN
    RETURN NEW;
  END IF;
  FOR document_row IN
    SELECT document.id
    FROM public.documents AS document
    WHERE document.org_id = NEW.org_id AND document.matter_id = NEW.id
    ORDER BY document.id
    FOR UPDATE
  LOOP
    DELETE FROM public.search_index_runs
    WHERE org_id = NEW.org_id AND document_id = document_row.id;
    DELETE FROM public.search_items
    WHERE org_id = NEW.org_id AND document_id = document_row.id;
  END LOOP;
  RETURN NEW;
END $$;

CREATE TRIGGER matters_invalidate_client_metadata_search_storage
  AFTER UPDATE OF client_id ON public.matters
  FOR EACH ROW EXECUTE FUNCTION public.invalidate_matter_client_metadata_search_storage();

-- This function deliberately accepts only identities and a fingerprint. It
-- reads the bounded projection itself and is never executable by callers.
CREATE FUNCTION public.upsert_current_document_metadata_search_storage(
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
DECLARE
  document_row public.documents%ROWTYPE;
  matter_row public.matters%ROWTYPE;
  version_row public.document_versions%ROWTYPE;
  projection_row record;
  item_id uuid;
BEGIN
  IF p_org_id IS NULL OR p_document_id IS NULL OR p_document_version_id IS NULL
     OR p_state NOT IN ('indexed', 'not_indexable', 'failed')
     OR p_attempt_count IS NULL OR p_attempt_count < 0
     OR (p_state IN ('indexed', 'not_indexable')
       AND (p_projection_fingerprint IS NULL OR p_projection_fingerprint !~ '^[a-f0-9]{64}$'))
     OR (p_state = 'failed' AND p_projection_fingerprint IS NOT NULL)
     OR (p_safe_error_code IS NOT NULL AND p_safe_error_code !~ '^[a-z][a-z0-9_]{0,99}$') THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;

  SELECT * INTO document_row
  FROM public.documents AS document
  WHERE document.org_id = p_org_id AND document.id = p_document_id
  FOR UPDATE;
  SELECT * INTO matter_row
  FROM public.matters AS matter
  WHERE matter.org_id = p_org_id AND matter.id = document_row.matter_id
  FOR KEY SHARE;
  SELECT * INTO version_row
  FROM public.document_versions AS version
  WHERE version.org_id = p_org_id AND version.id = p_document_version_id
  FOR KEY SHARE;
  IF document_row.id IS NULL OR matter_row.id IS NULL OR version_row.id IS NULL
     OR document_row.current_version_id IS DISTINCT FROM version_row.id
     OR document_row.record_state <> 'active'::public.document_record_state
     OR document_row.deleted_at IS NOT NULL
     OR version_row.document_id IS DISTINCT FROM document_row.id
     OR version_row.state <> 'current'::public.document_version_state
     OR version_row.validation_state <> 'valid'::public.document_version_validation_state THEN
    RETURN QUERY SELECT 'version_not_current'::text;
    RETURN;
  END IF;

  IF p_state IN ('indexed', 'not_indexable') THEN
    SELECT * INTO projection_row
    FROM public.read_current_document_search_index_projection(p_org_id, ARRAY[p_document_id]);
    IF projection_row.document_id IS NULL
       OR projection_row.document_version_id IS DISTINCT FROM p_document_version_id THEN
      RETURN QUERY SELECT 'version_not_current'::text;
      RETURN;
    END IF;
    IF projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
      RETURN QUERY SELECT 'projection_changed'::text;
      RETURN;
    END IF;

    INSERT INTO public.search_items(
      org_id, client_id, matter_id, document_id, document_version_id,
      source_type, source_id, content_availability, title, metadata,
      content_version_id, content_fingerprint, indexed_at
    ) VALUES (
      p_org_id, matter_row.client_id, matter_row.id, document_row.id, version_row.id,
      'document_metadata', document_row.id, document_row.content_availability,
      left(coalesce(nullif(document_row.display_title, ''), 'Document'), 500),
      jsonb_strip_nulls(jsonb_build_object(
        'doc_type', projection_row.doc_type,
        'reference_number', projection_row.reference_number,
        'financial_years', coalesce(to_jsonb(projection_row.financial_years), '[]'::jsonb),
        'issued_by', projection_row.issued_by
      )),
      version_row.id, p_projection_fingerprint, now()
    )
    ON CONFLICT (org_id, source_type, source_id) DO UPDATE
    SET client_id = EXCLUDED.client_id,
        matter_id = EXCLUDED.matter_id,
        document_id = EXCLUDED.document_id,
        document_version_id = EXCLUDED.document_version_id,
        visibility = EXCLUDED.visibility,
        content_availability = EXCLUDED.content_availability,
        title = EXCLUDED.title,
        metadata = EXCLUDED.metadata,
        content_version_id = EXCLUDED.content_version_id,
        content_fingerprint = EXCLUDED.content_fingerprint,
        indexing_version = EXCLUDED.indexing_version,
        indexed_at = EXCLUDED.indexed_at,
        updated_at = now()
    RETURNING id INTO item_id;
  ELSE
    SELECT item.id INTO item_id
    FROM public.search_items AS item
    WHERE item.org_id = p_org_id
      AND item.source_type = 'document_metadata'
      AND item.source_id = document_row.id
      AND item.document_version_id = version_row.id
    FOR KEY SHARE;
  END IF;

  INSERT INTO public.search_index_runs(
    org_id, search_item_id, document_id, document_version_id,
    source_type, source_id, processing_run_id, state, attempt_count,
    safe_error_code, content_fingerprint, started_at, completed_at, failed_at
  ) VALUES (
    p_org_id, item_id, document_row.id, version_row.id,
    'document_metadata', document_row.id, p_processing_run_id, p_state, p_attempt_count,
    p_safe_error_code, p_projection_fingerprint, now(),
    CASE WHEN p_state IN ('indexed', 'not_indexable') THEN now() ELSE NULL END,
    CASE WHEN p_state = 'failed' THEN now() ELSE NULL END
  )
  ON CONFLICT (org_id, source_type, source_id) DO UPDATE
  SET search_item_id = EXCLUDED.search_item_id,
      document_id = EXCLUDED.document_id,
      document_version_id = EXCLUDED.document_version_id,
      processing_run_id = EXCLUDED.processing_run_id,
      state = EXCLUDED.state,
      attempt_count = EXCLUDED.attempt_count,
      safe_error_code = EXCLUDED.safe_error_code,
      content_fingerprint = EXCLUDED.content_fingerprint,
      indexing_version = EXCLUDED.indexing_version,
      started_at = EXCLUDED.started_at,
      completed_at = EXCLUDED.completed_at,
      failed_at = EXCLUDED.failed_at,
      updated_at = now();

  RETURN QUERY SELECT p_state::text;
END $$;

ALTER FUNCTION public.write_current_document_search_index_embedding(
  uuid, uuid, uuid, vector, text, text, integer, text
) RENAME TO write_current_document_search_index_embedding_pre_item_storage;
REVOKE ALL ON FUNCTION public.write_current_document_search_index_embedding_pre_item_storage(
  uuid, uuid, uuid, vector, text, text, integer, text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.write_current_document_search_index_embedding(
  p_org_id uuid,
  p_document_id uuid,
  p_document_version_id uuid,
  p_embedding vector(768),
  p_embedding_model text,
  p_embedding_version text,
  p_input_tokens integer,
  p_projection_fingerprint text DEFAULT NULL
)
RETURNS TABLE(code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  result record;
  storage_result record;
BEGIN
  SELECT * INTO result
  FROM public.write_current_document_search_index_embedding_pre_item_storage(
    p_org_id, p_document_id, p_document_version_id, p_embedding,
    p_embedding_model, p_embedding_version, p_input_tokens, p_projection_fingerprint
  );
  IF result.code <> 'indexed' THEN
    RETURN QUERY SELECT result.code::text;
    RETURN;
  END IF;
  SELECT * INTO storage_result
  FROM public.upsert_current_document_metadata_search_storage(
    p_org_id, p_document_id, p_document_version_id, p_projection_fingerprint,
    NULL, 'indexed', 0, NULL
  );
  RETURN QUERY SELECT CASE
    WHEN storage_result.code = 'indexed' THEN 'indexed'
    ELSE storage_result.code
  END::text;
END $$;

ALTER FUNCTION public.finish_document_search_index_reprocess_work(
  uuid, uuid, text, vector, text, text, integer, text
) RENAME TO finish_document_search_index_reprocess_work_pre_item_storage;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work_pre_item_storage(
  uuid, uuid, text, vector, text, text, integer, text
) FROM PUBLIC, anon, authenticated, service_role;

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
DECLARE
  run_row public.document_processing_runs%ROWTYPE;
  document_row public.documents%ROWTYPE;
  projection_row record;
  result record;
  storage_result record;
BEGIN
  IF p_outcome IN ('indexed', 'not_indexable')
     AND (p_projection_fingerprint IS NULL
       OR p_projection_fingerprint !~ '^[a-f0-9]{64}$') THEN
    RETURN QUERY SELECT 'invalid_request'::text;
    RETURN;
  END IF;

  SELECT * INTO run_row
  FROM public.document_processing_runs AS run
  WHERE run.id = p_processing_run_id
  FOR UPDATE;
  IF run_row.id IS NOT NULL
     AND run_row.scope = 'search_index'::public.document_processing_scope
     AND run_row.state = 'running'::public.document_processing_state
     AND run_row.lease_token IS NOT DISTINCT FROM p_lease_token
     AND run_row.lease_expires_at > now()
     AND p_outcome IN ('indexed', 'not_indexable') THEN
    SELECT * INTO document_row
    FROM public.documents AS document
    WHERE document.org_id = run_row.org_id
      AND document.id = run_row.document_id
    FOR UPDATE;
    SELECT * INTO projection_row
    FROM public.read_current_document_search_index_projection(
      run_row.org_id,
      ARRAY[run_row.document_id]
    );
    IF document_row.id IS NOT NULL
       AND projection_row.document_id IS NOT NULL
       AND projection_row.document_version_id = run_row.document_version_id
       AND projection_row.projection_fingerprint IS DISTINCT FROM p_projection_fingerprint THEN
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
      RETURN QUERY SELECT 'projection_changed'::text;
      RETURN;
    END IF;
  END IF;

  SELECT * INTO result
  FROM public.finish_document_search_index_reprocess_work_pre_item_storage(
    p_processing_run_id, p_lease_token, p_outcome, p_embedding,
    p_embedding_model, p_embedding_version, p_input_tokens, p_projection_fingerprint
  );
  IF result.code IN ('indexed', 'not_indexable') THEN
    SELECT * INTO storage_result
    FROM public.upsert_current_document_metadata_search_storage(
      run_row.org_id, run_row.document_id, run_row.document_version_id,
      p_projection_fingerprint, run_row.id, result.code, run_row.attempt_count, NULL
    );
    RETURN QUERY SELECT CASE
      WHEN storage_result.code = result.code THEN result.code
      ELSE storage_result.code
    END::text;
    RETURN;
  ELSIF result.code = 'failed' THEN
    SELECT * INTO storage_result
    FROM public.upsert_current_document_metadata_search_storage(
      run_row.org_id, run_row.document_id, run_row.document_version_id,
      NULL, run_row.id, 'failed', run_row.attempt_count, 'search_index_failed'
    );
  END IF;
  RETURN QUERY SELECT result.code::text;
END $$;

ALTER TABLE public.search_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.search_index_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.search_index_runs FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.search_items, public.search_index_runs
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.search_item_metadata_is_safe(jsonb),
  public.search_item_document_lineage_guard(),
  public.invalidate_document_metadata_search_storage(),
  public.invalidate_current_document_metadata_search_storage(uuid,uuid,uuid),
  public.document_effective_metadata_invalidate_search_storage(),
  public.invalidate_document_metadata_search_storage_projection(),
  public.matter_client_same_org_guard(),
  public.invalidate_matter_client_metadata_search_storage(),
  public.upsert_current_document_metadata_search_storage(uuid,uuid,uuid,text,uuid,text,integer,text),
  public.write_current_document_search_index_embedding_pre_item_storage(uuid,uuid,uuid,vector,text,text,integer,text),
  public.finish_document_search_index_reprocess_work_pre_item_storage(uuid,uuid,text,vector,text,text,integer,text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.write_current_document_search_index_embedding(
  uuid, uuid, uuid, vector, text, text, integer, text
) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_document_search_index_reprocess_work(
  uuid, uuid, text, vector, text, text, integer, text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_current_document_search_index_embedding(
  uuid, uuid, uuid, vector, text, text, integer, text
) TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_search_index_reprocess_work(
  uuid, uuid, text, vector, text, text, integer, text
) TO service_role;

COMMENT ON TABLE public.search_items IS
  'Private current Search source-owner metadata. This initial slice contains only bounded document metadata and never extracted text, files, URLs, query text, or embeddings.';
COMMENT ON TABLE public.search_index_runs IS
  'Private current Search indexing state for one source owner. Safe operational state only; no source content or provider payload.';
COMMENT ON FUNCTION public.document_effective_metadata_invalidate_search_storage() IS
  'Internal statement-level invalidation of private current Search metadata storage when effective Search projection rows are inserted or removed, including cleared and rejected values.';
COMMENT ON FUNCTION public.matter_client_same_org_guard() IS
  'Maintains the same-organisation Matter-to-Client invariant before any document Search lineage is projected.';
COMMENT ON FUNCTION public.finish_document_search_index_reprocess_work(uuid,uuid,text,vector,text,text,integer,text) IS
  'Service-only leased Search completion. Retains exact current document/version/projection fences and atomically updates the legacy embedding plus private current metadata Search storage.';

COMMIT;
