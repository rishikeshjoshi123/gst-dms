-- Run after migration 00073 against a disposable local Supabase database.
-- The matter-backfill write must not revive an old-version vector after a
-- replacement, and a replacement must clear its former vector provenance.
BEGIN;

DO $setup$
DECLARE
  actor_id uuid := '70100000-0000-0000-0000-000000000001';
  org_id uuid := '70200000-0000-0000-0000-000000000001';
  client_id uuid := '70300000-0000-0000-0000-000000000001';
  matter_id uuid := '70400000-0000-0000-0000-000000000001';
  document_id uuid := '70500000-0000-0000-0000-000000000001';
  old_asset_id uuid := '70600000-0000-0000-0000-000000000001';
  new_asset_id uuid := '70600000-0000-0000-0000-000000000002';
  old_version_id uuid := '70700000-0000-0000-0000-000000000001';
  new_version_id uuid := '70700000-0000-0000-0000-000000000002';
  old_projection_fingerprint text;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000',actor_id,'authenticated','authenticated','search-version-fence@test','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_id,'Search version fence org',actor_id);
  INSERT INTO public.clients(id,org_id,name) VALUES(client_id,org_id,'Search version fence client');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_id,org_id,client_id,'Search version fence matter');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
    (old_asset_id,org_id,'documents','orgs/'||org_id||'/assets/'||old_asset_id||'/original.pdf',repeat('a',64),10,'application/pdf','available',now(),1,actor_id),
    (new_asset_id,org_id,'documents','orgs/'||org_id||'/assets/'||new_asset_id||'/original.pdf',repeat('b',64),11,'application/pdf','available',now(),1,actor_id);
  INSERT INTO public.documents(id,org_id,matter_id,display_title,origin_kind,record_state,content_availability,status,doc_type,reference_number,summary,created_by)
  VALUES(document_id,org_id,matter_id,'Version-fenced Search target','upload','active','source_attached','placed','SCN','VF/1','Version-fenced summary.',actor_id);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES(old_version_id,org_id,document_id,old_asset_id,1,'old.pdf',1,'valid','current',now(),now(),actor_id);
  UPDATE public.documents SET current_version_id=old_version_id WHERE id=document_id;
  SELECT projection_fingerprint INTO old_projection_fingerprint
  FROM public.read_current_document_search_index_projection(org_id, ARRAY[document_id]);

  SET LOCAL ROLE service_role;
  IF (SELECT code FROM public.write_current_document_search_index_embedding(
    org_id,document_id,old_version_id,('['||repeat('0.1,',767)||'0.1]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,old_projection_fingerprint
  )) <> 'indexed' THEN
    RAISE EXCEPTION 'initial old-version embedding write was not accepted';
  END IF;
  RESET ROLE;

  UPDATE public.document_versions
  SET state='superseded',superseded_at=now()
  WHERE id=old_version_id;
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
  VALUES(new_version_id,org_id,document_id,new_asset_id,2,'new.pdf',1,'valid','current',now(),now(),actor_id);
  UPDATE public.documents SET current_version_id=new_version_id,content_availability='source_attached'
  WHERE id=document_id;
END $setup$;

SELECT set_config('request.jwt.claim.role','service_role',true);
DO $race_fence$
DECLARE
  projection_row record;
  write_code text;
BEGIN
  SELECT * INTO projection_row
  FROM public.read_current_document_search_index_projection(
    '70200000-0000-0000-0000-000000000001',
    ARRAY['70500000-0000-0000-0000-000000000001'::uuid]
  );
  IF projection_row.document_version_id <> '70700000-0000-0000-0000-000000000002'::uuid THEN
    RAISE EXCEPTION 'Search projection did not carry the current replacement version';
  END IF;
  IF (SELECT embedding FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL
     OR (SELECT embedding_document_version_id FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'replacement did not clear the previous-version Search embedding';
  END IF;
  SELECT code INTO write_code FROM public.write_current_document_search_index_embedding(
    '70200000-0000-0000-0000-000000000001',
    '70500000-0000-0000-0000-000000000001',
    '70700000-0000-0000-0000-000000000001',
    ('['||repeat('0.1,',767)||'0.1]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  IF write_code <> 'version_not_current'
     OR (SELECT embedding FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'stale async Search embedding write escaped the version fence';
  END IF;
  SELECT code INTO write_code FROM public.write_current_document_search_index_embedding(
    '70200000-0000-0000-0000-000000000001',
    '70500000-0000-0000-0000-000000000001',
    projection_row.document_version_id,
    ('['||repeat('0.1,',767)||'0.1]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  IF write_code <> 'indexed'
     OR (SELECT embedding_document_version_id FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001')
        <> projection_row.document_version_id THEN
    RAISE EXCEPTION 'current Search embedding write did not retain its source version';
  END IF;
  UPDATE public.documents
  SET embedding_document_version_id = '70700000-0000-0000-0000-000000000001'::uuid
  WHERE id = '70500000-0000-0000-0000-000000000001';
  IF EXISTS (
    SELECT 1 FROM public.match_all_documents_v2(
      ('['||repeat('0.1,',767)||'0.1]')::vector,-1,5,
      '70200000-0000-0000-0000-000000000001',
      'gemini-embedding-001','gemini-embedding-001-768-v1'
    )
  ) OR EXISTS (
    SELECT 1 FROM public.match_documents_v2(
      ('['||repeat('0.1,',767)||'0.1]')::vector,-1,5,
      '70400000-0000-0000-0000-000000000001',
      'gemini-embedding-001','gemini-embedding-001-768-v1'
    )
  ) THEN
    RAISE EXCEPTION 'Search matching returned a vector with stale version provenance';
  END IF;
  SELECT code INTO write_code FROM public.write_current_document_search_index_embedding(
    '70200000-0000-0000-0000-000000000001',
    '70500000-0000-0000-0000-000000000001',
    projection_row.document_version_id,
    ('['||repeat('0.1,',767)||'0.1]')::vector,
    'gemini-embedding-001','gemini-embedding-001-768-v1',7,projection_row.projection_fingerprint
  );
  IF write_code <> 'indexed'
     OR (SELECT count(*) FROM public.match_all_documents_v2(
       ('['||repeat('0.1,',767)||'0.1]')::vector,-1,5,
       '70200000-0000-0000-0000-000000000001',
       'gemini-embedding-001','gemini-embedding-001-768-v1'
     )) <> 1
     OR (SELECT count(*) FROM public.match_documents_v2(
       ('['||repeat('0.1,',767)||'0.1]')::vector,-1,5,
       '70400000-0000-0000-0000-000000000001',
       'gemini-embedding-001','gemini-embedding-001-768-v1'
     )) <> 1 THEN
    RAISE EXCEPTION 'Search matching did not retain the current-provenance vector';
  END IF;
END $race_fence$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','70100000-0000-0000-0000-000000000001',true);
DO $not_indexable_request$
DECLARE result record;
BEGIN
  SELECT * INTO result FROM public.request_document_reprocess(
    '70500000-0000-0000-0000-000000000001','search_index',
    '70800000-0000-0000-0000-000000000001',6
  );
  IF result.code <> 'queued' THEN
    RAISE EXCEPTION 'not-indexable fixture Search reprocess was not queued';
  END IF;
  PERFORM set_config('test.not_indexable_event',result.outbox_event_id::text,true);
END $not_indexable_request$;
RESET ROLE;

UPDATE public.outbox_events
SET delivery_state='leased',lease_token='70800000-0000-0000-0000-000000000002',
    lease_expires_at=now()+interval '2 minutes',delivered_at=NULL,failed_at=NULL
WHERE id=current_setting('test.not_indexable_event')::uuid;

SET LOCAL ROLE service_role;
DO $not_indexable_terminal_cleanup$
DECLARE claim record; input_row record; completion record;
BEGIN
  SELECT * INTO claim FROM public.claim_document_search_index_reprocess_work(
    current_setting('test.not_indexable_event')::uuid,'not-indexable-test',
    '70200000-0000-0000-0000-000000000001','70800000-0000-0000-0000-000000000002'
  );
  SELECT * INTO input_row
  FROM public.get_document_search_index_reprocess_input(claim.processing_run_id,claim.lease_token);
  SELECT * INTO completion FROM public.finish_document_search_index_reprocess_work(
    claim.processing_run_id,claim.lease_token,'not_indexable',
    NULL,NULL,NULL,NULL,input_row.projection_fingerprint
  );
  IF claim.code <> 'claimed' OR input_row.code <> 'ready'
     OR completion.code <> 'not_indexable'
     OR (SELECT embedding FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL
     OR (SELECT embedding_model FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL
     OR (SELECT embedding_version FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL
     OR (SELECT embedding_document_version_id FROM public.documents WHERE id='70500000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'not-indexable completion did not clear all Search vector provenance';
  END IF;
END $not_indexable_terminal_cleanup$;
RESET ROLE;

DO $surface$
BEGIN
  IF has_function_privilege('authenticated', 'public.write_current_document_search_index_embedding(uuid,uuid,uuid,vector,text,text,integer,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.write_current_document_search_index_embedding(uuid,uuid,uuid,vector,text,text,integer,text)', 'EXECUTE')
     OR has_column_privilege('service_role', 'public.documents', 'embedding', 'INSERT')
     OR has_column_privilege('service_role', 'public.documents', 'embedding', 'UPDATE')
     OR has_column_privilege('service_role', 'public.documents', 'embedding_model', 'INSERT')
     OR has_column_privilege('service_role', 'public.documents', 'embedding_model', 'UPDATE')
     OR has_column_privilege('service_role', 'public.documents', 'embedding_version', 'INSERT')
     OR has_column_privilege('service_role', 'public.documents', 'embedding_version', 'UPDATE')
     OR has_column_privilege('service_role', 'public.documents', 'embedding_document_version_id', 'INSERT')
     OR has_column_privilege('service_role', 'public.documents', 'embedding_document_version_id', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding', 'INSERT')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding_model', 'INSERT')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding_model', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding_version', 'INSERT')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding_version', 'UPDATE')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding_document_version_id', 'INSERT')
     OR has_column_privilege('authenticated', 'public.documents', 'embedding_document_version_id', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.documents', 'doc_type', 'INSERT')
     OR NOT has_column_privilege('authenticated', 'public.documents', 'status', 'UPDATE') THEN
    RAISE EXCEPTION 'version-fenced Search embedding writer has an unsafe authority surface';
  END IF;
END $surface$;

ROLLBACK;
