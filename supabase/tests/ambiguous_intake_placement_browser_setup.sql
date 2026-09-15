\set ON_ERROR_STOP on
DO $setup$
DECLARE actor uuid:='153a0000-0000-0000-0000-000000000001'; org uuid:='153b0000-0000-0000-0000-000000000001';
  client_id uuid:='153c0000-0000-0000-0000-000000000001'; asset_id uuid:='164f0000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES
    ('164d0000-0000-0000-0000-000000000001',org,client_id,'Assessment proceeding','PLACE-BROWSER-A'),
    ('164d0000-0000-0000-0000-000000000002',org,client_id,'Appeal proceeding','PLACE-BROWSER-B');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES(asset_id,org,'documents','orgs/'||org||'/assets/'||asset_id||'/original.pdf','5d02d605e459d75c07055734a17b172b7fa523b6450047e62edbd2c8f5033b88',4551,'application/pdf','available',now(),4,actor);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES('16480000-0000-0000-0000-000000000001',org,asset_id,'ambiguous-browser-source.pdf','application/pdf',4551,'finalized',actor,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
    VALUES('16470000-0000-0000-0000-000000000001',org,asset_id,'16480000-0000-0000-0000-000000000001','ready',actor);
  PERFORM set_config('request.jwt.claim.role','service_role',true);
  PERFORM public.produce_ambiguous_intake_placement_review('16470000-0000-0000-0000-000000000001','trusted-placement-browser-v1',jsonb_build_array(
    jsonb_build_object('matter_id','164d0000-0000-0000-0000-000000000001','evidence',jsonb_build_array(jsonb_build_object('kind','verified_client_identifier','source_page_number',1))),
    jsonb_build_object('matter_id','164d0000-0000-0000-0000-000000000002','evidence',jsonb_build_array(jsonb_build_object('kind','referenced_document_exact','source_page_number',2)))
  ));
END $setup$;
