-- Run after migration 00132. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $privileges$
DECLARE column_name text;
BEGIN
  FOREACH column_name IN ARRAY ARRAY[
    'status','review_status','review_reason','reviewed_at','reviewed_by'
  ] LOOP
    IF has_column_privilege('authenticated','public.documents',column_name,'UPDATE')
       OR has_column_privilege('service_role','public.documents',column_name,'UPDATE') THEN
      RAISE EXCEPTION 'direct legacy review update privilege survived for %',column_name;
    END IF;
  END LOOP;
END $privileges$;

ROLLBACK;
