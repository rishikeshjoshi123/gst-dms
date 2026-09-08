-- Run after migration 00129. The transaction is always rolled back.
\set ON_ERROR_STOP on
BEGIN;

DO $privileges$
DECLARE column_name text;
BEGIN
  FOREACH column_name IN ARRAY ARRAY[
    'ai_prompt_version','confidence_scores','doc_date','doc_type',
    'financial_year','raw_metadata','reference_number'
  ] LOOP
    IF has_column_privilege('authenticated','public.documents',column_name,'UPDATE')
       OR has_column_privilege('service_role','public.documents',column_name,'UPDATE') THEN
      RAISE EXCEPTION 'direct document metadata update privilege survived for %',column_name;
    END IF;
  END LOOP;

  IF NOT has_function_privilege(
    'service_role',
    'public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.record_current_document_inspector_correction(uuid,uuid,uuid,uuid,text,jsonb,uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'canonical inspector correction authority changed';
  END IF;
END $privileges$;

ROLLBACK;
