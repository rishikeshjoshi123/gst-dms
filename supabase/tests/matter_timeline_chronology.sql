-- Run after migration 00140 against a disposable local Supabase database.
-- This executable fixture is rollback-only and never resets shared state.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000001','authenticated','authenticated','owner-a@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000002','authenticated','authenticated','admin-a@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000003','authenticated','authenticated','associate-a@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000004','authenticated','authenticated','viewer-a@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000005','authenticated','authenticated','suspended-a@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000006','authenticated','authenticated','removed-a@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000007','authenticated','authenticated','no-member@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000008','authenticated','authenticated','owner-b@timeline.test','x',now(),'{}','{}',now(),now()),
  ('00000000-0000-0000-0000-000000000000','a1400000-0000-0000-0000-000000000009','authenticated','authenticated','duplicate@timeline.test','x',now(),'{}','{}',now(),now());

INSERT INTO public.organisations(id,name,created_by) VALUES
  ('b1400000-0000-0000-0000-000000000001','Timeline organisation A','a1400000-0000-0000-0000-000000000001'),
  ('b1400000-0000-0000-0000-000000000002','Timeline organisation B','a1400000-0000-0000-0000-000000000008');
INSERT INTO public.org_members(org_id,user_id,role) VALUES
  ('b1400000-0000-0000-0000-000000000001','a1400000-0000-0000-0000-000000000002','admin'),
  ('b1400000-0000-0000-0000-000000000001','a1400000-0000-0000-0000-000000000003','associate'),
  ('b1400000-0000-0000-0000-000000000001','a1400000-0000-0000-0000-000000000004','viewer'),
  ('b1400000-0000-0000-0000-000000000001','a1400000-0000-0000-0000-000000000005','associate'),
  ('b1400000-0000-0000-0000-000000000001','a1400000-0000-0000-0000-000000000006','viewer');
UPDATE public.organisation_memberships SET state='suspended',suspended_at=now(),suspended_by='a1400000-0000-0000-0000-000000000001',suspension_reason='fixture'
WHERE org_id='b1400000-0000-0000-0000-000000000001' AND user_id='a1400000-0000-0000-0000-000000000005';
UPDATE public.organisation_memberships SET state='removed',removed_at=now(),removed_by='a1400000-0000-0000-0000-000000000001',removal_reason='fixture'
WHERE org_id='b1400000-0000-0000-0000-000000000001' AND user_id='a1400000-0000-0000-0000-000000000006';

INSERT INTO public.clients(id,org_id,name) VALUES
  ('c1400000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','Active client'),
  ('c1400000-0000-0000-0000-000000000002','b1400000-0000-0000-0000-000000000001','Deleted client'),
  ('c1400000-0000-0000-0000-000000000003','b1400000-0000-0000-0000-000000000002','Foreign client');
UPDATE public.clients SET record_state='trashed',deleted_at=now() WHERE id='c1400000-0000-0000-0000-000000000002';

INSERT INTO public.matters(id,org_id,client_id,title,financial_year,status) VALUES
  ('d1400000-0000-0000-0000-000000000000','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Zero fixture','FY-000','active'),
  ('d1400000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','One fixture','FY-001','active'),
  ('d1400000-0000-0000-0000-000000000050','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Fifty fixture','FY-050','active'),
  ('d1400000-0000-0000-0000-000000000100','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Hundred fixture','FY-100','active'),
  ('d1400000-0000-0000-0000-000000000250','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Two hundred fifty fixture','FY-250','active'),
  ('d1400000-0000-0000-0000-000000000900','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Metadata fixture','FY-900','active'),
  ('d1400000-0000-0000-0000-000000000901','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Closed fixture','FY-901','closed'),
  ('d1400000-0000-0000-0000-000000000902','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Stayed fixture','FY-902','stayed'),
  ('d1400000-0000-0000-0000-000000000903','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Disposed fixture','FY-903','disposed'),
  ('d1400000-0000-0000-0000-000000000904','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Appeal fixture','FY-904','appeal_pending'),
  ('d1400000-0000-0000-0000-000000000905','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Tribunal fixture','FY-905','tribunal'),
  ('d1400000-0000-0000-0000-000000000906','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','High Court fixture','FY-906','high_court'),
  ('d1400000-0000-0000-0000-000000000907','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Supreme Court fixture','FY-907','supreme_court'),
  ('d1400000-0000-0000-0000-000000000908','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000002','Deleted parent client fixture','FY-908','active'),
  ('d1400000-0000-0000-0000-000000000909','b1400000-0000-0000-0000-000000000001','c1400000-0000-0000-0000-000000000001','Trashed matter fixture','FY-909','active'),
  ('d1400000-0000-0000-0000-000000000999','b1400000-0000-0000-0000-000000000002','c1400000-0000-0000-0000-000000000003','Foreign fixture','FY-999','active');
UPDATE public.matters SET record_state='trashed',deleted_at=now() WHERE id='d1400000-0000-0000-0000-000000000909';

DO $paging_seed$
DECLARE fixture record; item integer;
BEGIN
  FOR fixture IN SELECT * FROM (VALUES
    ('d1400000-0000-0000-0000-000000000001'::uuid,1),
    ('d1400000-0000-0000-0000-000000000050'::uuid,50),
    ('d1400000-0000-0000-0000-000000000100'::uuid,100),
    ('d1400000-0000-0000-0000-000000000250'::uuid,250)
  ) AS values(matter_id,item_count)
  LOOP
    FOR item IN 1..fixture.item_count LOOP
      INSERT INTO public.documents(id,org_id,matter_id,display_title,doc_type,reference_number,doc_date,direction,document_class,origin_kind,content_availability,status,storage_path,created_by,created_at)
      VALUES (
        ('e' || lpad(fixture.item_count::text,3,'0') || '0000-0000-0000-0000-' || lpad(item::text,12,'0'))::uuid,
        'b1400000-0000-0000-0000-000000000001',fixture.matter_id,
        CASE WHEN fixture.item_count=1 THEN E'Literal %_\\ Mixed Case' ELSE 'Paging ' || lpad(item::text,3,'0') END,
        CASE WHEN fixture.item_count=1 THEN 'Notice' ELSE 'Order' END,
        'PAGE/' || item,
        CASE WHEN item=fixture.item_count THEN NULL ELSE date '2026-01-01' + ((item-1)/10) END,
        CASE WHEN item%2=0 THEN 'outgoing'::public.doc_direction ELSE 'incoming'::public.doc_direction END,
        'proceeding','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001',
        timestamptz '2026-01-01 00:00:00+00' + item * interval '1 second'
      );
    END LOOP;
  END LOOP;
END $paging_seed$;

-- Every historical work status remains readable when lifecycle and parent lineage are active.
INSERT INTO public.documents(org_id,matter_id,display_title,document_class,origin_kind,content_availability,status,storage_path,created_by)
SELECT 'b1400000-0000-0000-0000-000000000001',id,title,'proceeding','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001'
FROM public.matters WHERE id BETWEEN 'd1400000-0000-0000-0000-000000000901' AND 'd1400000-0000-0000-0000-000000000907';

-- Excluded document lineage and one honest metadata-only proceeding.
INSERT INTO public.documents(id,org_id,matter_id,display_title,doc_type,reference_number,doc_date,direction,document_class,origin_kind,content_availability,status,storage_path,created_by) VALUES
  ('e1400000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Honest metadata only','Manual order','META/1','2026-06-15','incoming','proceeding','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000002','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Attached without pointer','Must not fall back','NO/FALLBACK','2026-06-16','outgoing','proceeding','legacy_migration','source_attached','placed','legacy/no-fallback.pdf','a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000003','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Supporting excluded',NULL,NULL,NULL,NULL,'supporting','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000004','b1400000-0000-0000-0000-000000000002','d1400000-0000-0000-0000-000000000999','Foreign excluded',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000008'),
  ('e1400000-0000-0000-0000-000000000005','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Trashed excluded',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000006','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Deleted excluded',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000007','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Legacy null class','Legacy notice','LEGACY/1','2026-06-17','outgoing',NULL,'manual_record','metadata_only','placed',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000008','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Processing item',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','processing',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000009','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Review item',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','needs_review',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000010','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Failed item',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','failed',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000011','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Uploaded item',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','uploaded',NULL,'a1400000-0000-0000-0000-000000000001'),
  ('e1400000-0000-0000-0000-000000000012','b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Pending placement item',NULL,NULL,NULL,NULL,'proceeding','manual_record','metadata_only','pending_placement',NULL,'a1400000-0000-0000-0000-000000000001');
UPDATE public.documents SET record_state='trashed',deleted_at=now(),trashed_at=now() WHERE id='e1400000-0000-0000-0000-000000000005';
UPDATE public.documents SET deleted_at=now() WHERE id='e1400000-0000-0000-0000-000000000006';

-- Versioned metadata fixtures. All provider-derived values pass through the
-- source-candidate and version-analysis commands; human precedence uses the
-- decision command below.
DO $metadata_seed$
DECLARE
  names text[] := ARRAY['good','rejected','cleared','ambiguous','wrongtype','baddate','baddirection'];
  name text; pos integer; document_id uuid; asset_id uuid; version_id uuid; run_id uuid; candidate_id uuid;
  old_asset uuid; old_version uuid; old_run uuid;
BEGIN
  FOREACH name IN ARRAY names LOOP
    pos := array_position(names,name);
    document_id := ('e1410000-0000-0000-0000-' || lpad(pos::text,12,'0'))::uuid;
    asset_id := gen_random_uuid(); version_id := gen_random_uuid(); run_id := gen_random_uuid();
    INSERT INTO public.documents(id,org_id,matter_id,display_title,doc_type,reference_number,doc_date,direction,document_class,origin_kind,content_availability,status,storage_path,created_by)
    VALUES(document_id,'b1400000-0000-0000-0000-000000000001','d1400000-0000-0000-0000-000000000900','Versioned '||name,'Legacy fallback forbidden','LEGACY/'||pos,'2020-01-01','outgoing','proceeding','upload','source_indexed','placed','legacy/'||name||'.pdf','a1400000-0000-0000-0000-000000000001');
    INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES(asset_id,'b1400000-0000-0000-0000-000000000001','documents','orgs/b1400000-0000-0000-0000-000000000001/assets/'||asset_id||'/original.pdf',encode(digest(document_id::text,'sha256'),'hex'),100+pos,'application/pdf','available',now(),2,'a1400000-0000-0000-0000-000000000001');
    INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by)
    VALUES(version_id,'b1400000-0000-0000-0000-000000000001',document_id,asset_id,CASE WHEN name='good' THEN 2 ELSE 1 END,name||'.pdf',2,'valid','current',now(),now(),'a1400000-0000-0000-0000-000000000001');
    UPDATE public.documents SET current_version_id=version_id WHERE id=document_id;
    INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,started_at,completed_at,lease_token,lease_expires_at,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version)
    VALUES(run_id,'b1400000-0000-0000-0000-000000000001',asset_id,'timeline.'||name,'timeline.'||name,'ai_extraction','validated','succeeded',now()-interval '2 minutes',now()-interval '1 minute',gen_random_uuid(),now()+interval '1 minute','fixture','fixture','fixture','fixture','fixture','fixture','fixture');
    IF name='good' THEN
      PERFORM public.materialize_source_field_candidate(run_id,'document.type','document.type','code','"OIO"'::jsonb,1,'OIO',NULL,.99,'eligible',NULL);
      PERFORM public.materialize_source_field_candidate(run_id,'document.reference','document.reference_number','text',to_jsonb(E'Ref %_\\ Mixed'::text),1,E'Ref %_\\ Mixed',NULL,.99,'eligible',NULL);
      PERFORM public.materialize_source_field_candidate(run_id,'document.date','document.date','date','"2026-07-15"'::jsonb,1,'2026-07-15',NULL,.99,'eligible',NULL);
      PERFORM public.materialize_source_field_candidate(run_id,'document.direction','document.direction','code','"outgoing"'::jsonb,1,'outgoing',NULL,.99,'eligible',NULL);
    ELSIF name IN ('rejected','cleared') THEN
      PERFORM public.materialize_source_field_candidate(run_id,'document.reference','document.reference_number','code',to_jsonb(upper(name)||'/1'),1,upper(name)||'/1',NULL,.99,'eligible',NULL);
    ELSIF name='ambiguous' THEN
      PERFORM public.materialize_source_field_candidate(run_id,'document.type.one','document.type','code','"SCN"'::jsonb,1,'SCN',NULL,.99,'eligible',NULL);
      PERFORM public.materialize_source_field_candidate(run_id,'document.type.two','document.type','code','"OIO"'::jsonb,1,'OIO',NULL,.99,'eligible',NULL);
    ELSIF name='wrongtype' THEN
      PERFORM public.materialize_source_field_candidate(run_id,'document.type','document.type','text','"Wrong type"'::jsonb,1,'Wrong type',NULL,.99,'eligible',NULL);
    ELSIF name='baddate' THEN
      PERFORM public.materialize_source_field_candidate(run_id,'document.date','document.date','code','"not-a-date"'::jsonb,1,'not-a-date',NULL,.99,'eligible',NULL);
    ELSE
      PERFORM public.materialize_source_field_candidate(run_id,'document.direction','document.direction','code','"sideways"'::jsonb,1,'sideways',NULL,.99,'eligible',NULL);
    END IF;
    PERFORM public.materialize_document_version_analysis(version_id,run_id,'placement','a1400000-0000-0000-0000-000000000001');
  END LOOP;

  -- A stale successful analysis exists, but the projection must use only the
  -- document's explicit current pointer.
  document_id := 'e1410000-0000-0000-0000-000000000001'; old_asset:=gen_random_uuid(); old_version:=gen_random_uuid(); old_run:=gen_random_uuid();
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES(old_asset,'b1400000-0000-0000-0000-000000000001','documents','orgs/b1400000-0000-0000-0000-000000000001/assets/'||old_asset||'/original.pdf',encode(digest('stale-'||document_id::text,'sha256'),'hex'),90,'application/pdf','available',now(),2,'a1400000-0000-0000-0000-000000000001');
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,superseded_at,created_by)
  VALUES(old_version,'b1400000-0000-0000-0000-000000000001',document_id,old_asset,1,'stale.pdf',2,'valid','superseded',now(),now()-interval '2 days',now()-interval '1 day','a1400000-0000-0000-0000-000000000001');
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,started_at,completed_at,lease_token,lease_expires_at,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version)
  VALUES(old_run,'b1400000-0000-0000-0000-000000000001',old_asset,'timeline.good.stale','timeline.good.stale','ai_extraction','validated','succeeded',now()-interval '2 days',now()-interval '2 days',gen_random_uuid(),now()+interval '1 minute','fixture','fixture','fixture','fixture','fixture','fixture','fixture');
  PERFORM public.materialize_source_field_candidate(old_run,'document.type','document.type','code','"STALE"'::jsonb,1,'STALE',NULL,.99,'eligible',NULL);
  PERFORM public.materialize_document_version_analysis(old_version,old_run,'replacement_history','a1400000-0000-0000-0000-000000000001');

  SELECT candidate.id INTO candidate_id FROM public.document_field_candidates AS candidate WHERE candidate.document_id='e1410000-0000-0000-0000-000000000001' AND candidate.semantic_candidate_key='document.direction';
  PERFORM public.record_document_field_decision(candidate_id,'corrected','"incoming"'::jsonb,'Correct fixture direction','a1400000-0000-0000-0000-000000000001','timeline-good-direction');
  SELECT candidate.id INTO candidate_id FROM public.document_field_candidates AS candidate WHERE candidate.document_id='e1410000-0000-0000-0000-000000000002' AND candidate.semantic_candidate_key='document.reference';
  PERFORM public.record_document_field_decision(candidate_id,'rejected',NULL,'Reject fixture reference','a1400000-0000-0000-0000-000000000001','timeline-rejected-reference');
  SELECT candidate.id INTO candidate_id FROM public.document_field_candidates AS candidate WHERE candidate.document_id='e1410000-0000-0000-0000-000000000003' AND candidate.semantic_candidate_key='document.reference';
  PERFORM public.record_document_field_decision(candidate_id,'cleared',NULL,'Clear fixture reference','a1400000-0000-0000-0000-000000000001','timeline-cleared-reference');
END $metadata_seed$;

-- Exercise all deferred document/version lifecycle checks after pointers and
-- version states have been assembled. No later fixture step needs deferral.
SET CONSTRAINTS ALL IMMEDIATE;

DO $acl$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid=procedure.pronamespace
    JOIN LATERAL aclexplode(coalesce(procedure.proacl,acldefault('f',procedure.proowner))) AS acl ON true
    WHERE namespace.nspname='public' AND procedure.proname='read_matter_timeline_chronology'
      AND acl.grantee=0 AND acl.privilege_type='EXECUTE'
  ) OR has_function_privilege('anon','public.read_matter_timeline_chronology(uuid,integer,integer,text[],uuid)','EXECUTE')
     OR has_function_privilege('service_role','public.read_matter_timeline_chronology(uuid,integer,integer,text[],uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.read_matter_timeline_chronology(uuid,integer,integer,text[],uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'chronology RPC ACL is unsafe';
  END IF;
END $acl$;

SET LOCAL ROLE anon;
DO $anon_denied$ DECLARE denied boolean:=false; BEGIN
  BEGIN PERFORM 1 FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[]::text[],NULL); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'anon executed chronology'; END IF;
END $anon_denied$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $service_denied$ DECLARE denied boolean:=false; BEGIN
  BEGIN PERFORM 1 FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[]::text[],NULL); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role executed chronology'; END IF;
END $service_denied$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);

DO $role_and_lineage$
DECLARE user_id uuid; result record; status_matter uuid;
BEGIN
  FOREACH user_id IN ARRAY ARRAY['a1400000-0000-0000-0000-000000000001'::uuid,'a1400000-0000-0000-0000-000000000002'::uuid,'a1400000-0000-0000-0000-000000000003'::uuid,'a1400000-0000-0000-0000-000000000004'::uuid] LOOP
    PERFORM set_config('request.jwt.claim.sub',user_id::text,true);
    SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[]::text[],NULL);
    IF result.outcome<>'ok' OR result.total<>1 THEN RAISE EXCEPTION 'authorised role failed %',user_id; END IF;
  END LOOP;
  FOREACH user_id IN ARRAY ARRAY['a1400000-0000-0000-0000-000000000005'::uuid,'a1400000-0000-0000-0000-000000000006'::uuid,'a1400000-0000-0000-0000-000000000007'::uuid,'a1400000-0000-0000-0000-000000000008'::uuid] LOOP
    PERFORM set_config('request.jwt.claim.sub',user_id::text,true);
    SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[]::text[],NULL);
    IF result.outcome<>'unavailable' OR result.total<>0 OR result.source_revision IS NOT NULL THEN RAISE EXCEPTION 'fail-closed identity failed %',user_id; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','a1400000-0000-0000-0000-000000000001',true);
  FOREACH status_matter IN ARRAY ARRAY['d1400000-0000-0000-0000-000000000901'::uuid,'d1400000-0000-0000-0000-000000000902'::uuid,'d1400000-0000-0000-0000-000000000903'::uuid,'d1400000-0000-0000-0000-000000000904'::uuid,'d1400000-0000-0000-0000-000000000905'::uuid,'d1400000-0000-0000-0000-000000000906'::uuid,'d1400000-0000-0000-0000-000000000907'::uuid] LOOP
    SELECT * INTO result FROM public.read_matter_timeline_chronology(status_matter,0,50,ARRAY[]::text[],NULL);
    IF result.outcome<>'ok' OR result.total<>1 THEN RAISE EXCEPTION 'readable work status rejected %',status_matter; END IF;
  END LOOP;
  FOREACH status_matter IN ARRAY ARRAY['d1400000-0000-0000-0000-000000000908'::uuid,'d1400000-0000-0000-0000-000000000909'::uuid,'d1400000-0000-0000-0000-000000000999'::uuid] LOOP
    SELECT * INTO result FROM public.read_matter_timeline_chronology(status_matter,0,50,ARRAY[]::text[],NULL);
    IF result.outcome<>'unavailable' THEN RAISE EXCEPTION 'matter/client/tenant lineage leaked %',status_matter; END IF;
  END LOOP;
END $role_and_lineage$;

DO $paging_and_selection$
DECLARE result record; repeated jsonb; selected_id uuid:='e2500000-0000-0000-0000-000000000250';
BEGIN
  IF (SELECT total FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000000',999,50,ARRAY[]::text[],NULL))<>0
     OR (SELECT "offset" FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000000',999,50,ARRAY[]::text[],NULL))<>0 THEN RAISE EXCEPTION 'empty total/offset'; END IF;
  IF (SELECT total FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[]::text[],NULL))<>1
     OR (SELECT total FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000050',0,50,ARRAY[]::text[],NULL))<>50
     OR (SELECT total FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000100',0,100,ARRAY[]::text[],NULL))<>100
     OR (SELECT total FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000250',0,100,ARRAY[]::text[],NULL))<>250 THEN RAISE EXCEPTION 'exact paging totals'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000250',999,100,ARRAY[]::text[],selected_id);
  IF result."offset"<>200 OR jsonb_array_length(result.items)<>50 OR result.selected->>'id'<>selected_id::text OR (result.items->49->>'effectiveDate') IS NOT NULL THEN RAISE EXCEPTION 'stale paging, off-page selection, or undated-last'; END IF;
  repeated:=result.items;
  IF repeated IS DISTINCT FROM (SELECT items FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000250',999,100,ARRAY[]::text[],selected_id)) THEN RAISE EXCEPTION 'stable ordering'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000250',0,50,ARRAY['q:no-match']::text[],selected_id);
  IF result.total<>0 OR result."offset"<>0 OR result.selected->>'id'<>selected_id::text THEN RAISE EXCEPTION 'filtered off-page selection'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000250',0,50,ARRAY[]::text[],'e1400000-0000-0000-0000-000000000004');
  IF result.selected IS NOT NULL THEN RAISE EXCEPTION 'foreign selection leaked'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,50,ARRAY[]::text[],'e0010000-0000-0000-0000-000000000001');
  IF result.selected IS NOT NULL THEN RAISE EXCEPTION 'same-org cross-matter selection leaked'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,50,ARRAY[]::text[],'e1400000-0000-0000-0000-000000000003');
  IF result.selected IS NOT NULL THEN RAISE EXCEPTION 'wrong-class supporting selection leaked'; END IF;
END $paging_and_selection$;

DO $filters_and_metadata$
DECLARE result record; item jsonb;
BEGIN
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY['q:%']::text[],NULL); IF result.total<>1 THEN RAISE EXCEPTION 'literal percent search'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY['q:_']::text[],NULL); IF result.total<>1 THEN RAISE EXCEPTION 'literal underscore search'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[E'q:\\']::text[],NULL); IF result.total<>1 THEN RAISE EXCEPTION 'literal backslash search'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY['q:mixed case','type:notice','incoming','undated','attention:pdf-not-attached']::text[],NULL); IF result.total<>1 THEN RAISE EXCEPTION 'q/type/direction/date presence/attention filters'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY['q:notice']::text[],NULL); IF result.total<>0 THEN RAISE EXCEPTION 'q searched document type'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY['from:2026-01-01','to:2026-12-31']::text[],NULL); IF result.total<>0 THEN RAISE EXCEPTION 'date range must exclude undated'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY['from:2026-07-01','to:2026-07-31']::text[],NULL); IF result.total<>1 OR result.items->0->>'effectiveDate'<>'2026-07-15' THEN RAISE EXCEPTION 'positive effective date range'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY['attention:processing']::text[],NULL);
  IF result.total<>3
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result.items) value WHERE value->>'id'='e1400000-0000-0000-0000-000000000011' AND value->>'attentionState'='processing')
     OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result.items) value WHERE value->>'id'='e1400000-0000-0000-0000-000000000012' AND value->>'attentionState'='processing') THEN RAISE EXCEPTION 'processing/uploaded/pending-placement mapping'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY['attention:review']::text[],NULL); IF result.total<>1 THEN RAISE EXCEPTION 'review filter'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY['attention:failed']::text[],NULL); IF result.total<>1 THEN RAISE EXCEPTION 'failed filter'; END IF;
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY['attention:pdf-not-attached']::text[],NULL);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(result.items) value WHERE value->>'contentAvailability'<>'metadata_only') OR result.total<>7 THEN RAISE EXCEPTION 'PDF-not-attached exact availability'; END IF;

  SELECT selected INTO item FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000001');
  IF item->>'documentType'<>'OIO' OR item->>'referenceNumber'<>E'Ref %_\\ Mixed' OR item->>'effectiveDate'<>'2026-07-15' OR item->>'direction'<>'incoming' THEN RAISE EXCEPTION 'current corrected effective metadata'; END IF;
  FOREACH item IN ARRAY ARRAY[
    (SELECT selected FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000002')),
    (SELECT selected FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000003'))
  ] LOOP IF item->>'referenceNumber' IS NOT NULL THEN RAISE EXCEPTION 'rejected/cleared fallback'; END IF; END LOOP;
  SELECT selected INTO item FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000004'); IF item->>'documentType' IS NOT NULL THEN RAISE EXCEPTION 'ambiguous metadata'; END IF;
  SELECT selected INTO item FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000005'); IF item->>'documentType' IS NOT NULL THEN RAISE EXCEPTION 'wrong typed metadata'; END IF;
  SELECT selected INTO item FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000006'); IF item->>'effectiveDate' IS NOT NULL THEN RAISE EXCEPTION 'malformed date metadata'; END IF;
  SELECT selected INTO item FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000007'); IF item->>'direction' IS NOT NULL THEN RAISE EXCEPTION 'malformed direction metadata'; END IF;
  SELECT selected INTO item FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1400000-0000-0000-0000-000000000002'); IF item->>'documentType' IS NOT NULL OR item->>'referenceNumber' IS NOT NULL OR item->>'effectiveDate' IS NOT NULL OR item->>'direction' IS NOT NULL THEN RAISE EXCEPTION 'attached record fell back to legacy fields'; END IF;
END $filters_and_metadata$;

DO $invalid_filters$
DECLARE result record; filters text[]; filter_value text;
BEGIN
  FOREACH filters SLICE 1 IN ARRAY ARRAY[
    ARRAY['bad-filter','incoming'], ARRAY['incoming','outgoing'], ARRAY['dated','undated'], ARRAY['incoming','incoming'],
    ARRAY['q:one','q:two'], ARRAY['type:one','type:two'], ARRAY['attention:review','attention:failed'],
    ARRAY['from:2026-01-01','from:2026-02-01'], ARRAY['to:2026-01-01','to:2026-02-01'],
    ARRAY['from:2026-03-01','to:2026-02-01'], ARRAY['from:2026-02-30','incoming'], ARRAY['to:2026-02-30','incoming'],
    ARRAY['q:'||repeat('q',79),'incoming'], ARRAY['type:'||repeat('t',76),'incoming'],
    ARRAY['q: leading','dated'], ARRAY['q:trailing ','dated'], ARRAY['type: leading','dated'], ARRAY['type:trailing ','dated'],
    ARRAY[E'q:line\nbreak','dated'], ARRAY[E'type:tab\tvalue','dated']
  ] LOOP
    SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,filters,NULL);
    IF result.outcome<>'unavailable' OR result.total<>0 THEN RAISE EXCEPTION 'invalid filter accepted %',filters; END IF;
  END LOOP;
  SELECT * INTO result FROM public.read_matter_timeline_chronology(
    'd1400000-0000-0000-0000-000000000001',0,50,
    ARRAY[['incoming','dated'],['outgoing','undated']]::text[],NULL
  );
  IF result.outcome<>'unavailable' OR result.total<>0 THEN RAISE EXCEPTION 'multidimensional filter array accepted'; END IF;
  FOREACH filter_value IN ARRAY ARRAY['q:'||repeat('q',75),'q:'||repeat('q',76),'q:'||repeat('q',78),'type:'||repeat('t',75)] LOOP
    SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[filter_value],NULL);
    IF result.outcome<>'ok' THEN RAISE EXCEPTION 'valid boundary rejected %',filter_value; END IF;
  END LOOP;
END $invalid_filters$;

DO $safe_shape_and_revision$
DECLARE result record; stable_revision text; changed_revision text; stable_item_revision text; changed_item_revision text; item jsonb; keys text[]; selection_keys text[];
BEGIN
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000001');
  stable_revision:=result.source_revision;
  stable_item_revision:=result.selected->>'revision';
  IF stable_revision IS NULL OR stable_revision IS DISTINCT FROM (SELECT source_revision FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000001')) THEN RAISE EXCEPTION 'stable non-null source revision'; END IF;
  SELECT array_agg(key ORDER BY key) INTO keys FROM jsonb_object_keys(result.items->0) key;
  SELECT array_agg(key ORDER BY key) INTO selection_keys FROM jsonb_object_keys(result.selected) key;
  IF keys IS DISTINCT FROM ARRAY['attentionState','classificationState','contentAvailability','direction','documentType','effectiveDate','id','referenceNumber','revision','title']
     OR selection_keys IS DISTINCT FROM keys THEN RAISE EXCEPTION 'unsafe chronology JSON shape'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(result.items) value WHERE value->>'revision' IS NULL) OR result.selected->>'revision' IS NULL THEN RAISE EXCEPTION 'item revision missing'; END IF;
  RESET ROLE;
  UPDATE public.documents SET lifecycle_revision=lifecycle_revision+1 WHERE id='e1410000-0000-0000-0000-000000000001';
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claim.role','authenticated',true); PERFORM set_config('request.jwt.claim.sub','a1400000-0000-0000-0000-000000000001',true);
  SELECT source_revision,selected->>'revision' INTO changed_revision,changed_item_revision FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000900',0,100,ARRAY[]::text[],'e1410000-0000-0000-0000-000000000001');
  IF changed_revision IS NULL OR changed_revision=stable_revision OR changed_item_revision IS NULL OR changed_item_revision=stable_item_revision THEN RAISE EXCEPTION 'source/item revision did not change with lifecycle'; END IF;
END $safe_shape_and_revision$;
RESET ROLE;

-- Last: simulate restored/import corruption that the production unique index
-- prevents. The authority reader and chronology must still fail closed.
DROP INDEX public.organisation_memberships_one_current_org_per_user;
INSERT INTO public.organisation_memberships(id,org_id,user_id,role,state,generation,joined_at) VALUES
  ('a1490000-0000-0000-0000-000000000001','b1400000-0000-0000-0000-000000000001','a1400000-0000-0000-0000-000000000009','viewer','active',1,now()),
  ('a1490000-0000-0000-0000-000000000002','b1400000-0000-0000-0000-000000000002','a1400000-0000-0000-0000-000000000009','viewer','active',1,now());
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub','a1400000-0000-0000-0000-000000000009',true);
DO $duplicate_current_denied$ DECLARE result record; BEGIN
  SELECT * INTO result FROM public.read_matter_timeline_chronology('d1400000-0000-0000-0000-000000000001',0,50,ARRAY[]::text[],NULL);
  IF result.outcome<>'unavailable' OR result.total<>0 THEN RAISE EXCEPTION 'duplicate current membership retained chronology authority'; END IF;
END $duplicate_current_denied$;
RESET ROLE;

ROLLBACK;
