-- Persistent, dynamically identified fixture for the two-session harness.
\set ON_ERROR_STOP on
SELECT gen_random_uuid() AS org_id,gen_random_uuid() AS owner_id,gen_random_uuid() AS client_id,
  gen_random_uuid() AS matter_id,gen_random_uuid() AS document_id,gen_random_uuid() AS blocker_document_id \gset

INSERT INTO auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES('00000000-0000-0000-0000-000000000000',:'owner_id','authenticated','authenticated',
  :'owner_id'||'@purge-concurrency.test.invalid','x',now(),'{}','{}',now(),now());
INSERT INTO public.organisations(id,name,created_by) VALUES(:'org_id','Purge concurrency',:'owner_id');
UPDATE public.organisations organisation SET owner_membership_id=membership.id
FROM public.organisation_memberships membership
WHERE organisation.id=:'org_id' AND membership.org_id=organisation.id AND membership.user_id=:'owner_id';
INSERT INTO public.clients(id,org_id,name) VALUES(:'client_id',:'org_id','Purge concurrency client');
INSERT INTO public.matters(id,org_id,client_id,title,matter_code)
VALUES(:'matter_id',:'org_id',:'client_id','Purge concurrency matter','PURGE-RACE');
INSERT INTO public.documents(id,org_id,matter_id,storage_path,created_by,display_title)
VALUES(:'document_id',:'org_id',:'matter_id','fixture/purge-concurrency.pdf',:'owner_id','Concurrency document'),
  (:'blocker_document_id',:'org_id',:'matter_id','fixture/purge-blocker-race.pdf',:'owner_id','Blocker race document');

BEGIN;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub',:'owner_id',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',:'owner_id','iat',extract(epoch FROM now())::bigint)::text,true);
SELECT operation_id FROM public.trash_resource('document',:'document_id','purge.concurrent.trash') \gset
SELECT impact_fingerprint FROM public.get_trash_purge_impact(:'operation_id') \gset
SELECT code FROM public.confirm_trash_purge(:'operation_id',:'impact_fingerprint','Concurrency document','purge.concurrent.confirm');
COMMIT;

SELECT :'operation_id'||'|'||:'owner_id'||'|'||:'document_id'||'|'||:'blocker_document_id';
