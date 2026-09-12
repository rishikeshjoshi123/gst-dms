-- D09-T03: typed tax-period and official-reference source observations.
-- These immutable candidates deliberately create no identity, relationship,
-- placement, notification, or effective procedural effect.
BEGIN;
ALTER TYPE public.source_field_candidate_value_type ADD VALUE IF NOT EXISTS 'structured';

COMMIT;
BEGIN;

CREATE FUNCTION public.typed_extraction_string_array_is_valid(p_value jsonb, p_pattern text, p_max integer)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE item jsonb;
BEGIN
  IF jsonb_typeof(p_value) <> 'array' OR jsonb_array_length(p_value) > p_max THEN RETURN false; END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(p_value) LOOP
    IF jsonb_typeof(item) <> 'string' OR (item #>> '{}') !~ p_pattern THEN RETURN false; END IF;
  END LOOP;
  RETURN (SELECT count(*) = count(DISTINCT value) FROM jsonb_array_elements_text(p_value));
END $$;

CREATE FUNCTION public.typed_financial_year_is_valid(p_value text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog AS $$
BEGIN
  IF p_value IS NULL OR p_value !~ '^[0-9]{4}-[0-9]{2}$' THEN RETURN false; END IF;
  RETURN substring(p_value,6,2)::integer = (substring(p_value,1,4)::integer + 1) % 100;
END
$$;

CREATE FUNCTION public.typed_tax_period_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE
  segment jsonb; segment_count integer; kind text; segment_kind text; derived text[] := ARRAY[]::text[];
  printed text[]; supplied_derived text[]; supplied_financial_years text[]; canonical_printed text[]; canonical_derived text[];
  derived_year text; first_year integer; last_year integer; expected_conflict boolean;
BEGIN
  IF jsonb_typeof(p_value) <> 'object' OR NOT public.jsonb_object_has_exact_keys(p_value,
    ARRAY['catalogue_version','conflict','derived_financial_years','display','financial_years','kind','normalizer_version','precision','printed_financial_years','raw','segments']) THEN RETURN false;
  END IF;
  IF jsonb_typeof(p_value->'kind')<>'string' OR jsonb_typeof(p_value->'precision')<>'string'
    OR jsonb_typeof(p_value->'raw')<>'string' OR jsonb_typeof(p_value->'display')<>'string'
    OR jsonb_typeof(p_value->'catalogue_version')<>'string' OR jsonb_typeof(p_value->'normalizer_version')<>'string'
    OR jsonb_typeof(p_value->'conflict')<>'boolean' OR jsonb_typeof(p_value->'segments')<>'array'
    OR jsonb_typeof(p_value->'financial_years')<>'array' OR jsonb_typeof(p_value->'printed_financial_years')<>'array'
    OR jsonb_typeof(p_value->'derived_financial_years')<>'array' THEN RETURN false;
  END IF;
  IF p_value->>'kind' NOT IN ('month','quarter','exact_date_range','financial_year','multi_financial_year','non_contiguous','unclear')
    OR p_value->>'precision' NOT IN ('month','quarter','exact_date','financial_year','mixed','unclear')
    OR char_length(p_value->>'raw') NOT BETWEEN 1 AND 512 OR (p_value->>'raw') ~ '[[:cntrl:]]'
    OR char_length(p_value->>'display') NOT BETWEEN 1 AND 512 OR (p_value->>'display') ~ '[[:cntrl:]]'
    OR (p_value->>'catalogue_version') !~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    OR (p_value->>'normalizer_version') !~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    OR jsonb_array_length(p_value->'segments') > 24
    OR NOT public.typed_extraction_string_array_is_valid(p_value->'financial_years','^[0-9]{4}-[0-9]{2}$',30)
    OR NOT public.typed_extraction_string_array_is_valid(p_value->'printed_financial_years','^[0-9]{4}-[0-9]{2}$',30)
    OR NOT public.typed_extraction_string_array_is_valid(p_value->'derived_financial_years','^[0-9]{4}-[0-9]{2}$',30) THEN RETURN false;
  END IF;
  kind := p_value->>'kind'; segment_count := jsonb_array_length(p_value->'segments');
  FOR segment IN SELECT value FROM jsonb_array_elements(p_value->'segments') LOOP
    IF jsonb_typeof(segment) <> 'object' OR NOT public.jsonb_object_has_exact_keys(segment,
      ARRAY['end_date','financial_year','kind','month','quarter','start_date']) THEN RETURN false; END IF;
    IF jsonb_typeof(segment->'kind')<>'string' THEN RETURN false; END IF;
    segment_kind := segment->>'kind';
    IF segment_kind = 'month' THEN
      IF jsonb_typeof(segment->'month')<>'string' OR (segment->>'month') !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' OR segment->'quarter'<>'null' OR segment->'financial_year'<>'null' OR segment->'start_date'<>'null' OR segment->'end_date'<>'null' THEN RETURN false; END IF;
      first_year := substring(segment->>'month',1,4)::integer - CASE WHEN substring(segment->>'month',6,2)::integer<4 THEN 1 ELSE 0 END;
      derived_year := first_year::text||'-'||right((first_year+1)::text,2);
    ELSIF segment_kind = 'quarter' THEN
      IF jsonb_typeof(segment->'quarter')<>'string' OR jsonb_typeof(segment->'financial_year')<>'string' OR segment->>'quarter' NOT IN ('Q1','Q2','Q3','Q4') OR NOT public.typed_financial_year_is_valid(segment->>'financial_year') OR segment->'month'<>'null' OR segment->'start_date'<>'null' OR segment->'end_date'<>'null' THEN RETURN false; END IF;
      derived_year := segment->>'financial_year';
    ELSIF segment_kind = 'date_range' THEN
      IF jsonb_typeof(segment->'start_date')<>'string' OR jsonb_typeof(segment->'end_date')<>'string'
        OR NOT pg_input_is_valid(segment->>'start_date','date') OR NOT pg_input_is_valid(segment->>'end_date','date')
        OR segment->'month'<>'null' OR segment->'quarter'<>'null' OR segment->'financial_year'<>'null' THEN RETURN false; END IF;
      IF (segment->>'start_date')::date > (segment->>'end_date')::date THEN RETURN false; END IF;
      first_year := extract(year FROM (segment->>'start_date')::date)::integer - CASE WHEN extract(month FROM (segment->>'start_date')::date)<4 THEN 1 ELSE 0 END;
      last_year := extract(year FROM (segment->>'end_date')::date)::integer - CASE WHEN extract(month FROM (segment->>'end_date')::date)<4 THEN 1 ELSE 0 END;
      IF last_year-first_year>=30 THEN RETURN false; END IF;
      FOR first_year IN first_year..last_year LOOP
        derived_year := first_year::text||'-'||right((first_year+1)::text,2);
        IF NOT derived_year=ANY(derived) THEN derived:=array_append(derived,derived_year); END IF;
      END LOOP;
      derived_year := NULL;
    ELSIF segment_kind = 'financial_year' THEN
      IF jsonb_typeof(segment->'financial_year')<>'string' OR NOT public.typed_financial_year_is_valid(segment->>'financial_year') OR segment->'month'<>'null' OR segment->'quarter'<>'null' OR segment->'start_date'<>'null' OR segment->'end_date'<>'null' THEN RETURN false; END IF;
      derived_year := segment->>'financial_year';
    ELSE RETURN false;
    END IF;
    IF derived_year IS NOT NULL AND NOT derived_year=ANY(derived) THEN derived:=array_append(derived,derived_year); END IF;
  END LOOP;
  IF NOT (CASE kind
    WHEN 'unclear' THEN segment_count=0 AND p_value->>'precision'='unclear'
    WHEN 'month' THEN segment_count=1 AND p_value#>>'{segments,0,kind}'='month' AND p_value->>'precision'='month'
    WHEN 'quarter' THEN segment_count=1 AND p_value#>>'{segments,0,kind}'='quarter' AND p_value->>'precision'='quarter'
    WHEN 'exact_date_range' THEN segment_count=1 AND p_value#>>'{segments,0,kind}'='date_range' AND p_value->>'precision'='exact_date'
    WHEN 'financial_year' THEN segment_count=1 AND p_value#>>'{segments,0,kind}'='financial_year' AND p_value->>'precision'='financial_year'
    WHEN 'multi_financial_year' THEN segment_count BETWEEN 2 AND 24 AND p_value->>'precision'='financial_year'
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_value->'segments') value WHERE value->>'kind'<>'financial_year')
    WHEN 'non_contiguous' THEN segment_count BETWEEN 2 AND 24 AND p_value->>'precision'='mixed'
    ELSE false END) THEN RETURN false; END IF;

  SELECT coalesce(array_agg(value ORDER BY ordinal),ARRAY[]::text[]) INTO supplied_financial_years FROM jsonb_array_elements_text(p_value->'financial_years') WITH ORDINALITY AS item(value,ordinal);
  SELECT coalesce(array_agg(value ORDER BY ordinal),ARRAY[]::text[]) INTO supplied_derived FROM jsonb_array_elements_text(p_value->'derived_financial_years') WITH ORDINALITY AS item(value,ordinal);
  SELECT coalesce(array_agg(value ORDER BY ordinal),ARRAY[]::text[]) INTO printed FROM jsonb_array_elements_text(p_value->'printed_financial_years') WITH ORDINALITY AS item(value,ordinal);
  IF EXISTS (SELECT 1 FROM unnest(derived) value WHERE NOT public.typed_financial_year_is_valid(value))
    OR supplied_financial_years IS DISTINCT FROM derived OR supplied_derived IS DISTINCT FROM derived THEN RETURN false; END IF;
  SELECT coalesce(array_agg(value ORDER BY value),ARRAY[]::text[]) INTO canonical_printed FROM unnest(printed) value;
  SELECT coalesce(array_agg(value ORDER BY value),ARRAY[]::text[]) INTO canonical_derived FROM unnest(derived) value;
  expected_conflict := cardinality(printed)>0 AND canonical_printed IS DISTINCT FROM canonical_derived;
  RETURN (p_value->>'conflict')::boolean = expected_conflict;
END $$;

CREATE FUNCTION public.typed_official_reference_candidate_is_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, public AS $$
DECLARE normalized_namespace text; canonical_value text; canonical_components jsonb; expected_match_eligible boolean;
BEGIN
  IF jsonb_typeof(p_value) <> 'object' OR NOT public.jsonb_object_has_exact_keys(p_value,
    ARRAY['catalogue_version','components','completeness','display','kind','match_eligible','namespace','namespace_normalized','normalized_value','normalizer_version','raw','role']) THEN RETURN false;
  END IF;
  IF jsonb_typeof(p_value->'role')<>'string' OR jsonb_typeof(p_value->'kind')<>'string'
    OR jsonb_typeof(p_value->'completeness')<>'string' OR jsonb_typeof(p_value->'raw')<>'string'
    OR jsonb_typeof(p_value->'display')<>'string' OR jsonb_typeof(p_value->'normalized_value')<>'string'
    OR jsonb_typeof(p_value->'components')<>'object' OR jsonb_typeof(p_value->'match_eligible')<>'boolean'
    OR jsonb_typeof(p_value->'catalogue_version')<>'string' OR jsonb_typeof(p_value->'normalizer_version')<>'string'
    OR jsonb_typeof(p_value->'namespace') NOT IN ('string','null') OR jsonb_typeof(p_value->'namespace_normalized') NOT IN ('string','null') THEN RETURN false;
  END IF;
  IF p_value->>'role' NOT IN ('self_identifier','outbound_mention')
    OR p_value->>'kind' NOT IN ('proceeding_case_id','notice_reference','order_reference','appeal_reference','court_case_number','other_official_reference')
    OR p_value->>'completeness' NOT IN ('complete','partial','unknown')
    OR (jsonb_typeof(p_value->'namespace')='string' AND (char_length(p_value->>'namespace') NOT BETWEEN 2 AND 160 OR (p_value->>'namespace') ~ '[[:cntrl:]]'))
    OR char_length(p_value->>'raw') NOT BETWEEN 1 AND 300 OR (p_value->>'raw') ~ '[[:cntrl:]]' OR (p_value->>'raw') !~ '[[:alnum:]]'
    OR char_length(p_value->>'display') NOT BETWEEN 1 AND 300 OR (p_value->>'display') ~ '[[:cntrl:]]'
    OR (p_value->>'catalogue_version') !~ '^[a-z0-9][a-z0-9_.-]{0,127}$'
    OR (p_value->>'normalizer_version') !~ '^[a-z0-9][a-z0-9_.-]{0,127}$' THEN RETURN false;
  END IF;
  normalized_namespace:=public.normalize_matter_identifier_namespace_v1(p_value->>'namespace');
  SELECT normalized_value,normalized_components INTO canonical_value,canonical_components
    FROM public.normalize_matter_identifier_value_v1((p_value->>'kind')::public.matter_identifier_kind,p_value->>'raw');
  IF canonical_value IS NULL OR p_value->>'normalized_value' IS DISTINCT FROM canonical_value
    OR p_value->'components' IS DISTINCT FROM canonical_components
    OR p_value->>'namespace_normalized' IS DISTINCT FROM normalized_namespace THEN RETURN false; END IF;
  expected_match_eligible:=p_value->>'completeness'='complete' AND p_value->>'kind'<>'other_official_reference'
    AND normalized_namespace IS NOT NULL AND normalized_namespace NOT IN ('UNKNOWN','UNCLEAR','N/A','NA','NOT AVAILABLE','UNSPECIFIED');
  RETURN (p_value->>'match_eligible')::boolean=expected_match_eligible;
END $$;

CREATE OR REPLACE FUNCTION public.source_field_candidate_normalized_value_is_valid(
  p_value_type public.source_field_candidate_value_type, p_value jsonb
) RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE value_text text;
BEGIN
  IF p_value IS NULL THEN RETURN false; END IF;
  IF p_value_type='structured' THEN RETURN public.typed_tax_period_candidate_is_valid(p_value) OR public.typed_official_reference_candidate_is_valid(p_value); END IF;
  IF p_value_type='boolean' THEN RETURN jsonb_typeof(p_value)='boolean'; END IF;
  IF jsonb_typeof(p_value)<>'string' THEN RETURN false; END IF; value_text:=p_value#>>'{}';
  IF p_value_type='text' THEN RETURN char_length(value_text) BETWEEN 1 AND 1024 AND value_text !~ '[[:cntrl:]]';
  ELSIF p_value_type='code' THEN RETURN value_text ~ '^[A-Za-z0-9][A-Za-z0-9 .,/()&+#:_-]{0,255}$';
  ELSIF p_value_type='date' THEN RETURN value_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' AND pg_input_is_valid(value_text,'date');
  ELSIF p_value_type='integer' THEN RETURN value_text ~ '^-?(0|[1-9][0-9]{0,17})$';
  ELSIF p_value_type='decimal' THEN RETURN value_text ~ '^-?(0|[1-9][0-9]{0,17})(\.[0-9]{1,6})?$'; END IF;
  RETURN false;
END $$;

ALTER TABLE public.source_field_candidates ADD CONSTRAINT source_field_candidates_structured_path_valid CHECK (
  (value_type='structured' AND ((field_path='document.tax_period' AND public.typed_tax_period_candidate_is_valid(normalized_value))
    OR (field_path IN ('document.official_reference.self_identifier','document.official_reference.outbound_mention')
      AND public.typed_official_reference_candidate_is_valid(normalized_value) AND normalized_value->>'role'=split_part(field_path,'.',3))))
  OR (value_type<>'structured' AND field_path NOT IN ('document.tax_period','document.official_reference.self_identifier','document.official_reference.outbound_mention'))
), ADD CONSTRAINT source_field_candidates_structured_anchor_required CHECK (
  value_type<>'structured' OR validation_state='invalid' OR verified_source_anchor IS NOT NULL
);

ALTER TABLE public.source_field_candidates
  ADD COLUMN raw_value text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'raw' ELSE normalized_value#>>'{}' END) STORED,
  ADD COLUMN display_value text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'display' ELSE normalized_value#>>'{}' END) STORED,
  ADD COLUMN value_precision text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'precision' END) STORED,
  ADD COLUMN catalogue_version text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'catalogue_version' END) STORED,
  ADD COLUMN normalizer_version text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'normalizer_version' END) STORED;
ALTER TABLE public.document_field_candidates
  ADD COLUMN raw_value text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'raw' ELSE normalized_value#>>'{}' END) STORED,
  ADD COLUMN display_value text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'display' ELSE normalized_value#>>'{}' END) STORED,
  ADD COLUMN value_precision text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'precision' END) STORED,
  ADD COLUMN catalogue_version text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'catalogue_version' END) STORED,
  ADD COLUMN normalizer_version text GENERATED ALWAYS AS (CASE WHEN value_type='structured' THEN normalized_value->>'normalizer_version' END) STORED;
ALTER TABLE public.document_field_candidates ADD CONSTRAINT document_field_candidates_structured_path_valid CHECK (
  (value_type='structured' AND ((field_path='document.tax_period' AND public.typed_tax_period_candidate_is_valid(normalized_value))
    OR (field_path IN ('document.official_reference.self_identifier','document.official_reference.outbound_mention')
      AND public.typed_official_reference_candidate_is_valid(normalized_value) AND normalized_value->>'role'=split_part(field_path,'.',3))))
  OR (value_type<>'structured' AND field_path NOT IN ('document.tax_period','document.official_reference.self_identifier','document.official_reference.outbound_mention'))
);

CREATE FUNCTION public.typed_source_candidate_run_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE run_catalogue text; run_normalizer text;
BEGIN
  IF NEW.value_type='structured' THEN
    SELECT catalogue_version,normalizer_version INTO run_catalogue,run_normalizer FROM public.source_analysis_runs
      WHERE org_id=NEW.org_id AND id=NEW.source_analysis_run_id FOR KEY SHARE;
    IF NEW.normalized_value->>'catalogue_version' IS DISTINCT FROM run_catalogue OR NEW.normalized_value->>'normalizer_version' IS DISTINCT FROM run_normalizer THEN
      RAISE EXCEPTION 'official reference versions must match their immutable source run'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER source_field_candidates_typed_run_guard BEFORE INSERT ON public.source_field_candidates
  FOR EACH ROW EXECUTE FUNCTION public.typed_source_candidate_run_guard();

ALTER FUNCTION public.source_field_candidate_value_match_count(public.source_field_candidate_value_type,jsonb,text)
  RENAME TO source_field_candidate_value_match_count_legacy;

CREATE OR REPLACE FUNCTION public.source_field_candidate_value_match_count(
  p_value_type public.source_field_candidate_value_type, p_normalized_value jsonb, p_source_text text
) RETURNS integer LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $$
BEGIN
  IF p_value_type='structured' AND public.typed_official_reference_candidate_is_valid(p_normalized_value) THEN
    RETURN public.source_field_candidate_value_match_count('code',to_jsonb(p_normalized_value->>'normalized_value'),p_source_text);
  ELSIF p_value_type='structured' AND public.typed_tax_period_candidate_is_valid(p_normalized_value) THEN
    RETURN public.source_field_candidate_value_match_count('text',to_jsonb(p_normalized_value->>'raw'),p_source_text);
  END IF;
  RETURN public.source_field_candidate_value_match_count_legacy(p_value_type,p_normalized_value,p_source_text);
END $$;

CREATE INDEX source_official_reference_lookup_idx ON public.source_field_candidates(
  org_id,(normalized_value->>'namespace_normalized'),(normalized_value->>'kind'),(normalized_value->>'normalized_value'),source_analysis_run_id
) WHERE value_type='structured' AND field_path LIKE 'document.official_reference.%' AND validation_state<>'invalid'
  AND normalized_value->>'match_eligible'='true' AND normalized_value->>'kind'<>'other_official_reference'
  AND normalized_value->>'namespace_normalized' IS NOT NULL AND normalized_value->>'normalized_value' IS NOT NULL;
CREATE INDEX document_official_reference_lookup_idx ON public.document_field_candidates(
  org_id,(normalized_value->>'namespace_normalized'),(normalized_value->>'kind'),(normalized_value->>'normalized_value'),document_version_id
) WHERE value_type='structured' AND field_path LIKE 'document.official_reference.%' AND validation_state<>'invalid'
  AND normalized_value->>'match_eligible'='true' AND normalized_value->>'kind'<>'other_official_reference'
  AND normalized_value->>'namespace_normalized' IS NOT NULL AND normalized_value->>'normalized_value' IS NOT NULL;
CREATE INDEX source_tax_period_order_idx ON public.source_field_candidates(org_id,source_analysis_run_id,created_at,id)
  WHERE value_type='structured' AND field_path='document.tax_period';

REVOKE ALL ON FUNCTION public.typed_extraction_string_array_is_valid(jsonb,text,integer), public.typed_tax_period_candidate_is_valid(jsonb),
  public.typed_financial_year_is_valid(text), public.typed_official_reference_candidate_is_valid(jsonb), public.typed_source_candidate_run_guard() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.source_field_candidate_value_match_count(public.source_field_candidate_value_type,jsonb,text),
  public.source_field_candidate_value_match_count_legacy(public.source_field_candidate_value_type,jsonb,text)
  FROM PUBLIC,anon,authenticated,service_role;

COMMENT ON INDEX public.source_official_reference_lookup_idx IS 'Candidate discovery only; this index does not verify, reserve, match, place, or relate an official reference.';
COMMIT;
