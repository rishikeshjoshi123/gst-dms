-- Run after migration 00091 on a disposable local database. All fixture data
-- rolls back. Covers tenant/capability/recent-auth/fingerprint/blocker gates,
-- shared assets, durable leases, idempotent storage completion, and tombstones.
BEGIN;

DO $fixture$
DECLARE
  org uuid:='98000000-0000-0000-0000-000000000001'; other_org uuid:='98000000-0000-0000-0000-000000000002';
  owner uuid:='98100000-0000-0000-0000-000000000001'; associate_user uuid:='98100000-0000-0000-0000-000000000002';
  viewer_user uuid:='98100000-0000-0000-0000-000000000003'; other_owner uuid:='98100000-0000-0000-0000-000000000004';
  client uuid:='98200000-0000-0000-0000-000000000001'; matter uuid:='98300000-0000-0000-0000-000000000001';
  unique_doc uuid:='98400000-0000-0000-0000-000000000001'; shared_doc uuid:='98400000-0000-0000-0000-000000000002';
  surviving_doc uuid:='98400000-0000-0000-0000-000000000003'; blocked_doc uuid:='98400000-0000-0000-0000-000000000004';
  referenced_doc uuid:='98400000-0000-0000-0000-000000000006'; race_doc uuid:='98400000-0000-0000-0000-000000000007';
  retry_doc uuid:='98400000-0000-0000-0000-000000000008'; legacy_doc uuid:='98400000-0000-0000-0000-000000000009';
  legacy_client uuid:='98200000-0000-0000-0000-000000000009'; legacy_matter uuid:='98300000-0000-0000-0000-000000000009';
  other_client uuid:='98200000-0000-0000-0000-000000000002'; other_matter uuid:='98300000-0000-0000-0000-000000000002';
  other_doc uuid:='98400000-0000-0000-0000-000000000005';
  wiki_client uuid:='98200000-0000-0000-0000-000000000010'; wiki_matter uuid:='98300000-0000-0000-0000-000000000010';
  wiki_doc uuid:='98400000-0000-0000-0000-000000000010'; wiki_operation uuid;
  unique_asset uuid:='98500000-0000-0000-0000-000000000001'; shared_asset uuid:='98500000-0000-0000-0000-000000000002';
  referenced_asset uuid:='98500000-0000-0000-0000-000000000003'; provenance_run uuid:='98900000-0000-0000-0000-000000000001';
  provenance_successor uuid:='98900000-0000-0000-0000-000000000004';
  unbound_run uuid:='98900000-0000-0000-0000-000000000002'; shared_reference uuid:='98900000-0000-0000-0000-000000000003';
  membership uuid; unique_operation uuid; shared_operation uuid; blocked_operation uuid; other_operation uuid;
  referenced_operation uuid; race_operation uuid; retry_operation uuid; legacy_operation uuid; candidate_id uuid;
  impact record; result record; job record; deletion record; denied boolean;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  VALUES
    ('00000000-0000-0000-0000-000000000000',owner,'authenticated','authenticated','purge-owner@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',associate_user,'authenticated','authenticated','purge-associate@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',viewer_user,'authenticated','authenticated','purge-viewer@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',other_owner,'authenticated','authenticated','purge-other@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Purge fixture',owner),(other_org,'Other purge fixture',other_owner);
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=org AND user_id=owner;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=org;
  SELECT id INTO membership FROM public.organisation_memberships WHERE org_id=other_org AND user_id=other_owner;
  UPDATE public.organisations SET owner_membership_id=membership WHERE id=other_org;
  INSERT INTO public.organisation_memberships(org_id,user_id,role,state,generation,joined_by)
    VALUES(org,associate_user,'associate','active',1,owner),(org,viewer_user,'viewer','active',1,owner);
  INSERT INTO public.clients(id,org_id,name,gstin,pan) VALUES
    (client,org,'Purge client','27PPPPP0000P1Z5','PPPPP0000P'),
    (legacy_client,org,'Legacy client',NULL,NULL),
    (wiki_client,org,'Wiki client',NULL,NULL),
    (other_client,other_org,'Other purge client','27QQQQQ0000Q1Z5','QQQQQ0000Q');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES
    (matter,org,client,'Purge matter','PURGE-01'),(legacy_matter,org,legacy_client,'Legacy matter','LEGACY-01'),
    (wiki_matter,org,wiki_client,'Wiki matter','WIKI-01'),
    (other_matter,other_org,other_client,'Other matter','OTHER-01');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title) VALUES
    (unique_doc,org,matter,'fixture/unique.pdf',owner,'Unique document'),
    (shared_doc,org,matter,'fixture/shared.pdf',owner,'Shared document'),
    (surviving_doc,org,matter,'fixture/shared.pdf',owner,'Surviving document'),
    (blocked_doc,org,matter,'fixture/blocked.pdf',owner,'Blocked document'),
    (referenced_doc,org,matter,'fixture/referenced.pdf',owner,'Referenced document'),
    (race_doc,org,matter,'fixture/race.pdf',owner,'Race document'),
    (retry_doc,org,matter,'fixture/retry.pdf',owner,'Retry document'),
    (legacy_doc,org,legacy_matter,'fixture/legacy.pdf',owner,'Legacy supporting root'),
    (wiki_doc,org,wiki_matter,'fixture/wiki.pdf',owner,'Wiki purge document'),
    (other_doc,other_org,other_matter,'fixture/other.pdf',other_owner,'Other document');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by) VALUES
    (unique_asset,org,'documents','orgs/98000000-0000-0000-0000-000000000001/assets/98500000-0000-0000-0000-000000000001/original.pdf',repeat('a',64),100,'application/pdf','available',now(),1,owner),
    (shared_asset,org,'documents','orgs/98000000-0000-0000-0000-000000000001/assets/98500000-0000-0000-0000-000000000002/original.pdf',repeat('b',64),200,'application/pdf','available',now(),1,owner),
    (referenced_asset,org,'documents','orgs/98000000-0000-0000-0000-000000000001/assets/98500000-0000-0000-0000-000000000003/original.pdf',repeat('c',64),300,'application/pdf','available',now(),1,owner);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,validation_state,state,validated_at,promoted_at,created_by) VALUES
    ('98600000-0000-0000-0000-000000000001',org,unique_doc,unique_asset,1,'unique.pdf',1,'valid','current',now(),now(),owner),
    ('98600000-0000-0000-0000-000000000002',org,shared_doc,shared_asset,1,'shared.pdf',1,'valid','current',now(),now(),owner),
    ('98600000-0000-0000-0000-000000000003',org,surviving_doc,shared_asset,1,'shared.pdf',1,'valid','current',now(),now(),owner),
    ('98600000-0000-0000-0000-000000000004',org,referenced_doc,referenced_asset,1,'referenced.pdf',1,'valid','current',now(),now(),owner);
  UPDATE public.documents SET current_version_id=CASE id WHEN unique_doc THEN '98600000-0000-0000-0000-000000000001'::uuid WHEN shared_doc THEN '98600000-0000-0000-0000-000000000002'::uuid WHEN surviving_doc THEN '98600000-0000-0000-0000-000000000003'::uuid WHEN referenced_doc THEN '98600000-0000-0000-0000-000000000004'::uuid END
    WHERE id IN (unique_doc,shared_doc,surviving_doc,referenced_doc);
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,started_at,completed_at,lease_token,lease_expires_at,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,superseded_by_run_id) VALUES
    (provenance_successor,org,unique_asset,'purge.provenance.successor','purge.provenance.successor','ai_extraction','validated','succeeded',now()-interval '30 seconds',now(),gen_random_uuid(),now()+interval '1 minute','fixture','fixture','fixture','fixture','fixture','fixture','fixture',NULL),
    (unbound_run,org,referenced_asset,'purge.unbound','purge.unbound','ai_extraction','validated','succeeded',now()-interval '1 minute',now(),gen_random_uuid(),now()+interval '1 minute','fixture','fixture','fixture','fixture','fixture','fixture','fixture',NULL);
  INSERT INTO public.source_analysis_runs(id,org_id,asset_id,request_key,idempotency_key,analysis_kind,analysis_state,state,started_at,completed_at,lease_token,lease_expires_at,provider,model_identifier,model_config_version,prompt_version,schema_version,catalogue_version,normalizer_version,superseded_by_run_id)
    VALUES(provenance_run,org,unique_asset,'purge.provenance','purge.provenance','ai_extraction','validated','succeeded',now()-interval '1 minute',now(),gen_random_uuid(),now()+interval '1 minute','fixture','fixture','fixture','fixture','fixture','fixture','fixture',provenance_successor);
  -- Establish an immutable terminal supersession chain at INSERT time. Purge
  -- must delete it in FK-safe order without rewriting either terminal row.
  PERFORM public.materialize_source_field_candidate(provenance_run,'document.reference','document.reference_number','code','"PURGE/1"'::jsonb,1,'Purge reference',NULL,0.99,'eligible',NULL);
  PERFORM public.materialize_document_version_analysis('98600000-0000-0000-0000-000000000001',provenance_run,'purge_fixture',owner);
  PERFORM public.materialize_document_version_analysis('98600000-0000-0000-0000-000000000001',provenance_successor,'purge_fixture_successor',owner);
  IF (SELECT count(*) FROM public.document_version_analysis_bindings WHERE document_version_id='98600000-0000-0000-0000-000000000001')<>2 THEN
    RAISE EXCEPTION 'binding fixture did not create the governed document-version delete path'; END IF;
  SELECT id INTO candidate_id FROM public.document_field_candidates WHERE document_id=unique_doc LIMIT 1;
  PERFORM public.record_document_field_decision(candidate_id,'accepted',NULL,'Purge fixture decision',owner,'purge.fixture.decision');
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES(shared_reference,org,referenced_asset,'referenced.pdf','application/pdf',300,'finalized',owner,now(),now());
  denied:=false; BEGIN DELETE FROM public.source_field_candidates WHERE source_analysis_run_id=provenance_run; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary source candidate delete bypassed immutability'; END IF;
  denied:=false; BEGIN DELETE FROM public.document_field_candidates WHERE document_id=unique_doc; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary document candidate delete bypassed immutability'; END IF;
  denied:=false; BEGIN DELETE FROM public.document_field_decisions WHERE document_id=unique_doc; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary provenance decision delete bypassed immutability'; END IF;
  denied:=false; BEGIN UPDATE public.source_analysis_runs SET safe_error_code='direct_mutation' WHERE id=unbound_run; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary terminal provenance mutation bypassed immutability'; END IF;
  denied:=false; BEGIN DELETE FROM public.source_analysis_runs WHERE id=unbound_run; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary provenance run delete bypassed lifecycle fence'; END IF;
  denied:=false; BEGIN DELETE FROM public.documents WHERE id=unique_doc; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'direct document hard delete bypassed Trash lifecycle'; END IF;
  denied:=false; BEGIN DELETE FROM public.matters WHERE id=matter; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'direct matter hard delete bypassed Trash lifecycle'; END IF;
  denied:=false; BEGIN DELETE FROM public.clients WHERE id=client; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'direct client hard delete bypassed Trash lifecycle'; END IF;
  INSERT INTO public.case_notes(id,matter_id,document_id,org_id,author_id,content) VALUES
    ('98700000-0000-0000-0000-000000000001',matter,unique_doc,org,owner,'content that must be removed');
  denied:=false; BEGIN DELETE FROM public.case_notes WHERE document_id=unique_doc; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary dependent delete bypassed the governed purge fence'; END IF;
  INSERT INTO public.wiki_sections(id,matter_id,section_key,title,content) VALUES
    ('98700000-0000-0000-0000-000000000010',wiki_matter,'purge','Purge wiki','{}');
  INSERT INTO public.wiki_section_versions(id,wiki_section_id,content,generated_by) VALUES
    ('98700000-0000-0000-0000-000000000011','98700000-0000-0000-0000-000000000010','{}','fixture');
  denied:=false; BEGIN DELETE FROM public.wiki_sections WHERE id='98700000-0000-0000-0000-000000000010'; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'ordinary wiki delete bypassed the governed purge fence'; END IF;

  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT operation_id INTO unique_operation FROM public.trash_resource('document',unique_doc,'purge.fixture.unique');
  SELECT operation_id INTO shared_operation FROM public.trash_resource('document',shared_doc,'purge.fixture.shared');
  SELECT operation_id INTO blocked_operation FROM public.trash_resource('document',blocked_doc,'purge.fixture.blocked');
  SELECT operation_id INTO referenced_operation FROM public.trash_resource('document',referenced_doc,'purge.fixture.referenced');
  SELECT operation_id INTO race_operation FROM public.trash_resource('document',race_doc,'purge.fixture.race');
  SELECT operation_id INTO retry_operation FROM public.trash_resource('document',retry_doc,'purge.fixture.retry');
  SELECT operation_id INTO legacy_operation FROM public.trash_resource('matter',legacy_matter,'purge.fixture.legacy');
  SELECT operation_id INTO wiki_operation FROM public.trash_resource('matter',wiki_matter,'purge.fixture.wiki');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',other_owner::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',other_owner::text,true);
  SELECT operation_id INTO other_operation FROM public.trash_resource('document',other_doc,'purge.fixture.other');

  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  IF EXISTS (SELECT 1 FROM public.get_trash_purge_impact(other_operation)) THEN RAISE EXCEPTION 'cross-tenant impact disclosed'; END IF;
  SELECT * INTO impact FROM public.get_trash_purge_impact(wiki_operation);
  SELECT * INTO result FROM public.confirm_trash_purge(wiki_operation,impact.impact_fingerprint,'WIKI-01','purge.fixture.wiki');
  IF result.code<>'queued' THEN RAISE EXCEPTION 'wiki purge did not queue: %',result.code; END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=wiki_operation;
  SELECT * INTO result FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF result.code<>'prepared' OR EXISTS (SELECT 1 FROM public.wiki_sections WHERE matter_id=wiki_matter)
     OR EXISTS (SELECT 1 FROM public.wiki_section_versions WHERE wiki_section_id='98700000-0000-0000-0000-000000000010') THEN
    RAISE EXCEPTION 'fenced wiki purge did not explicitly clean the wiki/version dependency'; END IF;
  SELECT * INTO result FROM public.finish_trash_purge_attempt(job.job_id,job.lease_token);
  IF result.code<>'purged' THEN RAISE EXCEPTION 'fenced wiki purge did not finish'; END IF;
  SELECT * INTO impact FROM public.get_trash_purge_impact(shared_operation);
  IF impact.unique_bytes<>0 OR impact.shared_bytes_retained<>200 OR NOT impact.can_purge THEN RAISE EXCEPTION 'shared asset impact was unsafe'; END IF;
  SELECT * INTO impact FROM public.get_trash_purge_impact(referenced_operation);
  IF impact.unique_bytes<>0 OR impact.shared_bytes_retained<>300 THEN
    RAISE EXCEPTION 'source-analysis/upload-session surviving references were omitted from impact';
  END IF;

  INSERT INTO public.resource_holds(org_id,resource_type,resource_id,client_id,scope,reason,created_by)
    VALUES(org,'client',client,client,'subtree','Client subtree hold',owner);
  SELECT * INTO impact FROM public.get_trash_purge_impact(unique_operation);
  IF impact.hold_count<>1 OR impact.can_purge THEN RAISE EXCEPTION 'Client subtree hold did not block descendant document root'; END IF;
  UPDATE public.resource_holds SET state='released',released_at=now() WHERE org_id=org AND reason='Client subtree hold';
  INSERT INTO public.resource_holds(org_id,resource_type,resource_id,client_id,scope,reason,created_by)
    VALUES(org,'client',client,client,'resource','Client exact-only hold',owner);
  SELECT * INTO impact FROM public.get_trash_purge_impact(unique_operation);
  IF impact.hold_count<>0 THEN RAISE EXCEPTION 'Client resource-only hold incorrectly blocked a descendant root'; END IF;
  INSERT INTO public.resource_holds(org_id,resource_type,resource_id,matter_id,scope,reason,created_by)
    VALUES(org,'matter',matter,matter,'subtree','Matter subtree hold',owner);
  SELECT * INTO impact FROM public.get_trash_purge_impact(unique_operation);
  IF impact.hold_count<>1 OR impact.can_purge THEN RAISE EXCEPTION 'Matter subtree hold did not block descendant document root'; END IF;
  UPDATE public.resource_holds SET state='released',released_at=now() WHERE org_id=org AND reason='Matter subtree hold';

  INSERT INTO public.resource_holds(org_id,resource_type,resource_id,document_id,reason,created_by)
    VALUES(org,'document',blocked_doc,blocked_doc,'Fixture legal hold',owner);
  PERFORM public.register_trash_purge_blocker(blocked_operation,'document',blocked_doc,'active_export',gen_random_uuid(),true);
  SELECT * INTO impact FROM public.get_trash_purge_impact(blocked_operation);
  IF impact.can_purge OR impact.hold_count<>1 OR impact.active_export_count<>1 OR impact.blocker_count<>2 THEN
    RAISE EXCEPTION 'hold/export blockers did not block whole operation';
  END IF;
  PERFORM public.register_trash_purge_blocker(blocked_operation,'document',blocked_doc,'active_backup',
    '98900000-0000-0000-0000-000000000099',true);
  PERFORM public.register_trash_purge_blocker(shared_operation,'document',shared_doc,'active_backup',
    '98900000-0000-0000-0000-000000000099',true);
  IF (SELECT count(*) FROM public.trash_purge_blockers WHERE opaque_reference='98900000-0000-0000-0000-000000000099')<>2
     OR NOT EXISTS (SELECT 1 FROM public.trash_purge_blockers WHERE operation_id=blocked_operation AND state='active') THEN
    RAISE EXCEPTION 'one external blocker reference moved between root operations';
  END IF;
  PERFORM public.register_trash_purge_blocker(shared_operation,'document',shared_doc,'active_backup',
    '98900000-0000-0000-0000-000000000099',false);

  INSERT INTO public.supporting_documents(id,matter_id,org_id,title,storage_path,created_by)
    VALUES('98900000-0000-0000-0000-000000000098',legacy_matter,org,'Legacy dependency','legacy/private.pdf',owner);
  denied:=false; BEGIN DELETE FROM public.supporting_documents WHERE id='98900000-0000-0000-0000-000000000098'; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'direct legacy supporting-document delete bypassed lifecycle guard'; END IF;
  SELECT * INTO impact FROM public.get_trash_purge_impact(legacy_operation);
  IF impact.can_purge OR impact.blocker_count<>1
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(impact.blockers) blocker WHERE blocker->>'code'='platform_dependency') THEN
    RAISE EXCEPTION 'legacy supporting document did not fail closed';
  END IF;
  SELECT * INTO result FROM public.confirm_trash_purge(legacy_operation,impact.impact_fingerprint,'LEGACY-01','purge.fixture.legacy');
  IF result.code<>'blocked' OR NOT EXISTS (SELECT 1 FROM public.supporting_documents WHERE id='98900000-0000-0000-0000-000000000098') THEN
    RAISE EXCEPTION 'legacy supporting document was removed or failed to block';
  END IF;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',associate_user::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',associate_user::text,true);
  SELECT * INTO impact FROM public.get_trash_purge_impact(unique_operation);
  IF impact.can_purge THEN RAISE EXCEPTION 'Associate received purge authority'; END IF;
  SELECT * INTO result FROM public.confirm_trash_purge(unique_operation,impact.impact_fingerprint,'Unique document','purge.fixture.associate');
  IF result.code<>'not_allowed' THEN RAISE EXCEPTION 'Associate confirmed purge'; END IF;

  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner::text,'iat',extract(epoch FROM now()-interval '11 minutes')::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT * INTO impact FROM public.get_trash_purge_impact(unique_operation);
  SELECT * INTO result FROM public.confirm_trash_purge(unique_operation,impact.impact_fingerprint,'Unique document','purge.fixture.old-auth');
  IF result.code<>'recent_auth_required' THEN RAISE EXCEPTION 'stale authentication was accepted'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  SELECT * INTO result FROM public.confirm_trash_purge(unique_operation,repeat('0',64),'Unique document','purge.fixture.stale-impact');
  IF result.code<>'stale_impact' THEN RAISE EXCEPTION 'stale impact was accepted'; END IF;
  SELECT * INTO impact FROM public.get_trash_purge_impact(unique_operation);
  SELECT * INTO result FROM public.confirm_trash_purge(unique_operation,impact.impact_fingerprint,'wrong','purge.fixture.wrong-text');
  IF result.code<>'confirmation_mismatch' THEN RAISE EXCEPTION 'wrong confirmation was accepted'; END IF;
  SELECT * INTO result FROM public.confirm_trash_purge(unique_operation,impact.impact_fingerprint,'Unique document','purge.fixture.unique');
  IF result.code<>'queued' THEN RAISE EXCEPTION 'valid permanent delete was not queued: %',result.code; END IF;
  SELECT * INTO result FROM public.confirm_trash_purge(unique_operation,impact.impact_fingerprint,'Unique document','purge.fixture.unique');
  IF result.code<>'queued' THEN RAISE EXCEPTION 'same command replay changed its receipt'; END IF;
  SELECT * INTO result FROM public.confirm_trash_purge(shared_operation,(SELECT impact_fingerprint FROM public.get_trash_purge_impact(shared_operation)),'Shared document','purge.fixture.unique');
  IF result.code<>'not_available' THEN RAISE EXCEPTION 'cross-subject idempotency reuse was accepted'; END IF;

  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=unique_operation;
  IF job.job_id IS NULL OR (SELECT record_state::text FROM public.documents WHERE id=unique_doc)<>'purging' THEN RAISE EXCEPTION 'purge did not fence root lifecycle'; END IF;
  UPDATE public.trash_purge_jobs SET lease_expires_at=now()-interval '1 second' WHERE id=job.job_id;
  INSERT INTO public.trash_purge_execution_fences(transaction_id,job_id) VALUES(txid_current(),job.job_id);
  denied:=false; BEGIN DELETE FROM public.case_notes WHERE document_id=unique_doc; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'expired worker fence retained dependent-delete authority'; END IF;
  DELETE FROM public.trash_purge_execution_fences WHERE transaction_id=txid_current() AND job_id=job.job_id;
  SELECT * INTO result FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF result.code<>'stale_lease' THEN RAISE EXCEPTION 'expired worker lease retained authority'; END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=unique_operation;
  IF job.job_id IS NULL OR (SELECT attempt_count FROM public.trash_purge_jobs WHERE id=job.job_id)<>2 THEN
    RAISE EXCEPTION 'expired job lease was not safely recovered';
  END IF;
  SELECT * INTO result FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF result.code<>'prepared' OR result.storage_deletion_count<>1 OR EXISTS (SELECT 1 FROM public.case_notes WHERE document_id=unique_doc) THEN
    RAISE EXCEPTION 'database dependency cleanup was incomplete: code=%, storage=%, case_note=%',
      result.code,result.storage_deletion_count,EXISTS (SELECT 1 FROM public.case_notes WHERE document_id=unique_doc);
  END IF;
  IF EXISTS (SELECT 1 FROM public.document_field_decisions WHERE document_id=unique_doc)
     OR EXISTS (SELECT 1 FROM public.document_field_candidates WHERE document_id=unique_doc)
     OR EXISTS (SELECT 1 FROM public.document_version_analysis_bindings WHERE document_id=unique_doc)
     OR EXISTS (SELECT 1 FROM public.source_field_candidates WHERE source_analysis_run_id=provenance_run)
     OR EXISTS (SELECT 1 FROM public.source_analysis_runs WHERE id IN (provenance_run,provenance_successor)) THEN
    RAISE EXCEPTION 'normal fenced provenance purge did not complete';
  END IF;
  SELECT * INTO deletion FROM public.claim_trash_purge_storage_deletions(job.job_id,job.lease_token,25,120);
  SELECT * INTO result FROM public.finish_trash_purge_storage_deletion(deletion.deletion_id,deletion.lease_token,'deleted');
  IF result.code<>'deleted' THEN RAISE EXCEPTION 'storage completion failed'; END IF;
  SELECT * INTO result FROM public.finish_trash_purge_storage_deletion(deletion.deletion_id,deletion.lease_token,'deleted');
  IF result.code<>'already_deleted' THEN RAISE EXCEPTION 'storage completion replay was not idempotent'; END IF;
  SELECT * INTO result FROM public.finish_trash_purge_attempt(job.job_id,job.lease_token);
  IF result.code<>'purged' OR (SELECT record_state::text FROM public.documents WHERE id=unique_doc)<>'purged'
     OR (SELECT display_title FROM public.documents WHERE id=unique_doc) IS NOT NULL
     OR (SELECT reason FROM public.trash_operations WHERE id=unique_operation) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.file_assets WHERE id=unique_asset)
     OR NOT EXISTS (SELECT 1 FROM public.trash_purge_tombstones WHERE operation_id=unique_operation AND former_resource_id=unique_doc)
     OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='trash_purge_tombstones'
       AND column_name IN ('name','title','content','filename','storage_path','object_key','reference_number'))<>0 THEN
    RAISE EXCEPTION 'terminal purge or content-free tombstone contract failed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.file_assets WHERE id=shared_asset)
     OR NOT EXISTS (SELECT 1 FROM public.document_versions WHERE document_id=surviving_doc AND asset_id=shared_asset) THEN
    RAISE EXCEPTION 'shared surviving asset was removed';
  END IF;

  -- A blocker arriving after claim is rechecked before any content cleanup;
  -- the job becomes coherently recoverable and the blocker record survives.
  SELECT * INTO impact FROM public.get_trash_purge_impact(race_operation);
  SELECT * INTO result FROM public.confirm_trash_purge(race_operation,impact.impact_fingerprint,'Race document','purge.fixture.race');
  IF result.code<>'queued' THEN RAISE EXCEPTION 'race fixture did not queue'; END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=race_operation;
  PERFORM public.register_trash_purge_blocker(race_operation,'document',race_doc,'active_export',
    '98900000-0000-0000-0000-000000000097',true);
  SELECT * INTO result FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF result.code<>'blocked'
     OR (SELECT state::text FROM public.trash_purge_jobs WHERE id=job.job_id)<>'blocked'
     OR (SELECT state::text FROM public.trash_operations WHERE id=race_operation)<>'purge_failed'
     OR (SELECT display_title FROM public.documents WHERE id=race_doc)<>'Race document'
     OR NOT EXISTS (SELECT 1 FROM public.trash_purge_blockers WHERE operation_id=race_operation AND state='active') THEN
    RAISE EXCEPTION 'post-claim blocker bypassed atomic preparation check or stranded purging';
  END IF;

  -- Prepared retry exhaustion can be resumed only by a fresh authorised,
  -- current-impact command; retry receipts cannot be reused for another root.
  SELECT * INTO impact FROM public.get_trash_purge_impact(retry_operation);
  SELECT * INTO result FROM public.confirm_trash_purge(retry_operation,impact.impact_fingerprint,'Retry document','purge.fixture.retry');
  IF result.code<>'queued' THEN RAISE EXCEPTION 'retry fixture did not queue'; END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=retry_operation;
  SELECT * INTO result FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF result.code<>'prepared' THEN RAISE EXCEPTION 'retry fixture did not prepare'; END IF;
  SELECT * INTO result FROM public.register_trash_purge_blocker(retry_operation,'document',retry_doc,'active_export',gen_random_uuid(),true);
  IF result.code<>'not_available' THEN RAISE EXCEPTION 'blocker attached after irreversible database preparation'; END IF;
  denied:=false;
  BEGIN
    INSERT INTO public.resource_holds(org_id,resource_type,resource_id,matter_id,scope,reason,created_by)
      VALUES(org,'matter',matter,matter,'subtree','Late subtree hold',owner);
  EXCEPTION WHEN others THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'subtree hold writer bypassed prepared-operation fence'; END IF;
  UPDATE public.trash_purge_jobs SET state='blocked',attempt_count=20,lease_token=NULL,lease_expires_at=NULL,
    safe_error_code='retry_exhausted' WHERE id=job.job_id;
  UPDATE public.trash_operations SET state='purge_failed',purge_failed_at=now(),last_error_code='retry_exhausted' WHERE id=retry_operation;
  IF NOT EXISTS (SELECT 1 FROM public.get_trash_workspace(org,NULL,NULL,retry_operation,50) workspace
    WHERE workspace.row_kind='operation' AND workspace.operation_id=retry_operation) THEN
    RAISE EXCEPTION 'purge_failed operation disappeared from secured workspace';
  END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',viewer_user::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',viewer_user::text,true);
  SELECT * INTO impact FROM public.get_trash_purge_impact(retry_operation);
  IF impact.can_purge OR NOT EXISTS (SELECT 1 FROM public.get_trash_workspace(org,NULL,NULL,retry_operation,50) workspace
    WHERE workspace.row_kind='operation' AND workspace.operation_id=retry_operation) THEN
    RAISE EXCEPTION 'Viewer purge-failure visibility or capability was unsafe';
  END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',owner::text,'iat',extract(epoch FROM now())::bigint)::text,true);
  PERFORM set_config('request.jwt.claim.sub',owner::text,true);
  SELECT * INTO impact FROM public.get_trash_purge_impact(retry_operation);
  SELECT * INTO result FROM public.retry_trash_purge(retry_operation,repeat('0',64),'purge.fixture.retry.stale');
  IF result.code<>'stale_impact' THEN RAISE EXCEPTION 'stale prepared retry impact was accepted'; END IF;
  SELECT * INTO result FROM public.retry_trash_purge(retry_operation,impact.impact_fingerprint,'purge.fixture.retry.resume');
  IF result.code<>'retried' OR (SELECT attempt_count FROM public.trash_purge_jobs WHERE id=job.job_id)<>0 THEN
    RAISE EXCEPTION 'authorised prepared retry did not reset durable reconciliation';
  END IF;
  SELECT * INTO result FROM public.retry_trash_purge(race_operation,
    (SELECT impact_fingerprint FROM public.get_trash_purge_impact(race_operation)),'purge.fixture.retry.resume');
  IF result.code<>'not_available' THEN RAISE EXCEPTION 'retry idempotency key was reused across subjects'; END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=retry_operation;
  SELECT * INTO result FROM public.finish_trash_purge_attempt(job.job_id,job.lease_token);
  IF result.code<>'purged' THEN RAISE EXCEPTION 'retried prepared job did not finish'; END IF;
  SELECT * INTO result FROM public.retry_trash_purge(retry_operation,
    (SELECT impact_fingerprint FROM public.get_trash_purge_impact(retry_operation)),'purge.fixture.retry.terminal');
  IF result.code<>'not_available' THEN RAISE EXCEPTION 'terminal purged operation accepted retry'; END IF;

  UPDATE public.trash_operations SET auto_purge_enabled_snapshot=true,
    purge_eligible_at=now()-interval '1 second',auto_purge_at=now()-interval '1 second'
    WHERE id IN (shared_operation,blocked_operation);
  SELECT * INTO result FROM public.enqueue_due_trash_purges(100);
  IF result.queued_count<>1 OR result.blocked_count<>1
     OR NOT EXISTS (SELECT 1 FROM public.trash_purge_jobs WHERE operation_id=shared_operation
       AND source='retention_schedule' AND confirmed_by IS NULL)
     OR EXISTS (SELECT 1 FROM public.trash_purge_jobs WHERE operation_id=blocked_operation) THEN
    RAISE EXCEPTION 'scheduled purge did not share the manual blocker/workflow policy';
  END IF;
  SELECT * INTO job FROM public.claim_trash_purge_work(10,120) WHERE operation_id=shared_operation;
  SELECT * INTO result FROM public.prepare_trash_purge_database(job.job_id,job.lease_token);
  IF result.code<>'prepared' OR result.storage_deletion_count<>0 THEN RAISE EXCEPTION 'scheduled shared-asset preparation was unsafe'; END IF;
  SELECT * INTO result FROM public.finish_trash_purge_attempt(job.job_id,job.lease_token);
  IF result.code<>'purged' OR NOT EXISTS (SELECT 1 FROM public.file_assets WHERE id=shared_asset) THEN
    RAISE EXCEPTION 'scheduled purge did not use the durable terminal workflow';
  END IF;

  IF has_table_privilege('authenticated','public.trash_purge_jobs','SELECT')
     OR has_table_privilege('service_role','public.trash_purge_jobs','UPDATE')
     OR has_table_privilege('service_role','public.clients','DELETE')
     OR has_table_privilege('service_role','public.matters','DELETE')
     OR has_table_privilege('service_role','public.documents','DELETE')
     OR has_table_privilege('service_role','public.supporting_documents','DELETE')
     OR has_table_privilege('service_role','public.supporting_documents','TRUNCATE')
     OR has_table_privilege('service_role','public.case_notes','DELETE')
     OR has_table_privilege('service_role','public.document_links','DELETE')
     OR has_table_privilege('service_role','public.wiki_sections','TRUNCATE')
     OR NOT has_function_privilege('authenticated','public.get_trash_purge_impact(uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.confirm_trash_purge(uuid,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.retry_trash_purge(uuid,text,text)','EXECUTE')
     OR has_function_privilege('service_role','public.confirm_trash_purge(uuid,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('service_role','public.claim_trash_purge_work(integer,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'purge privilege boundary is incorrect';
  END IF;
END $fixture$;

SET LOCAL ROLE authenticated;
DO $direct_dml_denial$ DECLARE denied boolean:=false; BEGIN
  BEGIN UPDATE public.trash_purge_jobs SET state='completed'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'authenticated direct purge-job DML succeeded'; END IF;
END $direct_dml_denial$;
RESET ROLE;

SET LOCAL ROLE service_role;
DO $service_dml_denial$ DECLARE denied boolean:=false; BEGIN
  BEGIN DELETE FROM public.trash_purge_tombstones; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct tombstone delete succeeded'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.supporting_documents WHERE id='98900000-0000-0000-0000-000000000098'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct supporting-document delete succeeded'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.clients WHERE id='98200000-0000-0000-0000-000000000001'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct Client delete succeeded'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.matters WHERE id='98300000-0000-0000-0000-000000000001'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct Matter delete succeeded'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.documents WHERE id='98400000-0000-0000-0000-000000000002'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct Document delete succeeded'; END IF;
  denied:=false;
  BEGIN DELETE FROM public.case_notes WHERE document_id='98400000-0000-0000-0000-000000000001'; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct dependent delete succeeded'; END IF;
  denied:=false;
  BEGIN TRUNCATE public.wiki_sections; EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'service role direct hierarchy truncate succeeded'; END IF;
END $service_dml_denial$;
RESET ROLE;

DO $postgres_like_dml_denial$
DECLARE denied boolean:=false;
BEGIN
  BEGIN DELETE FROM public.clients WHERE id='98200000-0000-0000-0000-000000000001'; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'postgres-like direct root delete bypassed lifecycle trigger'; END IF;
  denied:=false;
  BEGIN TRUNCATE public.clients CASCADE; EXCEPTION WHEN others THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'postgres-like hierarchy truncate bypassed lifecycle trigger'; END IF;
END $postgres_like_dml_denial$;

ROLLBACK;
