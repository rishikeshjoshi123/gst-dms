-- Run after `npx supabase db reset --local --no-seed`.
BEGIN;

DO $fixture$
DECLARE
  owner_a uuid := '94000000-0000-0000-0000-000000000001'; owner_b uuid := '94000000-0000-0000-0000-000000000002';
  org_a uuid := '94100000-0000-0000-0000-000000000001'; org_b uuid := '94100000-0000-0000-0000-000000000002';
  client_a uuid := '94200000-0000-0000-0000-000000000001'; client_b uuid := '94200000-0000-0000-0000-000000000002';
  matter_a uuid := '94300000-0000-0000-0000-000000000001'; matter_b uuid := '94300000-0000-0000-0000-000000000002';
  doc_a uuid := '94400000-0000-0000-0000-000000000001'; doc_b uuid := '94400000-0000-0000-0000-000000000002'; doc_c uuid := '94400000-0000-0000-0000-000000000003';
  asset_a uuid := '94500000-0000-0000-0000-000000000001'; version_a uuid := '94600000-0000-0000-0000-000000000001'; trash_a uuid := '94700000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
    ('00000000-0000-0000-0000-000000000000',owner_a,'authenticated','authenticated','activity-a@test.invalid','x',now(),'{}','{}',now(),now()),
    ('00000000-0000-0000-0000-000000000000',owner_b,'authenticated','authenticated','activity-b@test.invalid','x',now(),'{}','{}',now(),now());
  INSERT INTO public.organisations(id,name,created_by) VALUES(org_a,'Activity A',owner_a),(org_b,'Activity B',owner_b);
  -- Organisation creation seeds the canonical owner membership/profile.
  UPDATE public.user_profiles SET display_name='Owner A' WHERE user_id=owner_a;
  UPDATE public.user_profiles SET display_name='Owner B' WHERE user_id=owner_b;
  INSERT INTO public.clients(id,org_id,name) VALUES(client_a,org_a,'Client A'),(client_b,org_b,'Client B');
  INSERT INTO public.matters(id,org_id,client_id,title) VALUES(matter_a,org_a,client_a,'Matter A'),(matter_b,org_b,client_b,'Matter B');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by) VALUES(doc_a,org_a,matter_a,'legacy-fixture.pdf',owner_a),(doc_b,org_b,matter_b,'legacy-fixture-b.pdf',owner_b),(doc_c,org_a,matter_a,'legacy-fixture-c.pdf',owner_a);
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,byte_size,created_by) VALUES(asset_a,org_a,'documents','orgs/94100000-0000-0000-0000-000000000001/assets/94500000-0000-0000-0000-000000000001/original.pdf',1,owner_a);
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,created_by) VALUES(version_a,org_a,doc_a,asset_a,1,'fixture.pdf',owner_a);
  INSERT INTO public.trash_operations(id,org_id,root_resource_type,root_resource_id,root_document_id,actor_user_id) VALUES(trash_a,org_a,'document',doc_a,doc_a,owner_a);
END $fixture$;

SET LOCAL ROLE service_role;
DO $authority$
DECLARE first_result record; replay_result record; lease_row record; completion record; blocked boolean;
BEGIN
  SELECT * INTO first_result FROM public.append_activity_event(
    '94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001','forged actor',
    'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','Document lifecycle changed',jsonb_build_object('change','reclassified'),
    'document','94400000-0000-0000-0000-000000000001','94600000-0000-0000-0000-000000000001',gen_random_uuid(),NULL,'activity-fixture-replay',now());
  IF first_result.activity_event_id IS NULL OR first_result.replayed THEN RAISE EXCEPTION 'authoritative Activity append did not create a durable event'; END IF;
  SELECT * INTO replay_result FROM public.append_activity_event(
    '94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,
    'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','different safe retry text',jsonb_build_object('change','reclassified'),
    'document','94400000-0000-0000-0000-000000000001','94600000-0000-0000-0000-000000000001',NULL,NULL,'activity-fixture-replay',now());
  IF NOT replay_result.replayed OR replay_result.activity_event_id<>first_result.activity_event_id OR replay_result.outbox_event_id<>first_result.outbox_event_id THEN RAISE EXCEPTION 'Activity replay did not return its durable original event'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','client.created',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'client','94200000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001',NULL,'Client retained','Client created','{}','client','94200000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-replay',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'cross-subject Activity idempotency reuse was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000002','client.created',1::smallint,'user','94000000-0000-0000-0000-000000000002',NULL,'client','94200000-0000-0000-0000-000000000002','94200000-0000-0000-0000-000000000002',NULL,'Client retained','Client created','{}','client','94200000-0000-0000-0000-000000000002',NULL,NULL,NULL,'activity-fixture-replay',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'cross-tenant Activity idempotency reuse was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',2::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-bad-definition',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'unknown Activity definition/version was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'document','94400000-0000-0000-0000-000000000001',NULL,'94300000-0000-0000-0000-000000000001','Document retained','Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-forged-lineage',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'forged Activity lineage was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','Changed',jsonb_build_object('storage_path','private/file.pdf'),'document','94400000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-sensitive',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'sensitive Activity metadata was accepted'; END IF;
  SELECT * INTO replay_result FROM public.append_activity_event('94100000-0000-0000-0000-000000000001','resource.trashed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'trash_operation','94700000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document Trash operation','Document moved to Trash',jsonb_build_object('resource_type','document'),'trash_operation','94700000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-document-root-trash',now());
  IF replay_result.activity_event_id IS NULL THEN RAISE EXCEPTION 'document-root Trash operation did not derive document lineage'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000001','94600000-0000-0000-0000-000000000099',NULL,NULL,'activity-fixture-missing-version',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'missing target version was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000003','94600000-0000-0000-0000-000000000001',NULL,NULL,'activity-fixture-wrong-target-version',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'target version bound to another document was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000002','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000002',NULL,'document','94400000-0000-0000-0000-000000000002','94200000-0000-0000-0000-000000000002','94300000-0000-0000-0000-000000000002','Document retained','Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000002','94600000-0000-0000-0000-000000000001',NULL,NULL,'activity-fixture-cross-tenant-version',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'cross-tenant target version was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'integration','94000000-0000-0000-0000-000000000002','Foreign integration','document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document retained','Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-foreign-integration',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'cross-tenant integration actor was accepted'; END IF;
  blocked:=false; BEGIN PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','document.lifecycle_changed',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'document','94400000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001','94300000-0000-0000-0000-000000000001','Document'||chr(10),'Changed',jsonb_build_object('change','reclassified'),'document','94400000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-newline',now()); EXCEPTION WHEN raise_exception THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'newline snapshot was accepted'; END IF;
  SELECT * INTO lease_row FROM public.lease_activity_projector_events(10,120) WHERE outbox_event_id=first_result.outbox_event_id;
  SELECT * INTO completion FROM public.complete_activity_projector_event(lease_row.outbox_event_id,lease_row.lease_token);
  IF completion.code<>'ok' THEN RAISE EXCEPTION 'service-only Activity projector completion was not accepted'; END IF;
  blocked:=false; BEGIN UPDATE public.activity_events SET summary='Mutated' WHERE id=first_result.activity_event_id; EXCEPTION WHEN others THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'Activity event mutation was accepted'; END IF;
  PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','client.created',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'client','94200000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001',NULL,'Client retained','Client created','{}','client','94200000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-stale-retry',now());
  PERFORM public.append_activity_event('94100000-0000-0000-0000-000000000001','client.created',1::smallint,'user','94000000-0000-0000-0000-000000000001',NULL,'client','94200000-0000-0000-0000-000000000001','94200000-0000-0000-0000-000000000001',NULL,'Client retained','Client created','{}','client','94200000-0000-0000-0000-000000000001',NULL,NULL,NULL,'activity-fixture-stale-dead',now());
  blocked:=false; BEGIN INSERT INTO public.activity_events(org_id,actor_kind,actor_snapshot,event_type,event_version,subject_type,subject_id,subject_snapshot,summary,metadata,visibility,renderer_key,target_type,target_id,idempotency_key,occurred_at) VALUES('94100000-0000-0000-0000-000000000001','system','System','client.created',1,'organisation','94100000-0000-0000-0000-000000000001','Organisation','Bypass','{}','organisation','client.created','organisation','94100000-0000-0000-0000-000000000001','direct-service-bypass',now()); EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END; IF NOT blocked THEN RAISE EXCEPTION 'service role retained direct Activity table authority'; END IF;
END $authority$;
RESET ROLE;

UPDATE public.activity_projector_outbox_events outbox SET delivery_state='leased',attempt_count=0,lease_token=gen_random_uuid(),lease_expires_at=now()-interval '1 second' FROM public.activity_events event WHERE event.id=outbox.activity_event_id AND event.idempotency_key='activity-fixture-stale-retry';
UPDATE public.activity_projector_outbox_events outbox SET delivery_state='leased',attempt_count=5,lease_token=gen_random_uuid(),lease_expires_at=now()-interval '1 second' FROM public.activity_events event WHERE event.id=outbox.activity_event_id AND event.idempotency_key='activity-fixture-stale-dead';
SET LOCAL ROLE service_role;
DO $stale_lease$
DECLARE leased record;
BEGIN
  SELECT * INTO leased FROM public.lease_activity_projector_events(100,120) LIMIT 1;
  IF leased.outbox_event_id IS NULL THEN RAISE EXCEPTION 'expired Activity projector lease was not retried'; END IF;
END $stale_lease$;
RESET ROLE;

DO $browser_surface$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.activity_projector_receipts receipt JOIN public.activity_events event ON event.id=receipt.activity_event_id WHERE event.idempotency_key='activity-fixture-replay') THEN RAISE EXCEPTION 'service-only Activity projector receipt was not atomically recorded'; END IF;
  IF (SELECT outbox.delivery_state::text FROM public.activity_projector_outbox_events outbox JOIN public.activity_events event ON event.id=outbox.activity_event_id WHERE event.idempotency_key='activity-fixture-stale-dead')<>'dead_letter' THEN RAISE EXCEPTION 'expired Activity projector lease did not dead-letter at the retry cap'; END IF;
  IF has_table_privilege('authenticated','public.activity_events','INSERT') OR has_table_privilege('authenticated','public.activity_events','UPDATE') OR has_function_privilege('authenticated','public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz)','EXECUTE') OR has_table_privilege('service_role','public.activity_events','INSERT') OR NOT has_function_privilege('service_role','public.append_activity_event(uuid,text,smallint,public.activity_actor_kind,uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,uuid,uuid,uuid,uuid,text,timestamptz)','EXECUTE') THEN RAISE EXCEPTION 'Activity browser or service authority grant surface is unsafe'; END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('activity_events','activity_projector_outbox_events') AND column_name ~* '(content|storage_path|object_key|url|embedding|credential|secret)') THEN RAISE EXCEPTION 'Activity schema retains a prohibited content or locator column'; END IF;
END $browser_surface$;

ROLLBACK;
