-- Run after migration 00131. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $privileges$
BEGIN
  IF has_column_privilege('authenticated','public.documents','document_class','UPDATE')
     OR has_column_privilege('authenticated','public.documents','document_category','UPDATE')
     OR has_column_privilege('service_role','public.documents','document_class','UPDATE')
     OR has_column_privilege('service_role','public.documents','document_category','UPDATE') THEN
    RAISE EXCEPTION 'direct document classification update privilege survived';
  END IF;
END $privileges$;

ROLLBACK;
