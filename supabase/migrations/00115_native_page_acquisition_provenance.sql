-- Per-page acquisition provenance for the existing private page artifact.
-- The service-only writer and all existing current-version/lease fences remain
-- in 00113; this migration records only the native/OCR source evidence.
BEGIN;

ALTER TABLE public.document_page_text_pages
  ADD COLUMN acquisition_method text NOT NULL DEFAULT 'legacy'
    CHECK (acquisition_method IN ('legacy', 'native_pdf', 'document_ai_ocr')),
  ADD COLUMN quality_policy_version text,
  ADD COLUMN quality_reasons text[] NOT NULL DEFAULT '{}'::text[],
  ADD COLUMN detected_languages text[] NOT NULL DEFAULT '{}'::text[],
  ADD COLUMN ocr_processor_identifier text,
  ADD COLUMN ocr_processor_version text;

ALTER TABLE public.document_page_text_pages
  ADD CONSTRAINT document_page_text_pages_acquisition_evidence_shape CHECK (
    (acquisition_method = 'legacy'
      AND quality_policy_version IS NULL
      AND cardinality(quality_reasons) = 0
      AND cardinality(detected_languages) = 0
      AND ocr_processor_identifier IS NULL
      AND ocr_processor_version IS NULL)
    OR (acquisition_method = 'native_pdf'
      AND quality_policy_version ~ '^[a-z][a-z0-9_-]{1,99}$'
      AND ocr_processor_identifier IS NULL
      AND ocr_processor_version IS NULL)
    OR (acquisition_method = 'document_ai_ocr'
      AND quality_policy_version ~ '^[a-z][a-z0-9_-]{1,99}$'
      AND ocr_processor_identifier ~ '^[A-Za-z0-9._:-]{1,200}$'
      AND (ocr_processor_version IS NULL OR ocr_processor_version ~ '^[A-Za-z0-9._:-]{1,200}$'))
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
      AND jsonb_typeof(value->'quality_reasons') = 'array'
      AND jsonb_typeof(value->'detected_languages') = 'array'
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(value->'quality_reasons') reason WHERE reason !~ '^[a-z][a-z0-9_]{1,99}$')
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(value->'detected_languages') language WHERE language !~ '^[A-Za-z0-9-]{1,35}$')
      AND (NOT value ? 'ocr_words' OR public.document_page_text_ocr_words_are_safe(value->'ocr_words'))
      AND ((value->>'acquisition_method' = 'native_pdf'
        AND value->'ocr_processor_identifier' = 'null'::jsonb AND value->'ocr_processor_version' = 'null'::jsonb)
        OR (value->>'acquisition_method' = 'document_ai_ocr'
          AND value->>'ocr_processor_identifier' ~ '^[A-Za-z0-9._:-]{1,200}$'
          AND (value->'ocr_processor_version' = 'null'::jsonb OR value->>'ocr_processor_version' ~ '^[A-Za-z0-9._:-]{1,200}$')))
    ) INTO pages_valid FROM jsonb_array_elements(p_pages) AS input(value);
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
  INSERT INTO public.document_page_text_pages(
    org_id,artifact_id,page_number,page_text,ocr_words,page_content_hash,
    acquisition_method,quality_policy_version,quality_reasons,detected_languages,ocr_processor_identifier,ocr_processor_version
  ) SELECT run_row.org_id,v_artifact_id,(value->>'page_number')::integer,value->>'text',
    CASE WHEN value ? 'ocr_words' THEN value->'ocr_words' ELSE NULL END,
    encode(extensions.digest(convert_to(value->>'text','utf8'),'sha256'),'hex'),
    value->>'acquisition_method',value->>'quality_policy_version',
    ARRAY(SELECT jsonb_array_elements_text(value->'quality_reasons')),
    ARRAY(SELECT jsonb_array_elements_text(value->'detected_languages')),
    NULLIF(value->>'ocr_processor_identifier',''),NULLIF(value->>'ocr_processor_version','')
  FROM jsonb_array_elements(p_pages) AS input(value);
  RETURN QUERY SELECT 'written'::text;
END $$;

COMMIT;
