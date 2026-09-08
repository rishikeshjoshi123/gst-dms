-- Bind direct-upload authority to its actor and conservatively account for
-- signed resumable uploads whose actual byte length has not yet been observed.
BEGIN;

-- A signed Storage upload token does not bind Upload-Length. Until the server
-- observes the object, every live token can consume the bucket's 50 MiB
-- per-object ceiling regardless of the browser declaration.
UPDATE public.storage_reservations AS reservation
SET reserved_bytes=52428800
FROM public.upload_sessions AS session
JOIN public.file_assets AS asset ON asset.id=session.asset_id AND asset.org_id=session.org_id
WHERE reservation.upload_session_id=session.id
  AND reservation.state='active'
  AND asset.byte_size IS NULL;

ALTER TABLE public.document_upload_command_receipts
  DROP CONSTRAINT document_upload_command_receipts_command_check;
ALTER TABLE public.document_upload_command_receipts
  ADD CONSTRAINT document_upload_command_receipts_command_check
  CHECK (command IN ('complete','fail','cancel'));

CREATE OR REPLACE FUNCTION public.reserve_document_upload(p_filename text,p_mime text,p_declared_bytes bigint,p_intended_matter uuid,p_idempotency uuid)
RETURNS TABLE(code text, upload_session_id uuid, intake_item_id uuid, asset_id uuid, bucket_id text, object_key text, expires_at timestamptz, retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid; v_asset uuid; v_session uuid; v_intake uuid; v_policy public.organisation_storage_policies%ROWTYPE; v_platform bigint; v_used bigint; v_reserved bigint; v_exp timestamptz; v_existing_exp timestamptz; v_existing_state text; v_unobserved_ceiling constant bigint:=52428800;
BEGIN
 SELECT org_id INTO v_org FROM public.get_my_organisation_context() WHERE state='active' AND 'document.intake.create'=ANY(capabilities) LIMIT 1;
 IF v_org IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 IF p_idempotency IS NULL THEN RETURN QUERY SELECT 'invalid_idempotency'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_org::text),pg_catalog.hashtext(auth.uid()::text||':'||p_idempotency::text));
 SELECT s.asset_id,s.id,i.id,s.expires_at,s.state INTO v_asset,v_session,v_intake,v_existing_exp,v_existing_state FROM public.upload_sessions AS s LEFT JOIN public.intake_items AS i ON i.upload_session_id=s.id WHERE s.org_id=v_org AND s.created_by=auth.uid() AND s.idempotency_key=p_idempotency;
 IF v_session IS NOT NULL THEN
   IF v_existing_exp<=now() THEN RETURN QUERY SELECT 'expired'::text,v_session::uuid,v_intake::uuid,v_asset::uuid,NULL::text,NULL::text,v_existing_exp::timestamptz,NULL::timestamptz; RETURN; END IF;
   IF v_existing_state='cancelled' THEN RETURN QUERY SELECT 'cancelled'::text,v_session::uuid,v_intake::uuid,v_asset::uuid,NULL::text,NULL::text,v_existing_exp::timestamptz,NULL::timestamptz; RETURN; END IF;
   IF v_existing_state<>'reserved' THEN RETURN QUERY SELECT 'not_available'::text,v_session::uuid,v_intake::uuid,v_asset::uuid,NULL::text,NULL::text,v_existing_exp::timestamptz,NULL::timestamptz; RETURN; END IF;
   RETURN QUERY SELECT 'ok'::text,v_session::uuid,v_intake::uuid,v_asset::uuid,'documents'::text,('orgs/'||v_org||'/assets/'||v_asset||'/original.pdf')::text,v_existing_exp::timestamptz,NULL::timestamptz; RETURN;
 END IF;
 v_exp:=now()+interval '24 hours';
 IF p_filename IS NULL OR char_length(p_filename) NOT BETWEEN 1 AND 255 OR p_filename ~ '[[:cntrl:]]' OR p_filename !~* '\.pdf$' THEN RETURN QUERY SELECT 'invalid_filename'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 IF p_mime IS DISTINCT FROM 'application/pdf' THEN RETURN QUERY SELECT 'invalid_mime'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 IF p_declared_bytes IS NULL OR p_declared_bytes<=0 THEN RETURN QUERY SELECT 'invalid_size'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 IF p_intended_matter IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.matters AS m WHERE m.id=p_intended_matter AND m.org_id=v_org AND m.status='active' AND m.deleted_at IS NULL) THEN RETURN QUERY SELECT 'invalid_matter'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 PERFORM public.maintain_document_upload_sessions(1000);
 INSERT INTO public.organisation_storage_policies(org_id) VALUES(v_org) ON CONFLICT(org_id) DO NOTHING;
 SELECT * INTO v_policy FROM public.organisation_storage_policies AS osp WHERE osp.org_id=v_org FOR UPDATE;
 SELECT psp.unique_asset_guard_bytes INTO v_platform FROM public.platform_storage_policy AS psp WHERE psp.singleton FOR UPDATE;
 IF p_declared_bytes>v_policy.max_pdf_bytes THEN RETURN QUERY SELECT 'file_too_large'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 SELECT public.document_retained_asset_bytes(v_org) INTO v_used;
 SELECT coalesce(sum(r.reserved_bytes),0) INTO v_reserved FROM public.storage_reservations AS r JOIN public.upload_sessions AS s ON s.id=r.upload_session_id JOIN public.file_assets AS a ON a.id=s.asset_id AND a.org_id=s.org_id WHERE r.org_id=v_org AND r.state='active' AND r.expires_at>now() AND a.byte_size IS NULL;
 IF v_used+v_reserved+v_unobserved_ceiling>v_policy.unique_asset_entitlement_bytes THEN RETURN QUERY SELECT 'organisation_quota_exceeded'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 SELECT public.document_platform_retained_asset_bytes() INTO v_used;
 SELECT coalesce(sum(r.reserved_bytes),0) INTO v_reserved FROM public.storage_reservations AS r JOIN public.upload_sessions AS s ON s.id=r.upload_session_id JOIN public.file_assets AS a ON a.id=s.asset_id AND a.org_id=s.org_id WHERE r.state='active' AND r.expires_at>now() AND a.byte_size IS NULL;
 IF v_used+v_reserved+v_unobserved_ceiling>v_platform THEN RETURN QUERY SELECT 'platform_capacity_unavailable'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 v_asset:=gen_random_uuid(); INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,availability,created_by) VALUES(v_asset,v_org,'documents','orgs/'||v_org||'/assets/'||v_asset||'/original.pdf','reserved',auth.uid());
 INSERT INTO public.upload_sessions(org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,created_by,idempotency_key,expires_at) VALUES(v_org,v_asset,p_filename,p_mime,p_declared_bytes,auth.uid(),p_idempotency,v_exp) RETURNING id INTO v_session;
 INSERT INTO public.storage_reservations(org_id,upload_session_id,reserved_bytes,expires_at) VALUES(v_org,v_session,v_unobserved_ceiling,v_exp);
 INSERT INTO public.intake_items(org_id,asset_id,upload_session_id,intended_matter_id,uploaded_by) VALUES(v_org,v_asset,v_session,p_intended_matter,auth.uid()) RETURNING id INTO v_intake;
 PERFORM public.document_upload_safe_event(v_org,v_session,'document.upload_reserved.v1','document.upload.reserve.'||v_session::text,jsonb_build_object('session_id',v_session::text,'intake_id',v_intake::text,'asset_id',v_asset::text));
 RETURN QUERY SELECT 'ok'::text,v_session,v_intake,v_asset,'documents'::text,'orgs/'||v_org||'/assets/'||v_asset||'/original.pdf',v_exp,NULL::timestamptz;
END $$;

DROP FUNCTION public.complete_document_upload(uuid,bigint,text,text,uuid);
CREATE FUNCTION public.complete_document_upload(p_session uuid,p_observed_bytes bigint,p_sha256 text,p_detected_mime text,p_idempotency uuid,p_actor uuid,p_org uuid)
RETURNS TABLE(code text, upload_session_id uuid, intake_item_id uuid, asset_id uuid, duplicate_asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE s public.upload_sessions%ROWTYPE; a public.file_assets%ROWTYPE; r public.storage_reservations%ROWTYPE; i public.intake_items%ROWTYPE; pol public.organisation_storage_policies%ROWTYPE; guard bigint; used bigint; reserved bigint; dup uuid; prior public.document_upload_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO s FROM public.upload_sessions AS us WHERE us.id=p_session FOR UPDATE;
 IF s.id IS NULL OR p_actor IS NULL OR p_org IS NULL OR p_idempotency IS NULL OR s.org_id IS DISTINCT FROM p_org OR s.created_by IS DISTINCT FROM p_actor OR s.idempotency_key IS DISTINCT FROM p_idempotency THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO i FROM public.intake_items AS ii WHERE ii.upload_session_id=s.id AND ii.org_id=s.org_id FOR UPDATE;
 SELECT * INTO prior FROM public.document_upload_command_receipts AS cr WHERE cr.org_id=s.org_id AND cr.upload_session_id=s.id AND cr.command='complete' AND cr.idempotency_key=p_idempotency;
 IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.code::text,s.id::uuid,i.id::uuid,s.asset_id::uuid,prior.duplicate_asset_id::uuid; RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.document_upload_command_receipts AS cr WHERE cr.org_id=s.org_id AND cr.upload_session_id=s.id AND cr.command='cancel' AND cr.idempotency_key=p_idempotency) OR s.state='cancelled' THEN RETURN QUERY SELECT 'cancelled'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO a FROM public.file_assets AS fa WHERE fa.id=s.asset_id AND fa.org_id=s.org_id FOR UPDATE;
 SELECT * INTO r FROM public.storage_reservations AS sr WHERE sr.upload_session_id=s.id AND sr.org_id=s.org_id FOR UPDATE;
 IF s.expires_at<=now() THEN RETURN QUERY SELECT 'expired'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 IF s.state<>'reserved' OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS m WHERE m.org_id=s.org_id AND m.user_id=p_actor AND m.state='active' AND (m.role IN ('admin','associate') OR EXISTS(SELECT 1 FROM public.organisations AS o WHERE o.id=s.org_id AND o.owner_membership_id=m.id))) THEN RETURN QUERY SELECT 'not_allowed'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 IF p_observed_bytes IS NULL OR p_observed_bytes<=0 OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' OR p_detected_mime IS DISTINCT FROM 'application/pdf' THEN RETURN QUERY SELECT 'invalid_observation'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO pol FROM public.organisation_storage_policies AS osp WHERE osp.org_id=s.org_id FOR UPDATE; SELECT psp.unique_asset_guard_bytes INTO guard FROM public.platform_storage_policy AS psp WHERE psp.singleton FOR UPDATE;
 IF p_observed_bytes>pol.max_pdf_bytes THEN RETURN QUERY SELECT 'file_too_large'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(s.org_id::text),pg_catalog.hashtext(p_sha256));
 SELECT fa.id INTO dup FROM public.file_assets AS fa WHERE fa.org_id=s.org_id AND fa.sha256=p_sha256 AND fa.id<>a.id ORDER BY EXISTS (SELECT 1 FROM public.document_versions AS dv WHERE dv.asset_id=fa.id) DESC,(fa.availability='available') DESC,fa.created_at LIMIT 1;
 IF dup IS NOT NULL THEN
   UPDATE public.file_assets SET byte_size=coalesce(byte_size,p_observed_bytes),detected_mime_type=coalesce(detected_mime_type,p_detected_mime),availability='failed',failed_at=now(),failure_code='duplicate' WHERE id=a.id;
   UPDATE public.upload_sessions SET state='failed',failed_at=now(),failure_code='duplicate' WHERE id=s.id; UPDATE public.storage_reservations SET state='released',released_at=now() WHERE id=r.id; UPDATE public.intake_items SET state='duplicate',failure_code='duplicate',updated_at=now() WHERE id=i.id;
   INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code,duplicate_asset_id) VALUES(s.org_id,s.id,'complete',p_idempotency,'duplicate',dup);
   PERFORM public.document_upload_safe_event(s.org_id,s.id,'document.upload_duplicate.v1','document.upload.complete.'||s.id::text,jsonb_build_object('session_id',s.id::text,'intake_id',i.id::text));
   RETURN QUERY SELECT 'duplicate'::text,s.id::uuid,i.id::uuid,a.id::uuid,dup::uuid; RETURN;
 END IF;
 SELECT public.document_retained_asset_bytes(s.org_id) INTO used;
 SELECT coalesce(sum(sr.reserved_bytes),0) INTO reserved FROM public.storage_reservations AS sr JOIN public.upload_sessions AS us ON us.id=sr.upload_session_id JOIN public.file_assets AS af ON af.id=us.asset_id AND af.org_id=us.org_id WHERE sr.org_id=s.org_id AND sr.state='active' AND sr.upload_session_id<>s.id AND sr.expires_at>now() AND af.byte_size IS NULL;
 IF used+reserved+p_observed_bytes>pol.unique_asset_entitlement_bytes THEN RETURN QUERY SELECT 'organisation_quota_exceeded'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 SELECT public.document_platform_retained_asset_bytes() INTO used;
 SELECT coalesce(sum(sr.reserved_bytes),0) INTO reserved FROM public.storage_reservations AS sr JOIN public.upload_sessions AS us ON us.id=sr.upload_session_id JOIN public.file_assets AS af ON af.id=us.asset_id AND af.org_id=us.org_id WHERE sr.state='active' AND sr.upload_session_id<>s.id AND sr.expires_at>now() AND af.byte_size IS NULL;
 IF used+reserved+p_observed_bytes>guard THEN RETURN QUERY SELECT 'platform_capacity_unavailable'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 UPDATE public.file_assets SET sha256=p_sha256,byte_size=p_observed_bytes,detected_mime_type=p_detected_mime,availability='available',validated_at=now() WHERE id=a.id;
 UPDATE public.upload_sessions SET state='finalized',uploaded_at=now(),finalized_at=now() WHERE id=s.id; UPDATE public.storage_reservations SET state='consumed',consumed_at=now() WHERE id=r.id; UPDATE public.intake_items SET state='uploaded',updated_at=now() WHERE id=i.id;
 INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code) VALUES(s.org_id,s.id,'complete',p_idempotency,'ok');
 PERFORM public.document_upload_safe_event(s.org_id,s.id,'document.upload_validation_requested.v1','document.upload.complete.'||s.id::text,jsonb_build_object('session_id',s.id::text,'intake_id',i.id::text,'asset_id',a.id::text));
 RETURN QUERY SELECT 'ok'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid;
END $$;

CREATE FUNCTION public.get_document_upload_completion_receipt(p_session uuid,p_idempotency uuid,p_actor uuid,p_org uuid)
RETURNS TABLE(code text, intake_item_id uuid, asset_id uuid, duplicate_asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE s public.upload_sessions%ROWTYPE; receipt public.document_upload_command_receipts%ROWTYPE; intake_id uuid;
BEGIN
 SELECT * INTO s FROM public.upload_sessions AS us WHERE us.id=p_session;
 IF s.id IS NULL OR p_actor IS NULL OR p_org IS NULL OR p_idempotency IS NULL OR s.org_id IS DISTINCT FROM p_org OR s.created_by IS DISTINCT FROM p_actor OR s.idempotency_key IS DISTINCT FROM p_idempotency OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS m WHERE m.org_id=p_org AND m.user_id=p_actor AND m.state='active' AND (m.role IN ('admin','associate') OR EXISTS(SELECT 1 FROM public.organisations AS o WHERE o.id=p_org AND o.owner_membership_id=m.id))) THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid; RETURN; END IF;
 SELECT id INTO intake_id FROM public.intake_items AS ii WHERE ii.upload_session_id=s.id AND ii.org_id=s.org_id;
 SELECT * INTO receipt FROM public.document_upload_command_receipts AS cr WHERE cr.org_id=s.org_id AND cr.upload_session_id=s.id AND cr.command='complete' AND cr.idempotency_key=p_idempotency;
 IF receipt.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid; RETURN; END IF;
 RETURN QUERY SELECT receipt.code::text,intake_id,s.asset_id,receipt.duplicate_asset_id;
END $$;

CREATE FUNCTION public.cancel_document_upload(p_session uuid,p_idempotency uuid,p_actor uuid,p_org uuid)
RETURNS TABLE(code text, completion_code text, intake_item_id uuid, asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE s public.upload_sessions%ROWTYPE; i public.intake_items%ROWTYPE; complete_receipt public.document_upload_command_receipts%ROWTYPE; cancel_receipt public.document_upload_command_receipts%ROWTYPE; v_unobserved_ceiling constant bigint:=52428800;
BEGIN
 SELECT * INTO s FROM public.upload_sessions AS us WHERE us.id=p_session FOR UPDATE;
 IF s.id IS NULL OR p_actor IS NULL OR p_org IS NULL OR p_idempotency IS NULL OR s.org_id IS DISTINCT FROM p_org OR s.created_by IS DISTINCT FROM p_actor OR s.idempotency_key IS DISTINCT FROM p_idempotency OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS m WHERE m.org_id=p_org AND m.user_id=p_actor AND m.state='active' AND (m.role IN ('admin','associate') OR EXISTS(SELECT 1 FROM public.organisations AS o WHERE o.id=p_org AND o.owner_membership_id=m.id))) THEN RETURN QUERY SELECT 'not_found'::text,NULL::text,NULL::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO i FROM public.intake_items AS ii WHERE ii.upload_session_id=s.id AND ii.org_id=s.org_id FOR UPDATE;
 SELECT * INTO complete_receipt FROM public.document_upload_command_receipts AS cr WHERE cr.org_id=s.org_id AND cr.upload_session_id=s.id AND cr.command='complete' AND cr.idempotency_key=p_idempotency;
 IF complete_receipt.id IS NOT NULL THEN RETURN QUERY SELECT 'already_completed'::text,complete_receipt.code::text,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
 SELECT * INTO cancel_receipt FROM public.document_upload_command_receipts AS cr WHERE cr.org_id=s.org_id AND cr.upload_session_id=s.id AND cr.command='cancel' AND cr.idempotency_key=p_idempotency;
 IF cancel_receipt.id IS NOT NULL OR s.state='cancelled' THEN RETURN QUERY SELECT 'cancelled'::text,NULL::text,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
 IF s.state<>'reserved' OR s.expires_at<=now() THEN RETURN QUERY SELECT 'not_available'::text,NULL::text,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
 UPDATE public.file_assets AS fa SET byte_size=coalesce(fa.byte_size,v_unobserved_ceiling),availability='failed',failed_at=now(),failure_code='upload_cancelled' WHERE fa.id=s.asset_id AND fa.org_id=s.org_id AND fa.availability='reserved';
 UPDATE public.upload_sessions SET state='cancelled',failure_code='upload_cancelled' WHERE id=s.id;
 UPDATE public.storage_reservations SET state='released',released_at=now() WHERE upload_session_id=s.id AND state='active';
 UPDATE public.intake_items SET state='discarded',discarded_at=now(),failure_code='upload_cancelled',updated_at=now() WHERE id=i.id AND state='awaiting_upload';
 INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code) VALUES(s.org_id,s.id,'cancel',p_idempotency,'cancelled');
 RETURN QUERY SELECT 'cancelled'::text,NULL::text,i.id::uuid,s.asset_id::uuid;
END $$;

-- A cancel that wins the session lock is terminal. A later validation failure
-- must not rewrite its state, Intake outcome, or command history.
CREATE OR REPLACE FUNCTION public.fail_document_upload(p_session uuid,p_error_code text,p_idempotency uuid)
RETURNS TABLE(code text, upload_session_id uuid, intake_item_id uuid, asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE s public.upload_sessions%ROWTYPE; i public.intake_items%ROWTYPE; prior public.document_upload_command_receipts%ROWTYPE;
BEGIN
 IF p_error_code IS NULL OR p_error_code NOT IN ('upload_failed','storage_missing','invalid_pdf','malware_suspect','validation_failed','upload_rejected') THEN RETURN QUERY SELECT 'invalid_error_code'::text,NULL::uuid,NULL::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO s FROM public.upload_sessions AS us WHERE us.id=p_session FOR UPDATE; IF s.id IS NULL OR p_idempotency IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO i FROM public.intake_items AS ii WHERE ii.upload_session_id=s.id FOR UPDATE;
 IF p_error_code IN ('upload_failed','storage_missing') THEN
   IF s.state='reserved' THEN RETURN QUERY SELECT 'retryable'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
   RETURN QUERY SELECT 'not_available'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid; RETURN;
 END IF;
 SELECT * INTO prior FROM public.document_upload_command_receipts AS cr WHERE cr.upload_session_id=p_session AND cr.command='fail'; IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.code::text,p_session::uuid,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
 IF s.state IN ('finalized','expired','failed','cancelled') THEN RETURN QUERY SELECT 'not_available'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
 UPDATE public.file_assets AS fa SET byte_size=coalesce(fa.byte_size,s.declared_byte_size),availability='failed',failed_at=now(),failure_code=p_error_code WHERE fa.id=s.asset_id;
 UPDATE public.upload_sessions AS us SET state='failed',failed_at=now(),failure_code=p_error_code WHERE us.id=s.id; UPDATE public.storage_reservations AS r SET state='released',released_at=now() WHERE r.upload_session_id=s.id AND r.state='active'; UPDATE public.intake_items AS ii SET state='failed',failed_at=now(),failure_code=p_error_code,updated_at=now() WHERE ii.id=i.id;
 INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code) VALUES(s.org_id,s.id,'fail',p_idempotency,'ok'); PERFORM public.document_upload_safe_event(s.org_id,s.id,'document.upload_failed.v1','document.upload.fail.'||s.id::text,jsonb_build_object('session_id',s.id::text,'intake_id',i.id::text,'error_code',p_error_code));
 RETURN QUERY SELECT 'ok'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid;
END $$;

-- Supabase signed upload tokens remain valid for two hours. A token can be
-- minted immediately before the CaseChain session expires, so terminal object
-- cleanup waits through that maximum authority lifetime plus a clock margin.
-- Until then the asset remains untombstoned and charged to retained bytes.
CREATE OR REPLACE FUNCTION public.claim_document_asset_storage_deletion_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(asset_id uuid, bucket_id text, object_key text, lease_token uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid batch size'; END IF;
 RETURN QUERY
 WITH candidates AS (
   SELECT fa.id
   FROM public.file_assets AS fa
   WHERE fa.storage_deleted_at IS NULL
     AND fa.legacy_staged_backfill_pending=false
     AND fa.availability IN ('failed','expired','quarantined')
     AND NOT EXISTS(SELECT 1 FROM public.document_versions AS dv WHERE dv.asset_id=fa.id)
     AND NOT EXISTS(SELECT 1 FROM public.upload_sessions AS us WHERE us.asset_id=fa.id AND us.expires_at+interval '2 hours 5 minutes'>now())
     AND (fa.storage_deletion_lease_expires_at IS NULL OR fa.storage_deletion_lease_expires_at<=now())
   ORDER BY fa.created_at
   FOR UPDATE OF fa SKIP LOCKED
   LIMIT p_batch_size
 ), leased AS (
   UPDATE public.file_assets AS fa
   SET storage_delete_attempted_at=now(),storage_deletion_lease_token=gen_random_uuid(),storage_deletion_lease_expires_at=now()+interval '10 minutes',storage_delete_failure_code=NULL
   FROM candidates AS candidate WHERE fa.id=candidate.id
   RETURNING fa.id,fa.bucket_id,fa.object_key,fa.storage_deletion_lease_token
 )
 SELECT leased.id,leased.bucket_id,leased.object_key,leased.storage_deletion_lease_token FROM leased;
END $$;

CREATE OR REPLACE FUNCTION public.maintain_document_upload_sessions(p_batch_size integer DEFAULT 100)
RETURNS TABLE(expired_sessions integer, expired_reservations integer, expired_intakes integer, expired_assets integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; n integer:=0; a integer:=0; b integer:=0; c integer:=0; d integer:=0; v_unobserved_ceiling constant bigint:=52428800;
BEGIN
 IF p_batch_size IS NULL OR p_batch_size<1 OR p_batch_size>1000 THEN RAISE EXCEPTION 'invalid batch size'; END IF;
 FOR x IN SELECT s.id,s.org_id,s.asset_id,i.id intake_id FROM public.upload_sessions AS s JOIN public.storage_reservations AS r ON r.upload_session_id=s.id LEFT JOIN public.intake_items AS i ON i.upload_session_id=s.id WHERE s.state IN ('reserved','uploading','uploaded') AND s.expires_at<=now() ORDER BY s.expires_at FOR UPDATE OF s SKIP LOCKED LIMIT p_batch_size LOOP
   UPDATE public.upload_sessions SET state='expired',expired_at=now() WHERE id=x.id; GET DIAGNOSTICS n=ROW_COUNT; a:=a+n;
   UPDATE public.storage_reservations SET state='expired',expired_at=now() WHERE upload_session_id=x.id AND state='active'; GET DIAGNOSTICS n=ROW_COUNT; b:=b+n;
   UPDATE public.intake_items SET state='expired',expired_at=now(),updated_at=now() WHERE id=x.intake_id AND state NOT IN ('assigned','duplicate','failed','discarded','expired'); GET DIAGNOSTICS n=ROW_COUNT; c:=c+n;
   UPDATE public.file_assets SET byte_size=coalesce(byte_size,v_unobserved_ceiling),availability='expired',expired_at=now(),failure_code='upload_expired' WHERE id=x.asset_id AND availability IN ('reserved','uploaded','validating','quarantined'); GET DIAGNOSTICS n=ROW_COUNT; d:=d+n;
   PERFORM public.document_upload_safe_event(x.org_id,x.id,'document.upload_expired.v1','document.upload.expire.'||x.id::text,jsonb_build_object('session_id',x.id::text));
 END LOOP;
 RETURN QUERY SELECT a,b,c,d;
END $$;

REVOKE ALL ON FUNCTION public.complete_document_upload(uuid,bigint,text,text,uuid,uuid,uuid), public.get_document_upload_completion_receipt(uuid,uuid,uuid,uuid), public.cancel_document_upload(uuid,uuid,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_document_upload(uuid,bigint,text,text,uuid,uuid,uuid), public.get_document_upload_completion_receipt(uuid,uuid,uuid,uuid), public.cancel_document_upload(uuid,uuid,uuid,uuid) TO service_role;

COMMIT;
