\set ON_ERROR_STOP on
DO $setup$
DECLARE
  actor uuid:='153a0000-0000-0000-0000-000000000001'; org uuid:='153b0000-0000-0000-0000-000000000001';
  client_id uuid:='153c0000-0000-0000-0000-000000000001';
  asset_id uuid:='163f0000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES
    ('163d0000-0000-0000-0000-000000000001',org,client_id,'Concurrent placement A','PLACE-RACE-A'),
    ('163d0000-0000-0000-0000-000000000002',org,client_id,'Concurrent placement B','PLACE-RACE-B');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES(asset_id,org,'documents','orgs/'||org||'/assets/'||asset_id||'/original.pdf',repeat('d',64),100,'application/pdf','available',now(),1,actor);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES('16380000-0000-0000-0000-000000000001',org,asset_id,'placement-race.pdf','application/pdf',100,'finalized',actor,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
    VALUES('16370000-0000-0000-0000-000000000001',org,asset_id,'16380000-0000-0000-0000-000000000001','ready',actor);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM public.produce_ambiguous_intake_placement_review('16370000-0000-0000-0000-000000000001','trusted-placement-race-v1',jsonb_build_array(
    jsonb_build_object('matter_id','163d0000-0000-0000-0000-000000000001','evidence',jsonb_build_array(jsonb_build_object('kind','matter_code_exact','source_page_number',NULL))),
    jsonb_build_object('matter_id','163d0000-0000-0000-0000-000000000002','evidence',jsonb_build_array(jsonb_build_object('kind','referenced_document_exact','source_page_number',1)))
  ));
END $setup$;
