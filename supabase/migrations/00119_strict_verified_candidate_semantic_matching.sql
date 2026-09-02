-- Keep the database materializer aligned with source-verifier.ts. In
-- particular, a value must resolve exactly once in the canonical page and
-- quote; formatting tolerance must never turn a prefix or a repeat into a
-- valid source fact.
BEGIN;

CREATE OR REPLACE FUNCTION public.source_field_candidate_normalized_source_text(p_value text)
RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path = pg_catalog, public AS $$
  SELECT upper(regexp_replace(btrim(p_value), '[[:space:]./,_-]', '', 'g'))
$$;

CREATE FUNCTION public.source_field_candidate_value_match_count(
  p_value_type public.source_field_candidate_value_type,
  p_normalized_value jsonb,
  p_source_text text
) RETURNS integer
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE
  candidate text; target text; target_date date; source_value text;
  pattern text := ''; character text; position_index integer;
  source_length integer; source_start integer; source_end integer;
  matched text[]; match_text text; before_char text; before_before_char text;
  after_char text; after_after_char text; match_count integer := 0;
BEGIN
  IF jsonb_typeof(p_normalized_value) <> 'string' OR p_source_text IS NULL THEN
    RETURN 0;
  END IF;
  candidate := p_normalized_value #>> '{}';

  IF p_value_type = 'date'::public.source_field_candidate_value_type THEN
    target_date := public.source_field_candidate_source_date(candidate);
    IF target_date IS NULL THEN RETURN 0; END IF;
    FOR source_value IN
      SELECT match[1]
      FROM regexp_matches(p_source_text,
        '([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}[./-][0-9]{1,2}[./-][0-9]{4}|[0-9]{1,2}(st|nd|rd|th)?[[:space:]]+[A-Za-z]+[.]?[,]?[[:space:]]+[0-9]{4}|[A-Za-z]+[.]?[[:space:]]+[0-9]{1,2}(st|nd|rd|th)?[,]?[[:space:]]+[0-9]{4})',
        'gi') AS match
    LOOP
      IF public.source_field_candidate_source_date(source_value) = target_date THEN
        match_count := match_count + 1;
      END IF;
    END LOOP;
    RETURN match_count;
  END IF;

  IF p_value_type IN ('decimal'::public.source_field_candidate_value_type, 'integer'::public.source_field_candidate_value_type) THEN
    target := regexp_replace(regexp_replace(btrim(candidate), '[₹,[:space:]]', '', 'g'), '^INR', '', 'i');
  ELSIF p_value_type IN ('text'::public.source_field_candidate_value_type, 'code'::public.source_field_candidate_value_type) THEN
    target := public.source_field_candidate_normalized_source_text(candidate);
  ELSE
    RETURN 0;
  END IF;
  IF target = '' THEN RETURN 0; END IF;

  FOR position_index IN 1..char_length(candidate) LOOP
    character := substring(candidate FROM position_index FOR 1);
    IF character !~ '[[:space:]./,_-]' AND character <> '₹' THEN
      IF pattern <> '' THEN pattern := pattern || '[[:space:]./,_-]*'; END IF;
      IF character ~ '[[:alnum:]]' THEN
        pattern := pattern || character;
      ELSIF position(character IN '.^$|()[]{}*+?') > 0 OR ascii(character) = 92 THEN
        pattern := pattern || chr(92) || character;
      ELSE
        pattern := pattern || character;
      END IF;
    END IF;
  END LOOP;
  IF pattern = '' THEN RETURN 0; END IF;

  source_length := char_length(p_source_text);
  FOR source_start IN 1..source_length LOOP
    before_char := CASE WHEN source_start = 1 THEN NULL ELSE substring(p_source_text FROM source_start - 1 FOR 1) END;
    before_before_char := CASE WHEN source_start <= 2 THEN NULL ELSE substring(p_source_text FROM source_start - 2 FOR 1) END;
    IF p_value_type IN ('decimal'::public.source_field_candidate_value_type, 'integer'::public.source_field_candidate_value_type) THEN
      IF before_char IS NOT NULL AND (before_char ~ '[[:alnum:],]' OR (before_char = '.' AND before_before_char ~ '[0-9]')) THEN CONTINUE; END IF;
    ELSIF before_char IS NOT NULL AND before_char ~ '[[:alnum:]]' THEN
      CONTINUE;
    END IF;

    matched := regexp_match(substring(p_source_text FROM source_start), '^(' || pattern || ')', 'i');
    IF matched IS NULL THEN CONTINUE; END IF;
    match_text := matched[1];
    source_end := source_start + char_length(match_text);
    after_char := CASE WHEN source_end > source_length THEN NULL ELSE substring(p_source_text FROM source_end FOR 1) END;
    after_after_char := CASE WHEN source_end >= source_length THEN NULL ELSE substring(p_source_text FROM source_end + 1 FOR 1) END;
    IF p_value_type IN ('decimal'::public.source_field_candidate_value_type, 'integer'::public.source_field_candidate_value_type) THEN
      IF after_char IS NOT NULL AND (after_char ~ '[[:alnum:],]' OR (after_char = '.' AND after_after_char ~ '[0-9]')) THEN CONTINUE; END IF;
      IF regexp_replace(regexp_replace(match_text, '[₹,[:space:]]', '', 'g'), '^INR', '', 'i') <> target THEN CONTINUE; END IF;
    ELSE
      IF after_char IS NOT NULL AND after_char ~ '[[:alnum:]]' THEN CONTINUE; END IF;
      IF public.source_field_candidate_normalized_source_text(match_text) <> target THEN CONTINUE; END IF;
    END IF;
    match_count := match_count + 1;
  END LOOP;
  RETURN match_count;
END $$;

CREATE OR REPLACE FUNCTION public.source_field_candidate_value_resolves_in_text(
  p_value_type public.source_field_candidate_value_type, p_normalized_value jsonb, p_source_text text
) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE candidate text;
BEGIN
  IF jsonb_typeof(p_normalized_value) <> 'string' OR p_source_text IS NULL THEN RETURN false; END IF;
  IF p_value_type = 'boolean'::public.source_field_candidate_value_type THEN
    candidate := p_normalized_value #>> '{}';
    RETURN position(upper(candidate) IN upper(p_source_text)) > 0;
  END IF;
  RETURN public.source_field_candidate_value_match_count(p_value_type, p_normalized_value, p_source_text) = 1;
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
    IF public.source_field_candidate_value_match_count(p_value_type,p_normalized_value,p_quotation) <> 1
       OR public.source_field_candidate_value_match_count(p_value_type,p_normalized_value,page_text) <> 1 THEN
      RAISE EXCEPTION 'verified source anchor does not resolve one exact normalized candidate value';
    END IF;
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
        OR public.source_field_candidate_value_match_count(p_value_type,p_normalized_value,expected_cell->>'text') <> 1
        OR p_evidence_regions IS DISTINCT FROM jsonb_build_array(jsonb_build_object('x',expected_cell->'x','y',expected_cell->'y','width',expected_cell->'width','height',expected_cell->'height'))
      THEN RAISE EXCEPTION 'verified table-cell anchor does not resolve one exact normalized candidate value and canonical geometry'; END IF;
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

REVOKE ALL ON FUNCTION public.source_field_candidate_value_match_count(public.source_field_candidate_value_type,jsonb,text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_normalized_source_text(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_source_date(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_value_resolves_in_text(public.source_field_candidate_value_type,jsonb,text) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.source_field_candidate_value_match_count(public.source_field_candidate_value_type,jsonb,text) IS
  'Service-only exact source matching equivalent to source-verifier.ts: supported dates, formatted decimal values, and word-bounded text/code values each resolve exactly once.';

COMMIT;
