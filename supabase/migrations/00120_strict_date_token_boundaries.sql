-- source-verifier.ts recognises source dates with JavaScript's ASCII word
-- boundaries. Keep the SQL materializer from accepting a supported date that
-- appears only as part of a larger identifier or number.
BEGIN;

CREATE OR REPLACE FUNCTION public.source_field_candidate_value_match_count(
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
  date_pattern constant text := '([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{1,2}[./-][0-9]{1,2}[./-][0-9]{4}|[0-9]{1,2}(st|nd|rd|th)?[[:space:]]+[A-Za-z]+[.]?[,]?[[:space:]]+[0-9]{4}|[A-Za-z]+[.]?[[:space:]]+[0-9]{1,2}(st|nd|rd|th)?[,]?[[:space:]]+[0-9]{4})';
BEGIN
  IF jsonb_typeof(p_normalized_value) <> 'string' OR p_source_text IS NULL THEN
    RETURN 0;
  END IF;
  candidate := p_normalized_value #>> '{}';

  IF p_value_type = 'date'::public.source_field_candidate_value_type THEN
    target_date := public.source_field_candidate_source_date(candidate);
    IF target_date IS NULL THEN RETURN 0; END IF;
    source_length := char_length(p_source_text);
    FOR source_start IN 1..source_length LOOP
      before_char := CASE WHEN source_start = 1 THEN NULL ELSE substring(p_source_text FROM source_start - 1 FOR 1) END;
      -- This is the SQL equivalent of the leading JavaScript `\b`: date
      -- tokens may not start immediately after an ASCII word character.
      IF before_char IS NOT NULL AND before_char ~ '[A-Za-z0-9_]' THEN CONTINUE; END IF;
      matched := regexp_match(substring(p_source_text FROM source_start), '^' || date_pattern, 'i');
      IF matched IS NULL THEN CONTINUE; END IF;
      match_text := matched[1];
      source_end := source_start + char_length(match_text);
      after_char := CASE WHEN source_end > source_length THEN NULL ELSE substring(p_source_text FROM source_end FOR 1) END;
      -- This is the trailing JavaScript `\b`; it rejects an otherwise valid
      -- prefix such as 2025-01-29 in 2025-01-290.
      IF after_char IS NOT NULL AND after_char ~ '[A-Za-z0-9_]' THEN CONTINUE; END IF;
      IF public.source_field_candidate_source_date(match_text) = target_date THEN
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

REVOKE ALL ON FUNCTION public.source_field_candidate_value_match_count(public.source_field_candidate_value_type,jsonb,text) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.source_field_candidate_value_match_count(public.source_field_candidate_value_type,jsonb,text) IS
  'Service-only exact source matching equivalent to source-verifier.ts, including ASCII word boundaries for every supported date format.';

COMMIT;
