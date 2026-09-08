-- Run after migration 00133. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $privileges$
BEGIN
  IF has_table_privilege('authenticated','public.documents','UPDATE')
     OR has_table_privilege('service_role','public.documents','UPDATE')
     OR EXISTS (
       SELECT 1
       FROM information_schema.columns AS column_info
       WHERE column_info.table_schema='public' AND column_info.table_name='documents'
         AND (has_column_privilege('authenticated','public.documents',column_info.column_name,'UPDATE')
           OR has_column_privilege('service_role','public.documents',column_info.column_name,'UPDATE'))
     ) OR EXISTS (
       SELECT 1 FROM pg_catalog.pg_policies
       WHERE schemaname='public' AND tablename='documents' AND cmd='UPDATE'
     ) THEN
    RAISE EXCEPTION 'direct document update authority survived';
  END IF;
END $privileges$;

ROLLBACK;
