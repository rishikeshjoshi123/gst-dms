-- Run after `npx supabase db reset --local --no-seed`. Always rolls back.
BEGIN;

DO $fixture$
DECLARE
  owner_a uuid:='a7000000-0000-0000-0000-000000000001'; viewer_a uuid:='a7000000-0000-0000-0000-000000000002'; owner_b uuid:='a7000000-0000-0000-0000-000000000003';
  org_a uuid:='a7100000-0000-0000-0000-000000000001'; org_b uuid:='a7100000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','quote-owner@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer_a,'authenticated','authenticated','quote-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','quote-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_a,'Quote A',owner_a),(org_b,'Quote B',owner_b);
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
    VALUES(org_a,viewer_a,'viewer','active',1,owner_a);
  INSERT INTO public.clients(id,org_id,name) VALUES
    ('a7200000-0000-0000-0000-000000000001',org_a,'Client A'),
    ('a7200000-0000-0000-0000-000000000002',org_b,'Client B');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES
    ('a7300000-0000-0000-0000-000000000001',org_a,'a7200000-0000-0000-0000-000000000001','Matter A'),
    ('a7300000-0000-0000-0000-000000000002',org_b,'a7200000-0000-0000-0000-000000000002','Matter B');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title) VALUES
    ('a7400000-0000-0000-0000-000000000001',org_a,'a7300000-0000-0000-0000-000000000001','fixture/a.pdf',owner_a,'Document A'),
    ('a7400000-0000-0000-0000-000000000002',org_a,'a7300000-0000-0000-0000-000000000001','fixture/failed.pdf',owner_a,'Failed source'),
    ('a7400000-0000-0000-0000-000000000003',org_b,'a7300000-0000-0000-0000-000000000002','fixture/b.pdf',owner_b,'Document B');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,failed_at,validated_page_count,created_by) VALUES
    ('a7500000-0000-0000-0000-000000000001',org_a,'documents','orgs/'||org_a||'/assets/a7500000-0000-0000-0000-000000000001/original.pdf',repeat('1',64),10,'application/pdf','available',now(),NULL,3,owner_a),
    ('a7500000-0000-0000-0000-000000000002',org_a,'documents','orgs/'||org_a||'/assets/a7500000-0000-0000-0000-000000000002/original.pdf',repeat('2',64),10,'application/pdf','available',now(),NULL,5,owner_a),
    ('a7500000-0000-0000-0000-000000000003',org_a,'documents','orgs/'||org_a||'/assets/a7500000-0000-0000-0000-000000000003/original.pdf',repeat('3',64),10,'application/pdf','failed',NULL,now(),2,owner_a),
    ('a7500000-0000-0000-0000-000000000004',org_b,'documents','orgs/'||org_b||'/assets/a7500000-0000-0000-0000-000000000004/original.pdf',repeat('4',64),10,'application/pdf','available',now(),NULL,2,owner_b);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,superseded_at,created_by) VALUES
    ('a7600000-0000-0000-0000-000000000001',org_a,'a7400000-0000-0000-0000-000000000001','a7500000-0000-0000-0000-000000000001',1,'a-v1.pdf',3,'valid','superseded',now(),now()-interval '1 day',now(),owner_a),
    ('a7600000-0000-0000-0000-000000000002',org_a,'a7400000-0000-0000-0000-000000000001','a7500000-0000-0000-0000-000000000002',2,'a-v2.pdf',5,'valid','current',now(),now(),NULL,owner_a),
    ('a7600000-0000-0000-0000-000000000003',org_a,'a7400000-0000-0000-0000-000000000002','a7500000-0000-0000-0000-000000000003',1,'failed.pdf',2,'valid','current',now(),now(),NULL,owner_a),
    ('a7600000-0000-0000-0000-000000000004',org_b,'a7400000-0000-0000-0000-000000000003','a7500000-0000-0000-0000-000000000004',1,'b.pdf',2,'valid','current',now(),now(),NULL,owner_b);
  UPDATE public.documents SET current_version_id=CASE id
    WHEN 'a7400000-0000-0000-0000-000000000001'::uuid THEN 'a7600000-0000-0000-0000-000000000002'::uuid
    WHEN 'a7400000-0000-0000-0000-000000000002'::uuid THEN 'a7600000-0000-0000-0000-000000000003'::uuid
    ELSE 'a7600000-0000-0000-0000-000000000004'::uuid END;
  INSERT INTO public.case_notes(id,org_id,matter_id,document_id,author_id,content,quote,page_number)
  VALUES('a7700000-0000-0000-0000-000000000099',org_a,'a7300000-0000-0000-0000-000000000001',
    'a7400000-0000-0000-0000-000000000001',owner_a,'Legacy note','Ambiguous excerpt',2);
END $fixture$;

SET LOCAL ROLE authenticated;
DO $actor_matrix$
DECLARE current_result record; historical_result record; result record; locator record; denied boolean:=false;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000001',true);
  SELECT * INTO current_result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Current exact quote','general',false,
    'a7800000-0000-0000-0000-000000000001','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'Exact current bytes',5,'a7600000-0000-0000-0000-000000000002');
  IF current_result.code<>'ok' OR current_result.note_id IS NULL THEN RAISE EXCEPTION 'current exact quotation failed'; END IF;
  -- This proves the new-write lock contract is held by this transaction; it
  -- intentionally does not claim to simulate or prove concurrent scheduling.
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_locks AS lock
    WHERE lock.locktype='advisory' AND lock.pid=pg_catalog.pg_backend_pid() AND lock.granted
      AND lock.classid=pg_catalog.hashtext('a7100000-0000-0000-0000-000000000001')::oid
      AND lock.objid=pg_catalog.hashtext('hierarchical-resource-trash')::oid
  ) THEN RAISE EXCEPTION 'new note creation did not retain the hierarchy advisory fence'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Current exact quote','general',false,
    'a7800000-0000-0000-0000-000000000001','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'Exact current bytes',5,'a7600000-0000-0000-0000-000000000002');
  IF result.code<>'ok' OR NOT result.replayed OR result.note_id<>current_result.note_id THEN RAISE EXCEPTION 'same source replay failed'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Current exact quote','general',false,
    'a7800000-0000-0000-0000-000000000001','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'Exact current bytes',1,'a7600000-0000-0000-0000-000000000001');
  IF result.code<>'idempotency_conflict' THEN RAISE EXCEPTION 'locator mismatch reused an idempotency key'; END IF;
  SELECT * INTO historical_result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Historical exact quote','general',false,
    'a7800000-0000-0000-0000-000000000002','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'Exact historical bytes',3,'a7600000-0000-0000-0000-000000000001');
  IF historical_result.code<>'ok' THEN RAISE EXCEPTION 'superseded exact quotation failed'; END IF;

  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Bad page zero','general',false,
    'a7800000-0000-0000-0000-000000000003','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'bad',0,'a7600000-0000-0000-0000-000000000002');
  IF result.code<>'invalid_request' THEN RAISE EXCEPTION 'page zero accepted'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Past end','general',false,
    'a7800000-0000-0000-0000-000000000004','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'bad',6,'a7600000-0000-0000-0000-000000000002');
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'past-end page accepted'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Foreign version','general',false,
    'a7800000-0000-0000-0000-000000000005','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'bad',1,'a7600000-0000-0000-0000-000000000004');
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'foreign version accepted'; END IF;
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Failed asset','general',false,
    'a7800000-0000-0000-0000-000000000006','a7400000-0000-0000-0000-000000000002',NULL,NULL,NULL,
    'bad',1,'a7600000-0000-0000-0000-000000000003');
  IF result.code<>'source_unavailable' THEN RAISE EXCEPTION 'failed asset accepted'; END IF;

  SELECT * INTO locator FROM public.get_note_quote_locators(ARRAY[current_result.note_id]);
  IF locator.document_version_id<>'a7600000-0000-0000-0000-000000000002' OR locator.page_number<>5
     OR NOT locator.is_current OR NOT locator.source_available THEN RAISE EXCEPTION 'exact locator readback changed identity'; END IF;
  IF EXISTS(SELECT 1 FROM public.get_note_quote_locators(ARRAY['a7700000-0000-0000-0000-000000000099'::uuid])) THEN
    RAISE EXCEPTION 'ambiguous legacy quotation was fabricated'; END IF;

  BEGIN UPDATE public.case_notes SET quote='forged' WHERE id=current_result.note_id; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'legacy quote direct update was allowed'; END IF;
  denied:=false;
  BEGIN INSERT INTO public.note_document_quotes(note_id,org_id,matter_id,document_id,document_version_id,page_number,excerpt)
    VALUES(gen_random_uuid(),'a7100000-0000-0000-0000-000000000001','a7300000-0000-0000-0000-000000000001',
      'a7400000-0000-0000-0000-000000000001','a7600000-0000-0000-0000-000000000002',1,'forged');
  EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'direct locator insert was allowed'; END IF;

  PERFORM set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000002',true);
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Viewer quote','general',false,
    'a7800000-0000-0000-0000-000000000007','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'bad',1,'a7600000-0000-0000-0000-000000000002');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'viewer created quotation'; END IF;
  PERFORM set_config('request.jwt.claim.sub','a7000000-0000-0000-0000-000000000003',true);
  SELECT * INTO result FROM public.create_note_with_optional_task(
    'a7300000-0000-0000-0000-000000000001','Cross tenant quote','general',false,
    'a7800000-0000-0000-0000-000000000008','a7400000-0000-0000-0000-000000000001',NULL,NULL,NULL,
    'bad',1,'a7600000-0000-0000-0000-000000000002');
  IF result.code<>'context_unavailable' THEN RAISE EXCEPTION 'cross-tenant quote did not fail closed'; END IF;
END $actor_matrix$;
RESET ROLE;

DO $privileges$
BEGIN
  IF has_table_privilege('authenticated','public.note_document_quotes','INSERT')
     OR has_table_privilege('authenticated','public.note_document_quotes','UPDATE')
     OR has_table_privilege('service_role','public.note_document_quotes','SELECT')
     OR has_function_privilege('service_role','public.get_note_quote_locators(uuid[],uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.create_note_with_optional_task(uuid,text,public.note_template_type,boolean,uuid,uuid,uuid,date,uuid,text,integer,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'quotation privilege surface is unsafe';
  END IF;
END $privileges$;

ROLLBACK;
