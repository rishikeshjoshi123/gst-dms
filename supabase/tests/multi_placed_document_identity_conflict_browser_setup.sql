\set ON_ERROR_STOP on
DO $setup$
DECLARE org uuid:='152b0000-0000-0000-0000-000000000001';
  target_b uuid:='152d0000-0000-0000-0000-000000000002';
  target_c uuid:='169d0000-0000-0000-0000-000000000003';
  target_c_doc uuid:='169e0000-0000-0000-0000-000000000003';
  target_c_asset uuid:='169f0000-0000-0000-0000-000000000003';
  target_c_version uuid:='16900000-0000-0000-0000-000000000003';
  rev bigint; created record;
BEGIN
  UPDATE auth.users SET encrypted_password=crypt('PlacementFixture167!',gen_salt('bf')),
    raw_app_meta_data='{"provider":"email","providers":["email"]}',
    raw_user_meta_data='{"full_name":"Placement member"}',
    confirmation_token='',recovery_token='',email_change_token_new='',email_change=''
    WHERE id IN ('152a0000-0000-0000-0000-000000000001','152a0000-0000-0000-0000-000000000002');
  INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,id,created_at,updated_at,last_sign_in_at)
    SELECT u.id::text,u.id,jsonb_build_object('sub',u.id,'email',u.email),'email',gen_random_uuid(),now(),now(),now()
    FROM auth.users u WHERE u.id IN ('152a0000-0000-0000-0000-000000000001','152a0000-0000-0000-0000-000000000002');
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-000000000001',true);
  SELECT revision INTO rev FROM public.matters WHERE id=target_b;
  SELECT * INTO created FROM public.activate_matter_identifier(target_b,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/555/2026','GST/555/2026','152e0000-0000-0000-0000-000000000003',
    '15200000-0000-0000-0000-000000000003',1,'GST/555/2026','[]',
    'Verified exact target B for browser',gen_random_uuid());
  IF created.code<>'ok' THEN RAISE EXCEPTION 'Browser target B verification failed: %',created.code; END IF;
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
    VALUES(target_c,org,'152c0000-0000-0000-0000-000000000001','Reference C','REF-169-C');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,
    content_availability,status,created_by)
    VALUES(target_c_doc,org,target_c,'fixture/reference-c.pdf','Reference C key source','proceeding','upload','source_attached','placed',
      '152a0000-0000-0000-0000-000000000001');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,
    validated_at,validated_page_count,created_by)
    VALUES(target_c_asset,org,'documents','orgs/'||org||'/assets/'||target_c_asset||'/original.pdf',
      repeat('9',64),100,'application/pdf','available',now(),1,'152a0000-0000-0000-0000-000000000001');
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,
    validation_state,state,validated_at,promoted_at,created_by)
    VALUES(target_c_version,org,target_c_doc,target_c_asset,1,'reference-c.pdf',1,'valid','current',now(),now(),
      '152a0000-0000-0000-0000-000000000001');
  UPDATE public.documents SET current_version_id=target_c_version WHERE id=target_c_doc;
  SELECT revision INTO rev FROM public.matters WHERE id=target_c;
  SELECT * INTO created FROM public.activate_matter_identifier(target_c,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/556/2026','GST/556/2026',target_c_doc,target_c_version,1,'GST/556/2026','[]',
    'Verified exact target C for browser',gen_random_uuid());
  IF created.code<>'ok' OR (SELECT count(*) FROM public.review_items WHERE type='multi_placement_conflict' AND status='needs_review')<>1
    THEN RAISE EXCEPTION 'Browser multi-target setup failed: %',created.code; END IF;
END $setup$;
