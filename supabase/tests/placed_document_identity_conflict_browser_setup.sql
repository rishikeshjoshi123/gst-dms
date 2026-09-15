\set ON_ERROR_STOP on
DO $setup$
DECLARE target_m uuid:='152d0000-0000-0000-0000-000000000002'; rev bigint; created record;
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
  SELECT revision INTO rev FROM public.matters WHERE id=target_m;
  SELECT * INTO created FROM public.activate_matter_identifier(target_m,rev,'order_reference','self_identifier',
    'GST Tribunal','GST/555/2026','GST/555/2026','152e0000-0000-0000-0000-000000000003',
    '15200000-0000-0000-0000-000000000003',1,'GST/555/2026','[]',
    'Verified exact target for browser fixture',gen_random_uuid());
  IF created.code<>'ok' OR (SELECT count(*) FROM public.review_items WHERE type='placement_conflict' AND status='needs_review')<>2
    THEN RAISE EXCEPTION 'Browser Review setup failed: %',created.code; END IF;
END $setup$;
