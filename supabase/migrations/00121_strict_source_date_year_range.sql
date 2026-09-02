-- source-verifier.ts canonicalDate accepts only four-digit Gregorian years
-- from 1000 through 9999. PostgreSQL make_date also accepts earlier years,
-- so preserve the TypeScript contract before normalizing any source date.
BEGIN;

CREATE OR REPLACE FUNCTION public.source_field_candidate_source_date(p_value text)
RETURNS date LANGUAGE plpgsql IMMUTABLE STRICT SET search_path = pg_catalog, public AS $$
DECLARE match text[]; month_number integer;
BEGIN
  match := regexp_match(btrim(p_value), '^([0-9]{4})-([0-9]{2})-([0-9]{2})$');
  IF match IS NOT NULL THEN
    IF match[1]::integer < 1000 THEN RETURN NULL; END IF;
    RETURN make_date(match[1]::integer, match[2]::integer, match[3]::integer);
  END IF;
  match := regexp_match(btrim(p_value), '^([0-9]{1,2})[./-]([0-9]{1,2})[./-]([0-9]{4})$');
  IF match IS NOT NULL THEN
    IF match[3]::integer < 1000 THEN RETURN NULL; END IF;
    RETURN make_date(match[3]::integer, match[2]::integer, match[1]::integer);
  END IF;
  match := regexp_match(btrim(p_value), '^([0-9]{1,2})(st|nd|rd|th)?[[:space:]]+([A-Za-z]+)[.]?[,]?[[:space:]]+([0-9]{4})$', 'i');
  IF match IS NOT NULL THEN
    IF match[4]::integer < 1000 THEN RETURN NULL; END IF;
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
    IF match[4]::integer < 1000 THEN RETURN NULL; END IF;
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

REVOKE ALL ON FUNCTION public.source_field_candidate_source_date(text) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.source_field_candidate_source_date(text) IS
  'Service-only parsing for the supported source date formats, with the same 1000..9999 Gregorian year range as source-verifier.ts.';

COMMIT;
