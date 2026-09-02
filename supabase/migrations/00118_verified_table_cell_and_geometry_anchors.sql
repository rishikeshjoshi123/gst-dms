-- Canonical table cells and exact persisted anchor derivation.  This is a
-- hardening successor to 00117: callers may not choose in-bounds tokens or
-- arbitrary boxes; the completion authority derives both from the acquired
-- page artifact.
BEGIN;

CREATE FUNCTION public.document_page_text_table_cells_are_safe(p_cells jsonb)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $$
  SELECT p_cells IS NULL OR p_cells = 'null'::jsonb OR (
    jsonb_typeof(p_cells) = 'array' AND jsonb_array_length(p_cells) <= 500
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(p_cells) cell(value)
      WHERE jsonb_typeof(cell.value) <> 'object'
        OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(cell.value) key)
          IS DISTINCT FROM ARRAY['column_index','column_span','height','reading_order','row_index','row_span','table_index','text','width','x','y']::text[]
        OR (cell.value->>'table_index') !~ '^[0-9]{1,2}$'
        OR (cell.value->>'row_index') !~ '^[0-9]{1,3}$'
        OR (cell.value->>'column_index') !~ '^[0-9]{1,3}$'
        OR (cell.value->>'row_span') !~ '^[1-9][0-9]?$'
        OR (cell.value->>'column_span') !~ '^[1-9][0-9]?$'
        OR (cell.value->>'reading_order') !~ '^[0-9]{1,5}$'
        OR jsonb_typeof(cell.value->'text') <> 'string' OR char_length(cell.value->>'text') NOT BETWEEN 1 AND 1000
        OR (cell.value->>'text') ~ E'[\\x00-\\x1F\\x7F]'
        OR NOT pg_input_is_valid(cell.value->>'x','numeric') OR NOT (cell.value->>'x')::numeric BETWEEN 0 AND 1
        OR NOT pg_input_is_valid(cell.value->>'y','numeric') OR NOT (cell.value->>'y')::numeric BETWEEN 0 AND 1
        OR NOT pg_input_is_valid(cell.value->>'width','numeric') OR NOT (cell.value->>'width')::numeric > 0 OR NOT (cell.value->>'width')::numeric <= 1
        OR NOT pg_input_is_valid(cell.value->>'height','numeric') OR NOT (cell.value->>'height')::numeric > 0 OR NOT (cell.value->>'height')::numeric <= 1
        OR (cell.value->>'x')::numeric + (cell.value->>'width')::numeric > 1
        OR (cell.value->>'y')::numeric + (cell.value->>'height')::numeric > 1
    )
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_cells) WITH ORDINALITY AS first_cell(value, ordinal)
      JOIN jsonb_array_elements(p_cells) WITH ORDINALITY AS second_cell(value, ordinal)
        ON first_cell.ordinal < second_cell.ordinal
      WHERE first_cell.value->>'table_index' = second_cell.value->>'table_index'
        AND first_cell.value->>'row_index' = second_cell.value->>'row_index'
        AND first_cell.value->>'column_index' = second_cell.value->>'column_index'
    )
  )
$$;

CREATE FUNCTION public.jsonb_object_has_exact_keys(p_value jsonb, p_keys text[])
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $$
  SELECT jsonb_typeof(p_value) = 'object'
    AND (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_value) key)
      IS NOT DISTINCT FROM (SELECT array_agg(key ORDER BY key) FROM unnest(p_keys) key)
$$;

-- Keep service-side source verification equivalent to source-verifier.ts:
-- syntax-only normalization for text/code, supported Indian date formats,
-- and formatted decimal matching without accepting a different source value.
CREATE FUNCTION public.source_field_candidate_normalized_source_text(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path = pg_catalog, public AS $$
  SELECT upper(regexp_replace(p_value, '[[:space:]./,_-]', '', 'g'))
$$;

CREATE FUNCTION public.source_field_candidate_source_date(p_value text)
RETURNS date LANGUAGE plpgsql IMMUTABLE STRICT SET search_path = pg_catalog, public AS $$
DECLARE match text[]; month_number integer;
BEGIN
  match := regexp_match(btrim(p_value), '^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
  IF match IS NOT NULL THEN RETURN make_date(match[1]::integer, match[2]::integer, match[3]::integer); END IF;
  match := regexp_match(btrim(p_value), '^([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{4})$');
  IF match IS NOT NULL THEN RETURN make_date(match[3]::integer, match[2]::integer, match[1]::integer); END IF;
  match := regexp_match(btrim(p_value), '^([0-9]{1,2})(st|nd|rd|th)?[[:space:]]+([A-Za-z]+)[.]?[,]?[[:space:]]+([0-9]{4})$', 'i');
  IF match IS NOT NULL THEN
    month_number := CASE lower(match[3])
      WHEN 'january' THEN 1 WHEN 'jan' THEN 1 WHEN 'february' THEN 2 WHEN 'feb' THEN 2
      WHEN 'march' THEN 3 WHEN 'mar' THEN 3 WHEN 'april' THEN 4 WHEN 'apr' THEN 4
      WHEN 'may' THEN 5 WHEN 'june' THEN 6 WHEN 'jun' THEN 6 WHEN 'july' THEN 7 WHEN 'jul' THEN 7
      WHEN 'august' THEN 8 WHEN 'aug' THEN 8 WHEN 'september' THEN 9 WHEN 'sep' THEN 9 WHEN 'sept' THEN 9
      WHEN 'october' THEN 10 WHEN 'oct' THEN 10 WHEN 'november' THEN 11 WHEN 'nov' THEN 11
      WHEN 'december' THEN 12 WHEN 'dec' THEN 12 ELSE 0 END;
    RETURN make_date(match[4]::integer, month_number, match[1]::integer);
  END IF;
  match := regexp_match(btrim(p_value), '^([A-Za-z]+)[.]?[[:space:]]+([0-9]{1,2})(st|nd|rd|th)?[,]?[[:space:]]+([0-9]{4})$', 'i');
  IF match IS NOT NULL THEN
    month_number := CASE lower(match[1])
      WHEN 'january' THEN 1 WHEN 'jan' THEN 1 WHEN 'february' THEN 2 WHEN 'feb' THEN 2
      WHEN 'march' THEN 3 WHEN 'mar' THEN 3 WHEN 'april' THEN 4 WHEN 'apr' THEN 4
      WHEN 'may' THEN 5 WHEN 'june' THEN 6 WHEN 'jun' THEN 6 WHEN 'july' THEN 7 WHEN 'jul' THEN 7
      WHEN 'august' THEN 8 WHEN 'aug' THEN 8 WHEN 'september' THEN 9 WHEN 'sep' THEN 9 WHEN 'sept' THEN 9
      WHEN 'october' THEN 10 WHEN 'oct' THEN 10 WHEN 'november' THEN 11 WHEN 'nov' THEN 11
      WHEN 'december' THEN 12 WHEN 'dec' THEN 12 ELSE 0 END;
    RETURN make_date(match[4]::integer, month_number, match[2]::integer);
  END IF;
  RETURN NULL;
EXCEPTION WHEN datetime_field_overflow THEN
  RETURN NULL;
END $$;

CREATE FUNCTION public.source_field_candidate_value_resolves_in_text(
  p_value_type public.source_field_candidate_value_type, p_normalized_value jsonb, p_source_text text
) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE candidate text; target_date date; source_value text;
BEGIN
  IF jsonb_typeof(p_normalized_value) <> 'string' OR p_source_text IS NULL THEN RETURN false; END IF;
  candidate := p_normalized_value #>> '{}';
  IF p_value_type = 'date'::public.source_field_candidate_value_type THEN
    target_date := public.source_field_candidate_source_date(candidate);
    IF target_date IS NULL THEN RETURN false; END IF;
    FOR source_value IN
      SELECT match[1] FROM regexp_matches(p_source_text,
        '([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}[./-][0-9]{1,2}[./-][0-9]{4}|[0-9]{1,2}(st|nd|rd|th)?[[:space:]]+[A-Za-z]+[.]?[,]?[[:space:]]+[0-9]{4}|[A-Za-z]+[.]?[[:space:]]+[0-9]{1,2}(st|nd|rd|th)?[,]?[[:space:]]+[0-9]{4})', 'gi') AS match
    LOOP
      IF public.source_field_candidate_source_date(source_value) = target_date THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
  ELSIF p_value_type = 'decimal'::public.source_field_candidate_value_type
     OR p_value_type = 'integer'::public.source_field_candidate_value_type THEN
    FOR source_value IN
      SELECT match[2] FROM regexp_matches(p_source_text,
        '(^|[^[:alnum:]])(-?[0-9][0-9,[:space:]]*([.][0-9]+)?)([^[:alnum:]]|$)', 'g') AS match
    LOOP
      IF regexp_replace(regexp_replace(source_value, '[₹,[:space:]]', '', 'g'), '^INR', '', 'i') = candidate THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
  ELSIF p_value_type IN ('text'::public.source_field_candidate_value_type, 'code'::public.source_field_candidate_value_type) THEN
    RETURN position(public.source_field_candidate_normalized_source_text(candidate) IN public.source_field_candidate_normalized_source_text(p_source_text)) > 0;
  ELSIF p_value_type = 'boolean'::public.source_field_candidate_value_type THEN
    RETURN position(upper(candidate) IN upper(p_source_text)) > 0;
  END IF;
  RETURN false;
END $$;

ALTER TABLE public.document_page_text_pages
  ADD COLUMN table_cells jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (public.document_page_text_table_cells_are_safe(table_cells));

ALTER TABLE public.source_field_candidates
  DROP CONSTRAINT source_field_candidates_verified_source_anchor_valid,
  ADD CONSTRAINT source_field_candidates_verified_source_anchor_valid CHECK (
    verified_source_anchor IS NULL OR (
      jsonb_typeof(verified_source_anchor) = 'object'
      AND (public.jsonb_object_has_exact_keys(verified_source_anchor, ARRAY['char_end','char_start','token_end','token_start'])
        OR public.jsonb_object_has_exact_keys(verified_source_anchor, ARRAY['char_end','char_start','table_cell','token_end','token_start']))
      AND (verified_source_anchor->>'char_start') ~ '^[0-9]{1,8}$'
      AND (verified_source_anchor->>'char_end') ~ '^[1-9][0-9]{0,8}$'
      AND (verified_source_anchor->>'char_end')::integer > (verified_source_anchor->>'char_start')::integer
      AND (verified_source_anchor->'token_start' = 'null'::jsonb OR (verified_source_anchor->>'token_start') ~ '^[0-9]{1,8}$')
      AND (verified_source_anchor->'token_end' = 'null'::jsonb OR (verified_source_anchor->>'token_end') ~ '^[0-9]{1,8}$')
      AND ((verified_source_anchor->'token_start' = 'null'::jsonb AND verified_source_anchor->'token_end' = 'null'::jsonb)
        OR ((verified_source_anchor->>'token_start')::integer <= (verified_source_anchor->>'token_end')::integer))
      AND (NOT verified_source_anchor ? 'table_cell' OR verified_source_anchor->'table_cell' = 'null'::jsonb OR (
        jsonb_typeof(verified_source_anchor->'table_cell') = 'object'
        AND public.jsonb_object_has_exact_keys(verified_source_anchor->'table_cell', ARRAY['column_index','row_index','table_index'])
        AND (verified_source_anchor #>> '{table_cell,table_index}') ~ '^[0-9]{1,2}$'
        AND (verified_source_anchor #>> '{table_cell,row_index}') ~ '^[0-9]{1,3}$'
        AND (verified_source_anchor #>> '{table_cell,column_index}') ~ '^[0-9]{1,3}$'
      ))
    )
  );

CREATE OR REPLACE FUNCTION public.write_current_document_page_text_artifact(
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
      AND value ? 'acquisition_method' AND value ? 'quality_policy_version' AND value ? 'quality_reasons'
      AND value ? 'detected_languages' AND value ? 'ocr_processor_identifier' AND value ? 'ocr_processor_version'
      AND value->>'page_number' IN (SELECT page_number::text FROM generate_series(1, expected_pages) page_number)
      AND jsonb_typeof(value->'text')='string' AND char_length(value->>'text') BETWEEN 1 AND 8000
      AND value->>'text' !~ E'[\\x00-\\x1F\\x7F]'
      AND value->>'acquisition_method' IN ('native_pdf','document_ai_ocr')
      AND value->>'quality_policy_version' ~ '^[a-z][a-z0-9_-]{1,99}$'
      AND jsonb_typeof(value->'quality_reasons') = 'array' AND jsonb_typeof(value->'detected_languages') = 'array'
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(value->'quality_reasons') reason WHERE reason !~ '^[a-z][a-z0-9_]{1,99}$')
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(value->'detected_languages') language WHERE language !~ '^[A-Za-z0-9-]{1,35}$')
      AND (NOT value ? 'ocr_words' OR public.document_page_text_ocr_words_are_safe(value->'ocr_words'))
      AND (NOT value ? 'table_cells' OR public.document_page_text_table_cells_are_safe(value->'table_cells'))
      AND ((value->>'acquisition_method' = 'native_pdf' AND value->'ocr_processor_identifier' = 'null'::jsonb AND value->'ocr_processor_version' = 'null'::jsonb)
        OR (value->>'acquisition_method' = 'document_ai_ocr' AND value->>'ocr_processor_identifier' ~ '^[A-Za-z0-9._:-]{1,200}$'
          AND (value->'ocr_processor_version' = 'null'::jsonb OR value->>'ocr_processor_version' ~ '^[A-Za-z0-9._:-]{1,200}$')))
    ) INTO pages_valid FROM jsonb_array_elements(p_pages) AS input(value);
  IF pages_valid IS DISTINCT FROM true THEN
    INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,safe_error_code)
    VALUES(run_row.org_id,run_row.document_id,version_row.id,run_row.id,source_row.id,'not_indexable',expected_pages,'page_text_unavailable')
    ON CONFLICT (org_id,document_id,document_version_id) DO UPDATE SET processing_run_id=EXCLUDED.processing_run_id, source_analysis_run_id=EXCLUDED.source_analysis_run_id,state='not_indexable',content_fingerprint=NULL,safe_error_code='page_text_unavailable',updated_at=now() RETURNING id INTO v_artifact_id;
    DELETE FROM public.document_page_text_pages WHERE artifact_id = v_artifact_id;
    DELETE FROM public.search_document_chunks WHERE org_id=run_row.org_id AND document_id=run_row.document_id AND document_version_id=version_row.id;
    INSERT INTO public.search_document_chunk_runs(org_id,document_id,document_version_id,artifact_id,processing_run_id,state,changed_chunk_count,safe_error_code)
    VALUES(run_row.org_id,run_row.document_id,version_row.id,NULL,run_row.id,'not_indexable',0,'page_text_unavailable')
    ON CONFLICT (processing_run_id) DO UPDATE SET state='not_indexable',artifact_id=NULL,changed_chunk_count=0,safe_error_code='page_text_unavailable',updated_at=now();
    RETURN QUERY SELECT 'not_indexable'::text; RETURN;
  END IF;
  SELECT encode(extensions.digest(convert_to(string_agg(value->>'text','' ORDER BY (value->>'page_number')::integer),'utf8'),'sha256'),'hex') INTO artifact_hash FROM jsonb_array_elements(p_pages) AS input(value);
  INSERT INTO public.document_page_text_artifacts(org_id,document_id,document_version_id,processing_run_id,source_analysis_run_id,state,page_count,content_fingerprint)
  VALUES(run_row.org_id,run_row.document_id,version_row.id,run_row.id,source_row.id,'ready',expected_pages,artifact_hash)
  ON CONFLICT (org_id,document_id,document_version_id) DO UPDATE SET processing_run_id=EXCLUDED.processing_run_id,source_analysis_run_id=EXCLUDED.source_analysis_run_id,state='ready',page_count=EXCLUDED.page_count,content_fingerprint=EXCLUDED.content_fingerprint,safe_error_code=NULL,updated_at=now() RETURNING id INTO v_artifact_id;
  DELETE FROM public.document_page_text_pages WHERE artifact_id = v_artifact_id;
  INSERT INTO public.document_page_text_pages(org_id,artifact_id,page_number,page_text,ocr_words,table_cells,page_content_hash,acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version)
  SELECT run_row.org_id,v_artifact_id,(value->>'page_number')::integer,value->>'text',CASE WHEN value ? 'ocr_words' THEN value->'ocr_words' ELSE NULL END,CASE WHEN value ? 'table_cells' THEN value->'table_cells' ELSE '[]'::jsonb END,encode(extensions.digest(convert_to(value->>'text','utf8'),'sha256'),'hex'),value->>'acquisition_method',value->>'quality_policy_version',ARRAY(SELECT jsonb_array_elements_text(value->'quality_reasons')),ARRAY(SELECT jsonb_array_elements_text(value->'detected_languages')),NULLIF(value->>'ocr_processor_identifier',''),NULLIF(value->>'ocr_processor_version','')
  FROM jsonb_array_elements(p_pages) AS input(value);
  RETURN QUERY SELECT 'written'::text;
END $$;

CREATE OR REPLACE FUNCTION public.materialize_verified_source_field_candidate(
  p_source_analysis_run_id uuid, p_semantic_candidate_key text, p_field_path text,
  p_value_type public.source_field_candidate_value_type, p_normalized_value jsonb,
  p_page_number integer, p_quotation text, p_evidence_regions jsonb, p_confidence numeric,
  p_validation_state public.source_field_candidate_validation_state, p_validation_error_codes text[],
  p_verified_source_anchor jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE run_row public.source_analysis_runs%ROWTYPE; existing_row public.source_field_candidates%ROWTYPE;
DECLARE page_text text; words jsonb; table_cells jsonb; candidate_id uuid; canonical_confidence numeric(4,3);
DECLARE start_offset integer; end_offset integer; token_start integer; token_end integer; critical boolean;
DECLARE cursor_offset integer := 0; token_index integer; word_text text; word_start integer; word_end integer; found_at integer;
DECLARE expected_token_start integer := NULL; expected_token_end integer := NULL; selected_count integer := 0; expected_regions jsonb := '[]'::jsonb;
DECLARE expected_cell jsonb; anchor_table_index integer; anchor_row_index integer; anchor_column_index integer; matching_cell_count integer;
BEGIN
  IF p_source_analysis_run_id IS NULL OR p_confidence IS NULL OR p_confidence < 0 OR p_confidence > 1 THEN RAISE EXCEPTION 'verified candidate materialization request is incomplete'; END IF;
  critical := p_field_path IN ('document.gstin','document.date','deadline.due_date','document.client_identifier','document.reference_number','document.referenced_document_number','document.matter_assignment_key','document.client_assignment_key') OR p_field_path LIKE 'financial.%';
  IF critical AND p_validation_state='eligible'::public.source_field_candidate_validation_state AND p_verified_source_anchor IS NULL THEN RAISE EXCEPTION 'critical eligible candidates require a verified source anchor'; END IF;
  canonical_confidence := round(p_confidence,3)::numeric(4,3);
  SELECT * INTO run_row FROM public.source_analysis_runs WHERE id=p_source_analysis_run_id FOR UPDATE;
  IF run_row.id IS NULL OR run_row.analysis_kind <> 'ai_extraction'::public.source_analysis_kind OR run_row.analysis_state <> 'validated'::public.source_analysis_provenance_state THEN RAISE EXCEPTION 'verified candidates require a validated AI extraction run'; END IF;
  IF p_verified_source_anchor IS NULL THEN
    IF p_evidence_regions IS NOT NULL THEN RAISE EXCEPTION 'evidence regions require a verified source anchor'; END IF;
  ELSIF jsonb_typeof(p_verified_source_anchor)<>'object' OR (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(p_verified_source_anchor) key) IS DISTINCT FROM ARRAY['char_end','char_start','table_cell','token_end','token_start']::text[] THEN
    RAISE EXCEPTION 'verified source anchor is malformed';
  END IF;
  IF p_verified_source_anchor IS NOT NULL THEN
    start_offset := (p_verified_source_anchor->>'char_start')::integer; end_offset := (p_verified_source_anchor->>'char_end')::integer;
    IF end_offset <= start_offset THEN RAISE EXCEPTION 'verified source anchor is empty'; END IF;
    SELECT page.page_text,coalesce(page.ocr_words,'[]'::jsonb),page.table_cells INTO page_text,words,table_cells
    FROM public.document_page_text_artifacts artifact JOIN public.document_page_text_pages page ON page.artifact_id=artifact.id AND page.org_id=artifact.org_id
    JOIN public.documents document_row ON document_row.id=artifact.document_id AND document_row.org_id=artifact.org_id
    WHERE artifact.org_id=run_row.org_id AND artifact.source_analysis_run_id=run_row.id AND artifact.state='ready'
      AND artifact.document_version_id=document_row.current_version_id AND document_row.record_state='active'::public.document_record_state AND document_row.deleted_at IS NULL
      AND page.page_number=p_page_number AND public.document_page_text_artifact_has_approved_acquisition(artifact.id,artifact.page_count) FOR KEY SHARE;
    IF page_text IS NULL OR end_offset > char_length(page_text) OR substring(page_text FROM start_offset+1 FOR end_offset-start_offset) IS DISTINCT FROM p_quotation THEN RAISE EXCEPTION 'verified source anchor does not resolve to the canonical page quote'; END IF;
    IF NOT public.source_field_candidate_value_resolves_in_text(p_value_type,p_normalized_value,p_quotation) THEN RAISE EXCEPTION 'verified source anchor quote does not semantically resolve the normalized candidate value'; END IF;
    IF p_verified_source_anchor->'table_cell' <> 'null'::jsonb THEN
      IF p_verified_source_anchor->'token_start' <> 'null'::jsonb OR p_verified_source_anchor->'token_end' <> 'null'::jsonb THEN RAISE EXCEPTION 'table-cell source anchors cannot also claim token anchors'; END IF;
      anchor_table_index := (p_verified_source_anchor #>> '{table_cell,table_index}')::integer; anchor_row_index := (p_verified_source_anchor #>> '{table_cell,row_index}')::integer; anchor_column_index := (p_verified_source_anchor #>> '{table_cell,column_index}')::integer;
      SELECT count(*) INTO matching_cell_count FROM jsonb_array_elements(table_cells) cell(value)
      WHERE (cell.value->>'table_index')::integer=anchor_table_index AND (cell.value->>'row_index')::integer=anchor_row_index AND (cell.value->>'column_index')::integer=anchor_column_index;
      IF matching_cell_count <> 1 THEN RAISE EXCEPTION 'verified table-cell anchor resolves to no or duplicate canonical cells'; END IF;
      SELECT cell.value INTO expected_cell FROM jsonb_array_elements(table_cells) cell(value)
      WHERE (cell.value->>'table_index')::integer=anchor_table_index AND (cell.value->>'row_index')::integer=anchor_row_index AND (cell.value->>'column_index')::integer=anchor_column_index;
      IF expected_cell IS NULL
        OR position(p_quotation IN (expected_cell->>'text')) = 0
        OR NOT public.source_field_candidate_value_resolves_in_text(p_value_type,p_normalized_value,expected_cell->>'text')
        OR p_evidence_regions IS DISTINCT FROM jsonb_build_array(jsonb_build_object('x',expected_cell->'x','y',expected_cell->'y','width',expected_cell->'width','height',expected_cell->'height'))
      THEN RAISE EXCEPTION 'verified table-cell anchor does not resolve to canonical cell text and geometry'; END IF;
    ELSIF p_verified_source_anchor->'token_start' <> 'null'::jsonb OR p_verified_source_anchor->'token_end' <> 'null'::jsonb THEN
      IF p_verified_source_anchor->'token_start'='null'::jsonb OR p_verified_source_anchor->'token_end'='null'::jsonb THEN RAISE EXCEPTION 'verified source anchor token range is incomplete'; END IF;
      token_start := (p_verified_source_anchor->>'token_start')::integer; token_end := (p_verified_source_anchor->>'token_end')::integer;
      FOR token_index IN 0..coalesce(jsonb_array_length(words),0)-1 LOOP
        word_text := words->token_index->>'text'; found_at := strpos(substring(page_text FROM cursor_offset+1),word_text);
        IF found_at > 0 THEN
          word_start := cursor_offset+found_at-1; word_end := word_start+char_length(word_text); cursor_offset := word_end;
          IF word_start < end_offset AND word_end > start_offset THEN
            IF expected_token_start IS NULL THEN expected_token_start := token_index; END IF;
            expected_token_end := token_index;
            IF selected_count < 16 THEN expected_regions := expected_regions || jsonb_build_array(jsonb_build_object('x',words->token_index->'x','y',words->token_index->'y','width',words->token_index->'width','height',words->token_index->'height')); END IF;
            selected_count := selected_count+1;
          END IF;
        END IF;
      END LOOP;
      IF expected_token_start IS NULL OR token_start IS DISTINCT FROM expected_token_start OR token_end IS DISTINCT FROM expected_token_end OR p_evidence_regions IS DISTINCT FROM expected_regions THEN RAISE EXCEPTION 'verified source anchor token/region evidence is not canonical'; END IF;
    ELSIF p_evidence_regions IS NOT NULL THEN RAISE EXCEPTION 'evidence regions require canonical token or table-cell anchors'; END IF;
  END IF;
  SELECT * INTO existing_row FROM public.source_field_candidates WHERE source_analysis_run_id=p_source_analysis_run_id AND semantic_candidate_key=p_semantic_candidate_key FOR KEY SHARE;
  IF existing_row.id IS NOT NULL THEN
    IF existing_row.field_path IS DISTINCT FROM p_field_path OR existing_row.value_type IS DISTINCT FROM p_value_type OR existing_row.normalized_value IS DISTINCT FROM p_normalized_value OR existing_row.asset_id IS DISTINCT FROM run_row.asset_id OR existing_row.page_number IS DISTINCT FROM p_page_number OR existing_row.quotation IS DISTINCT FROM p_quotation OR existing_row.evidence_regions IS DISTINCT FROM p_evidence_regions OR existing_row.verified_source_anchor IS DISTINCT FROM p_verified_source_anchor OR existing_row.confidence IS DISTINCT FROM canonical_confidence OR existing_row.validation_state IS DISTINCT FROM p_validation_state OR existing_row.validation_error_codes IS DISTINCT FROM p_validation_error_codes THEN RAISE EXCEPTION 'source field candidate semantic key conflicts with existing materialization'; END IF;
    RETURN existing_row.id;
  END IF;
  INSERT INTO public.source_field_candidates(org_id,source_analysis_run_id,asset_id,semantic_candidate_key,field_path,value_type,normalized_value,page_number,quotation,evidence_regions,verified_source_anchor,confidence,validation_state,validation_error_codes)
  VALUES(run_row.org_id,run_row.id,run_row.asset_id,p_semantic_candidate_key,p_field_path,p_value_type,p_normalized_value,p_page_number,p_quotation,p_evidence_regions,p_verified_source_anchor,canonical_confidence,p_validation_state,p_validation_error_codes) RETURNING id INTO candidate_id;
  RETURN candidate_id;
END $$;

REVOKE ALL ON FUNCTION public.document_page_text_table_cells_are_safe(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.jsonb_object_has_exact_keys(jsonb,text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_normalized_source_text(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_source_date(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_value_resolves_in_text(public.source_field_candidate_value_type,jsonb,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.materialize_verified_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[],jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_verified_source_field_candidate(uuid,text,text,public.source_field_candidate_value_type,jsonb,integer,text,jsonb,numeric,public.source_field_candidate_validation_state,text[],jsonb) TO service_role;

COMMENT ON COLUMN public.document_page_text_pages.table_cells IS 'Bounded Document AI table cells with structural coordinates, reading order, and canonical boxes; omitted cells are not evidence.';
COMMENT ON COLUMN public.source_field_candidates.verified_source_anchor IS 'Exact canonical acquired-page character/token or table-cell locator and derived geometry, validated by the service-only completion transaction.';

COMMIT;
