-- Exclusively disposable D05 fixture; no provider or Storage calls.
CREATE SCHEMA attachment_test;
CREATE TABLE attachment_test.uploads(n integer PRIMARY KEY,document_id uuid,session_id uuid,intake_id uuid,asset_id uuid,event_id uuid,idempotency uuid);
DO $$
DECLARE org uuid:='154b0000-0000-0000-0000-000000000001'; actor uuid:='154a0000-0000-0000-0000-000000000001'; r record; doc uuid; n integer;
BEGIN
  INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    SELECT '00000000-0000-0000-0000-000000000000',('154a0000-0000-0000-0000-'||lpad(x::text,12,'0'))::uuid,'authenticated','authenticated','attachment-'||x||'@example.test',crypt('AttachmentFixture154!',gen_salt('bf')),now(),'{}','{}',now(),now() FROM generate_series(1,4) x;
  UPDATE auth.users SET confirmation_token='',recovery_token='',email_change_token_new='',email_change='',raw_app_meta_data='{"provider":"email","providers":["email"]}',raw_user_meta_data='{"full_name":"Attachment member"}' WHERE email LIKE 'attachment-%@example.test';
  INSERT INTO auth.identities(provider_id,user_id,identity_data,provider,id,created_at,updated_at,last_sign_in_at)
    SELECT id::text,id,jsonb_build_object('sub',id,'email',email),'email',gen_random_uuid(),now(),now(),now() FROM auth.users WHERE email LIKE 'attachment-%@example.test';
  INSERT INTO public.organisations(id,name,created_by) VALUES(org,'Attachment acceptance',actor),('154b0000-0000-0000-0000-000000000002','Foreign attachment','154a0000-0000-0000-0000-000000000004');
  INSERT INTO public.organisation_storage_policies(org_id,unique_asset_entitlement_bytes) VALUES(org,700000000) ON CONFLICT(org_id) DO UPDATE SET unique_asset_entitlement_bytes=EXCLUDED.unique_asset_entitlement_bytes;
  INSERT INTO public.org_members(org_id,user_id,role) VALUES(org,'154a0000-0000-0000-0000-000000000002','associate'),(org,'154a0000-0000-0000-0000-000000000003','viewer');
  INSERT INTO public.clients(id,org_id,name) VALUES('154c0000-0000-0000-0000-000000000001',org,'Attachment client');
  INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES('154d0000-0000-0000-0000-000000000001',org,'154c0000-0000-0000-0000-000000000001','Attachment proceeding','ATTACH-154');
  FOR n IN 5..6 LOOP
    INSERT INTO public.clients(id,org_id,name) VALUES(('154c0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,org,'Isolated Trash race client');
    INSERT INTO public.matters(id,org_id,client_id,title,matter_code) VALUES(('154d0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,org,('154c0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Trash race matter','ATTACH-RACE-'||n);
  END LOOP;
  FOR n IN 1..8 LOOP
    doc:=('154e0000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid;
    INSERT INTO public.documents(id,org_id,matter_id,display_title,document_class,origin_kind,content_availability,status,created_by,doc_type,reference_number,doc_date,direction,issued_by,summary,raw_metadata)
      VALUES(doc,org,('154d0000-0000-0000-0000-'||lpad(CASE WHEN n IN(5,6) THEN n ELSE 1 END::text,12,'0'))::uuid,'Metadata record '||n,'proceeding','manual_record','metadata_only','placed',actor,'SCN','HUMAN-154','2020-01-02','incoming','Human authority',NULL,'{"human":true}');
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',actor::text,true);
  FOR n IN 1..8 LOOP
    doc:=('154e0000-0000-0000-0000-'||lpad(CASE WHEN n=2 THEN 1 ELSE n END::text,12,'0'))::uuid;
    SELECT * INTO r FROM public.reserve_document_attachment(doc,'attachment-'||n||'.pdf',4530,('15490000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid);
    IF r.code<>'ok' THEN RAISE EXCEPTION 'reservation % failed: %',n,r.code; END IF;
    INSERT INTO attachment_test.uploads VALUES(n,doc,r.upload_session_id,r.intake_item_id,r.asset_id,NULL,('15490000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid);
  END LOOP;
END $$;

CREATE FUNCTION attachment_test.validate(n_value integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE u attachment_test.uploads%ROWTYPE; r record;
BEGIN
  SELECT * INTO u FROM attachment_test.uploads WHERE n=n_value;
  SELECT * INTO r FROM public.complete_document_upload(u.session_id,4530,md5(n_value::text)||md5(n_value::text),'application/pdf',u.idempotency,'154a0000-0000-0000-0000-000000000001','154b0000-0000-0000-0000-000000000001');
  IF r.code<>'ok' THEN RAISE EXCEPTION 'completion %: %',n_value,r.code; END IF;
  SELECT * INTO r FROM public.validate_document_intake_asset(u.intake_id,4,'ready',gen_random_uuid());
  IF r.code<>'ok' THEN RAISE EXCEPTION 'validation %: %',n_value,r.code; END IF;
  UPDATE attachment_test.uploads SET event_id=(SELECT id FROM public.outbox_events WHERE aggregate_id=u.intake_id AND event_kind='document.intake_validated.v1') WHERE n=n_value;
END $$;
SELECT attachment_test.validate(n) FROM attachment_test.uploads WHERE n IN(1,2,3,4,5,6,7);
