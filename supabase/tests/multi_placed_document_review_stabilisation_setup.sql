-- Add a second distinct active verified Matter key to the persistent synthetic fixture.
\set ON_ERROR_STOP on
DO $setup$
DECLARE org uuid:='152b0000-0000-0000-0000-000000000001';
  m uuid:='169d0000-0000-0000-0000-000000000003'; d uuid:='169e0000-0000-0000-0000-000000000003';
  a uuid:='169f0000-0000-0000-0000-000000000003'; v uuid:='16900000-0000-0000-0000-000000000003';
  rev bigint; result record;
BEGIN
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  PERFORM set_config('request.jwt.claim.sub','152a0000-0000-0000-0000-000000000001',true);
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
    VALUES(m,org,'152c0000-0000-0000-0000-000000000001','Synthetic target C','REF-169-C');
  INSERT INTO public.documents(id,org_id,matter_id,storage_path,display_title,document_class,origin_kind,
    content_availability,status,created_by)
    VALUES(d,org,m,'fixture/reference-c.pdf','Synthetic C key source','proceeding','upload',
      'source_attached','placed','152a0000-0000-0000-0000-000000000001');
  INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,sha256,byte_size,detected_mime_type,availability,
    validated_at,validated_page_count,created_by)
    VALUES(a,org,'documents','orgs/'||org||'/assets/'||a||'/original.pdf',repeat('9',64),100,
      'application/pdf','available',now(),1,'152a0000-0000-0000-0000-000000000001');
  INSERT INTO public.document_versions(id,org_id,document_id,asset_id,version_number,original_filename,page_count,
    validation_state,state,validated_at,promoted_at,created_by)
    VALUES(v,org,d,a,1,'reference-c.pdf',1,'valid','current',now(),now(),
      '152a0000-0000-0000-0000-000000000001');
  UPDATE public.documents SET current_version_id=v WHERE id=d;
  SELECT revision INTO rev FROM public.matters WHERE id=m;
  SELECT * INTO result FROM public.activate_matter_identifier(m,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/556/2026','GST/556/2026',d,v,1,'GST/556/2026','[]',
    'Synthetic human verification for overlap',gen_random_uuid());
  IF result.code<>'ok' OR
    (SELECT count(*) FROM public.review_items WHERE document_id='152e0000-0000-0000-0000-000000000002'
      AND type='multi_placement_conflict' AND status='needs_review')<>1
    THEN RAISE EXCEPTION 'Synthetic multi-target fixture setup failed: %',result.code; END IF;
END $setup$;
