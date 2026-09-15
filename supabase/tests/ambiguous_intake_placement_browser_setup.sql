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
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,validated_at,validated_page_count,created_by)
    VALUES('164f0000-0000-0000-0000-000000000002',org,'documents','orgs/'||org||'/assets/164f0000-0000-0000-0000-000000000002/original.pdf',repeat('e',64),4551,'application/pdf','available',now(),4,actor);
  INSERT INTO public.upload_sessions(id,org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,state,created_by,uploaded_at,finalized_at)
    VALUES('16480000-0000-0000-0000-000000000002',org,'164f0000-0000-0000-0000-000000000002','unavailable-browser-source.pdf','application/pdf',4551,'finalized',actor,now(),now());
  INSERT INTO public.intake_items(id,org_id,asset_id,upload_session_id,state,uploaded_by)
    VALUES('16470000-0000-0000-0000-000000000002',org,'164f0000-0000-0000-0000-000000000002','16480000-0000-0000-0000-000000000002','ready',actor);
END $setup$;
