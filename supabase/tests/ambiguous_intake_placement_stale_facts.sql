\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE
  actor uuid:='153a0000-0000-0000-0000-000000000001';
  org uuid:='153b0000-0000-0000-0000-000000000001';
  existing_client uuid:='153c0000-0000-0000-0000-000000000001';
  changing_client uuid:='165c0000-0000-0000-0000-000000000001';
  source_matter_a uuid:='165d0000-0000-0000-0000-000000000001';
  source_matter_b uuid:='165d0000-0000-0000-0000-000000000002';
  client_matter_a uuid:='165d0000-0000-0000-0000-000000000003';
  client_matter_b uuid:='165d0000-0000-0000-0000-000000000004';
  intake_changed uuid:='16570000-0000-0000-0000-000000000001';
  asset_changed uuid:='16570000-0000-0000-0000-000000000002';
  client_changed uuid:='16570000-0000-0000-0000-000000000003';
  produced record; updated_client record;
  hash_denied boolean:=false; mime_denied boolean:=false; page_count_denied boolean:=false;
  source_candidates jsonb; client_candidates jsonb;
BEGIN
  INSERT INTO public.clients(id,org_id,name) VALUES(changing_client,org,'Placement lifecycle client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES
    (source_matter_a,org,existing_client,'Source fence A','SOURCE-FENCE-A'),
    (source_matter_b,org,existing_client,'Source fence B','SOURCE-FENCE-B'),
    (client_matter_a,org,changing_client,'Client fence A','CLIENT-FENCE-A'),
    (client_matter_b,org,changing_client,'Client fence B','CLIENT-FENCE-B');
  source_candidates:=jsonb_build_array(
    jsonb_build_object('matter_id',source_matter_a,'evidence',jsonb_build_array(jsonb_build_object('kind','matter_code_exact','source_page_number',1))),
    jsonb_build_object('matter_id',source_matter_b,'evidence',jsonb_build_array(jsonb_build_object('kind','referenced_document_exact','source_page_number',2))));
  client_candidates:=jsonb_build_array(
    jsonb_build_object('matter_id',client_matter_a,'evidence',jsonb_build_array(jsonb_build_object('kind','matter_code_exact','source_page_number',1))),
    jsonb_build_object('matter_id',client_matter_b,'evidence',jsonb_build_array(jsonb_build_object('kind','referenced_document_exact','source_page_number',2))));

  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
  VALUES
    ('165f0000-0000-0000-0000-000000000001',org,'documents','orgs/'||org||'/assets/165f0000-0000-0000-0000-000000000001/original.pdf',repeat('1',64),100,'application/pdf','available',now(),2,actor),
    ('165f0000-0000-0000-0000-000000000002',org,'documents','orgs/'||org||'/assets/165f0000-0000-0000-0000-000000000002/original.pdf',repeat('2',64),100,'application/pdf','available',now(),2,actor),
    ('165f0000-0000-0000-0000-000000000003',org,'documents','orgs/'||org||'/assets/165f0000-0000-0000-0000-000000000003/original.pdf',repeat('3',64),100,'application/pdf','available',now(),2,actor);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at) VALUES
    ('16580000-0000-0000-0000-000000000001',org,'165f0000-0000-0000-0000-000000000001','intake-revision.pdf','application/pdf',100,'finalized',actor,now(),now()),
    ('16580000-0000-0000-0000-000000000002',org,'165f0000-0000-0000-0000-000000000002','asset-revision.pdf','application/pdf',100,'finalized',actor,now(),now()),
    ('16580000-0000-0000-0000-000000000003',org,'165f0000-0000-0000-0000-000000000003','client-revision.pdf','application/pdf',100,'finalized',actor,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by) VALUES
    (intake_changed,org,'165f0000-0000-0000-0000-000000000001','16580000-0000-0000-0000-000000000001','ready',actor),
    (asset_changed,org,'165f0000-0000-0000-0000-000000000002','16580000-0000-0000-0000-000000000002','ready',actor),
    (client_changed,org,'165f0000-0000-0000-0000-000000000003','16580000-0000-0000-0000-000000000003','ready',actor);

  PERFORM set_config('request.jwt.claim.role','service_role',true);
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(intake_changed,'trusted-stale-v1',source_candidates);
  IF produced.code<>'ok' THEN RAISE EXCEPTION 'Intake revision fixture was not produced'; END IF;
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(asset_changed,'trusted-stale-v1',source_candidates);
  IF produced.code<>'ok' THEN RAISE EXCEPTION 'Asset revision fixture was not produced'; END IF;
  SELECT * INTO produced FROM public.produce_ambiguous_intake_placement_review(client_changed,'trusted-stale-v1',client_candidates);
  IF produced.code<>'ok' OR EXISTS(
    SELECT 1 FROM public.intake_placement_candidates c JOIN public.matters m ON m.id=c.matter_id
    JOIN public.clients cl ON cl.id=c.client_id
    WHERE c.placement_run_id=produced.placement_run_id
      AND (c.client_id<>m.client_id OR c.client_revision<>cl.revision)
  ) THEN RAISE EXCEPTION 'Exact Client identity/revision was not snapshotted'; END IF;

  UPDATE public.intake_items SET updated_at=updated_at+interval '1 second' WHERE id=intake_changed;
  UPDATE public.file_assets SET availability='quarantined',validated_at=NULL WHERE id='165f0000-0000-0000-0000-000000000002';
  BEGIN UPDATE public.file_assets SET sha256=repeat('4',64) WHERE id='165f0000-0000-0000-0000-000000000002';
    EXCEPTION WHEN OTHERS THEN hash_denied:=SQLERRM='file asset sha256 is immutable'; END;
  BEGIN UPDATE public.file_assets SET detected_mime_type='image/png' WHERE id='165f0000-0000-0000-0000-000000000002';
    EXCEPTION WHEN OTHERS THEN mime_denied:=SQLERRM='file asset mime type is immutable'; END;
  BEGIN UPDATE public.file_assets SET validated_page_count=3 WHERE id='165f0000-0000-0000-0000-000000000002';
    EXCEPTION WHEN OTHERS THEN page_count_denied:=SQLERRM='validated file asset page count is immutable'; END;
  IF NOT hash_denied OR NOT mime_denied OR NOT page_count_denied THEN
    RAISE EXCEPTION 'Immutable source facts were directly mutable';
  END IF;
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  SELECT * INTO updated_client FROM public.update_client_command(changing_client,1,'Placement lifecycle client updated',NULL,NULL,gen_random_uuid());
  IF updated_client.code<>'ok' THEN RAISE EXCEPTION 'Client revision fixture could not be changed'; END IF;

  IF (SELECT count(*) FROM public.review_items WHERE intake_id IN(intake_changed,asset_changed,client_changed)
      AND status='closed' AND closure_reason='source_unavailable')<>3
    OR EXISTS(SELECT 1 FROM public.intake_placement_runs WHERE intake_id IN(intake_changed,asset_changed,client_changed) AND state='ambiguous') THEN
    RAISE EXCEPTION 'A stale Intake, asset, or Client fact left an active placement fence';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.get_intake_item_triage_context(intake_changed)) THEN
    RAISE EXCEPTION 'Closed stale Review still fenced ordinary Intake triage';
  END IF;
END $test$;
ROLLBACK;
