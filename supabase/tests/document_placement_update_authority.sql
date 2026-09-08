-- Run after migration 00130. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $privileges$
BEGIN
  IF has_column_privilege('authenticated','public.documents','matter_id','UPDATE')
     OR has_column_privilege('authenticated','public.documents','source','UPDATE')
     OR has_column_privilege('service_role','public.documents','matter_id','UPDATE')
     OR has_column_privilege('service_role','public.documents','source','UPDATE') THEN
    RAISE EXCEPTION 'direct document placement update privilege survived';
  END IF;
END $privileges$;

ROLLBACK;
