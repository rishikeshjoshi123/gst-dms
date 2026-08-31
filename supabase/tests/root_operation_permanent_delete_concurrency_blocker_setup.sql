\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('request.jwt.claim.role','authenticated',true);
SELECT set_config('request.jwt.claim.sub',:'owner_id',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',:'owner_id','iat',extract(epoch FROM now())::bigint)::text,true);
SELECT operation_id FROM public.trash_resource('document',:'document_id','purge.concurrent.blocker-trash') \gset
SELECT impact_fingerprint FROM public.get_trash_purge_impact(:'operation_id') \gset
SELECT code FROM public.confirm_trash_purge(:'operation_id',:'impact_fingerprint','Blocker race document','purge.concurrent.blocker-confirm');
COMMIT;
SELECT :'operation_id';
