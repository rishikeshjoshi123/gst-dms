-- Close lifecycle integrity gaps discovered during the upload/processing bridge review.
-- All changes are additive or replace service-only command implementations.
BEGIN;

-- Storage accepts no object larger than 50 MiB. Keep the ordinary 25 MiB
-- default while making a policy override impossible to sign beyond Storage.
ALTER TABLE public.organisation_storage_policies
  DROP CONSTRAINT organisation_storage_policies_pdf_ceiling;
UPDATE public.organisation_storage_policies
  SET max_pdf_bytes=least(max_pdf_bytes,52428800)
  WHERE max_pdf_bytes>52428800;
ALTER TABLE public.organisation_storage_policies
  ADD CONSTRAINT organisation_storage_policies_pdf_ceiling
  CHECK (max_pdf_bytes <= 52428800);

-- Account for every retained object, not only successfully available assets.
-- A terminal intake records its observed/declarative byte size before its
-- reservation is released; expiry does the same conservatively. This prevents
-- retained quarantined or failed objects from creating a quota bypass.
CREATE OR REPLACE FUNCTION public.document_retained_asset_bytes(p_org_id uuid)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(sum(byte_size),0)::bigint
  FROM public.file_assets
  WHERE org_id=p_org_id AND byte_size IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.document_platform_retained_asset_bytes()
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(sum(byte_size),0)::bigint
  FROM public.file_assets
  WHERE byte_size IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION public.reserve_document_upload(p_filename text,p_mime text,p_declared_bytes bigint,p_intended_matter uuid,p_idempotency uuid)
RETURNS TABLE(code text, upload_session_id uuid, intake_item_id uuid, asset_id uuid, bucket_id text, object_key text, expires_at timestamptz, retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_org uuid; v_asset uuid; v_session uuid; v_intake uuid; v_policy public.organisation_storage_policies%ROWTYPE; v_platform bigint; v_used bigint; v_reserved bigint; v_exp timestamptz; v_existing_exp timestamptz;
BEGIN
 SELECT org_id INTO v_org FROM public.get_my_organisation_context() WHERE state='active' AND 'document.intake.create'=ANY(capabilities) LIMIT 1;
 IF v_org IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 IF p_idempotency IS NULL THEN RETURN QUERY SELECT 'invalid_idempotency'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_org::text),pg_catalog.hashtext(auth.uid()::text||':'||p_idempotency::text));
 SELECT s.asset_id,s.id,i.id,s.expires_at INTO v_asset,v_session,v_intake,v_existing_exp FROM public.upload_sessions AS s LEFT JOIN public.intake_items AS i ON i.upload_session_id=s.id WHERE s.org_id=v_org AND s.created_by=auth.uid() AND s.idempotency_key=p_idempotency;
 IF v_session IS NOT NULL THEN
   IF v_existing_exp<=now() THEN RETURN QUERY SELECT 'expired'::text,v_session::uuid,v_intake::uuid,v_asset::uuid,NULL::text,NULL::text,v_existing_exp::timestamptz,NULL::timestamptz; RETURN; END IF;
   RETURN QUERY SELECT 'ok'::text,v_session::uuid,v_intake::uuid,v_asset::uuid,'documents'::text,('orgs/'||v_org||'/assets/'||v_asset||'/original.pdf')::text,v_existing_exp::timestamptz,NULL::timestamptz; RETURN;
 END IF;
 v_exp := now()+interval '24 hours';
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
 SELECT coalesce(sum(r.reserved_bytes),0) INTO v_reserved FROM public.storage_reservations r JOIN public.file_assets a ON a.id=(SELECT s.asset_id FROM public.upload_sessions s WHERE s.id=r.upload_session_id) WHERE r.org_id=v_org AND r.state='active' AND r.expires_at>now() AND a.byte_size IS NULL;
 IF v_used+v_reserved+p_declared_bytes>v_policy.unique_asset_entitlement_bytes THEN RETURN QUERY SELECT 'organisation_quota_exceeded'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 SELECT public.document_platform_retained_asset_bytes() INTO v_used;
 SELECT coalesce(sum(r.reserved_bytes),0) INTO v_reserved FROM public.storage_reservations r JOIN public.file_assets a ON a.id=(SELECT s.asset_id FROM public.upload_sessions s WHERE s.id=r.upload_session_id) WHERE r.state='active' AND r.expires_at>now() AND a.byte_size IS NULL;
 IF v_used+v_reserved+p_declared_bytes>v_platform THEN RETURN QUERY SELECT 'platform_capacity_unavailable'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
 v_asset:=gen_random_uuid(); INSERT INTO public.file_assets(id,org_id,bucket_id,object_key,availability,created_by) VALUES(v_asset,v_org,'documents','orgs/'||v_org||'/assets/'||v_asset||'/original.pdf','reserved',auth.uid());
 INSERT INTO public.upload_sessions(org_id,asset_id,declared_filename,declared_mime_type,declared_byte_size,created_by,idempotency_key,expires_at) VALUES(v_org,v_asset,p_filename,p_mime,p_declared_bytes,auth.uid(),p_idempotency,v_exp) RETURNING id INTO v_session;
 INSERT INTO public.storage_reservations(org_id,upload_session_id,reserved_bytes,expires_at) VALUES(v_org,v_session,p_declared_bytes,v_exp);
 INSERT INTO public.intake_items(org_id,asset_id,upload_session_id,intended_matter_id,uploaded_by) VALUES(v_org,v_asset,v_session,p_intended_matter,auth.uid()) RETURNING id INTO v_intake;
 PERFORM public.document_upload_safe_event(v_org,v_session,'document.upload_reserved.v1','document.upload.reserve.'||v_session::text,jsonb_build_object('session_id',v_session::text,'intake_id',v_intake::text,'asset_id',v_asset::text));
 RETURN QUERY SELECT 'ok'::text,v_session,v_intake,v_asset,'documents'::text,'orgs/'||v_org||'/assets/'||v_asset||'/original.pdf',v_exp,NULL::timestamptz;
END $$;

CREATE OR REPLACE FUNCTION public.complete_document_upload(p_session uuid,p_observed_bytes bigint,p_sha256 text,p_detected_mime text,p_idempotency uuid)
RETURNS TABLE(code text, upload_session_id uuid, intake_item_id uuid, asset_id uuid, duplicate_asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE s public.upload_sessions%ROWTYPE; a public.file_assets%ROWTYPE; r public.storage_reservations%ROWTYPE; i public.intake_items%ROWTYPE; pol public.organisation_storage_policies%ROWTYPE; guard bigint; used bigint; reserved bigint; dup uuid; prior public.document_upload_command_receipts%ROWTYPE;
BEGIN
 SELECT * INTO prior FROM public.document_upload_command_receipts AS cr WHERE cr.upload_session_id=p_session AND cr.command='complete'; IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.code::text,p_session::uuid,(SELECT ii.id FROM public.intake_items AS ii WHERE ii.upload_session_id=p_session)::uuid,(SELECT us.asset_id FROM public.upload_sessions AS us WHERE us.id=p_session)::uuid,prior.duplicate_asset_id::uuid; RETURN; END IF;
 SELECT * INTO s FROM public.upload_sessions AS us WHERE us.id=p_session FOR UPDATE; IF s.id IS NULL THEN RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN; END IF;
 -- Re-read the command receipt after acquiring the session fence. Two
 -- concurrent completion RPCs may both miss the optimistic first lookup.
 SELECT * INTO prior FROM public.document_upload_command_receipts AS cr WHERE cr.upload_session_id=p_session AND cr.command='complete'; IF prior.id IS NOT NULL THEN RETURN QUERY SELECT prior.code::text,p_session::uuid,(SELECT ii.id FROM public.intake_items AS ii WHERE ii.upload_session_id=p_session)::uuid,s.asset_id::uuid,prior.duplicate_asset_id::uuid; RETURN; END IF;
 SELECT * INTO a FROM public.file_assets AS fa WHERE fa.id=s.asset_id FOR UPDATE; SELECT * INTO r FROM public.storage_reservations AS sr WHERE sr.upload_session_id=s.id FOR UPDATE; SELECT * INTO i FROM public.intake_items AS ii WHERE ii.upload_session_id=s.id FOR UPDATE;
 IF s.expires_at<=now() THEN RETURN QUERY SELECT 'expired'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 IF s.state<>'reserved' OR s.created_by IS NULL OR NOT EXISTS(SELECT 1 FROM public.organisation_memberships AS m WHERE m.org_id=s.org_id AND m.user_id=s.created_by AND m.state='active' AND (m.role IN ('admin','associate') OR EXISTS(SELECT 1 FROM public.organisations AS o WHERE o.id=s.org_id AND o.owner_membership_id=m.id))) THEN RETURN QUERY SELECT 'not_allowed'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 IF p_idempotency IS NULL OR p_observed_bytes IS NULL OR p_observed_bytes<=0 OR p_sha256 IS NULL OR p_sha256 !~ '^[0-9a-f]{64}$' OR p_detected_mime IS NULL OR p_detected_mime<>'application/pdf' THEN RETURN QUERY SELECT 'invalid_observation'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 SELECT * INTO pol FROM public.organisation_storage_policies AS osp WHERE osp.org_id=s.org_id FOR UPDATE; SELECT psp.unique_asset_guard_bytes INTO guard FROM public.platform_storage_policy AS psp WHERE psp.singleton FOR UPDATE;
 IF p_observed_bytes>pol.max_pdf_bytes THEN RETURN QUERY SELECT 'file_too_large'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 -- The partial checksum index covers every retained availability. Serialise
 -- same-org hashes so the safe duplicate result wins over a uniqueness error.
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(s.org_id::text),pg_catalog.hashtext(p_sha256));
 SELECT fa.id INTO dup FROM public.file_assets AS fa WHERE fa.org_id=s.org_id AND fa.sha256=p_sha256 AND fa.id<>a.id
   ORDER BY EXISTS (SELECT 1 FROM public.document_versions dv WHERE dv.asset_id=fa.id) DESC,
     (fa.availability='available') DESC, fa.created_at LIMIT 1;
 IF dup IS NOT NULL THEN
   UPDATE public.file_assets SET byte_size=coalesce(byte_size,p_observed_bytes),detected_mime_type=coalesce(detected_mime_type,p_detected_mime),availability='failed',failed_at=now(),failure_code='duplicate' WHERE id=a.id;
   UPDATE public.upload_sessions SET state='failed',failed_at=now(),failure_code='duplicate' WHERE id=s.id; UPDATE public.storage_reservations SET state='released',released_at=now() WHERE id=r.id; UPDATE public.intake_items SET state='duplicate',failure_code='duplicate',updated_at=now() WHERE id=i.id;
   INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code,duplicate_asset_id) VALUES(s.org_id,s.id,'complete',p_idempotency,'duplicate',dup);
   PERFORM public.document_upload_safe_event(s.org_id,s.id,'document.upload_duplicate.v1','document.upload.complete.'||s.id::text,jsonb_build_object('session_id',s.id::text,'intake_id',i.id::text));
   RETURN QUERY SELECT 'duplicate'::text,s.id::uuid,i.id::uuid,a.id::uuid,dup::uuid; RETURN;
 END IF;
 SELECT public.document_retained_asset_bytes(s.org_id) INTO used;
 SELECT coalesce(sum(sr.reserved_bytes),0) INTO reserved FROM public.storage_reservations sr JOIN public.upload_sessions us ON us.id=sr.upload_session_id JOIN public.file_assets af ON af.id=us.asset_id WHERE sr.org_id=s.org_id AND sr.state='active' AND sr.upload_session_id<>s.id AND sr.expires_at>now() AND af.byte_size IS NULL;
 IF used+reserved+p_observed_bytes>pol.unique_asset_entitlement_bytes THEN RETURN QUERY SELECT 'organisation_quota_exceeded'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 SELECT public.document_platform_retained_asset_bytes() INTO used;
 SELECT coalesce(sum(sr.reserved_bytes),0) INTO reserved FROM public.storage_reservations sr JOIN public.upload_sessions us ON us.id=sr.upload_session_id JOIN public.file_assets af ON af.id=us.asset_id WHERE sr.state='active' AND sr.upload_session_id<>s.id AND sr.expires_at>now() AND af.byte_size IS NULL;
 IF used+reserved+p_observed_bytes>guard THEN RETURN QUERY SELECT 'platform_capacity_unavailable'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid; RETURN; END IF;
 UPDATE public.file_assets SET sha256=p_sha256,byte_size=p_observed_bytes,detected_mime_type=p_detected_mime,availability='available',validated_at=now() WHERE id=a.id;
 UPDATE public.upload_sessions SET state='finalized',uploaded_at=now(),finalized_at=now() WHERE id=s.id; UPDATE public.storage_reservations SET state='consumed',consumed_at=now() WHERE id=r.id; UPDATE public.intake_items SET state='uploaded',updated_at=now() WHERE id=i.id;
 INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code) VALUES(s.org_id,s.id,'complete',p_idempotency,'ok');
 PERFORM public.document_upload_safe_event(s.org_id,s.id,'document.upload_validation_requested.v1','document.upload.complete.'||s.id::text,jsonb_build_object('session_id',s.id::text,'intake_id',i.id::text,'asset_id',a.id::text));
 RETURN QUERY SELECT 'ok'::text,s.id::uuid,i.id::uuid,a.id::uuid,NULL::uuid;
END $$;

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
 IF s.state IN ('finalized','expired','failed') THEN RETURN QUERY SELECT 'not_available'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid; RETURN; END IF;
 UPDATE public.file_assets AS fa SET byte_size=coalesce(fa.byte_size,s.declared_byte_size),availability='failed',failed_at=now(),failure_code=p_error_code WHERE fa.id=s.asset_id;
 UPDATE public.upload_sessions AS us SET state='failed',failed_at=now(),failure_code=p_error_code WHERE us.id=s.id; UPDATE public.storage_reservations AS r SET state='released',released_at=now() WHERE r.upload_session_id=s.id AND r.state='active'; UPDATE public.intake_items AS ii SET state='failed',failed_at=now(),failure_code=p_error_code,updated_at=now() WHERE ii.id=i.id;
 INSERT INTO public.document_upload_command_receipts(org_id,upload_session_id,command,idempotency_key,code) VALUES(s.org_id,s.id,'fail',p_idempotency,'ok'); PERFORM public.document_upload_safe_event(s.org_id,s.id,'document.upload_failed.v1','document.upload.fail.'||s.id::text,jsonb_build_object('session_id',s.id::text,'intake_id',i.id::text,'error_code',p_error_code));
 RETURN QUERY SELECT 'ok'::text,s.id::uuid,i.id::uuid,s.asset_id::uuid;
END $$;

CREATE OR REPLACE FUNCTION public.maintain_document_upload_sessions(p_batch_size integer DEFAULT 100)
RETURNS TABLE(expired_sessions integer, expired_reservations integer, expired_intakes integer, expired_assets integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE x record; n integer:=0; a integer:=0; b integer:=0; c integer:=0; d integer:=0;
BEGIN
 IF p_batch_size IS NULL OR p_batch_size<1 OR p_batch_size>1000 THEN RAISE EXCEPTION 'invalid batch size'; END IF;
 FOR x IN SELECT s.id,s.org_id,s.asset_id,s.declared_byte_size,i.id intake_id FROM public.upload_sessions s JOIN public.storage_reservations r ON r.upload_session_id=s.id LEFT JOIN public.intake_items i ON i.upload_session_id=s.id WHERE s.state IN ('reserved','uploading','uploaded') AND s.expires_at<=now() ORDER BY s.expires_at FOR UPDATE OF s SKIP LOCKED LIMIT p_batch_size LOOP
   UPDATE public.upload_sessions AS us SET state='expired',expired_at=now() WHERE us.id=x.id; GET DIAGNOSTICS n=ROW_COUNT; a:=a+n; UPDATE public.storage_reservations AS sr SET state='expired',expired_at=now() WHERE sr.upload_session_id=x.id AND sr.state='active'; GET DIAGNOSTICS n=ROW_COUNT; b:=b+n; UPDATE public.intake_items AS ii SET state='expired',expired_at=now(),updated_at=now() WHERE ii.id=x.intake_id AND ii.state NOT IN ('assigned','duplicate','failed','discarded','expired'); GET DIAGNOSTICS n=ROW_COUNT; c:=c+n;
   UPDATE public.file_assets AS fa SET byte_size=coalesce(fa.byte_size,x.declared_byte_size),availability='expired',expired_at=now(),failure_code='upload_expired' WHERE fa.id=x.asset_id AND fa.availability IN ('reserved','uploaded','validating','quarantined'); GET DIAGNOSTICS n=ROW_COUNT; d:=d+n;
   PERFORM public.document_upload_safe_event(x.org_id,x.id,'document.upload_expired.v1','document.upload.expire.'||x.id::text,jsonb_build_object('session_id',x.id::text));
 END LOOP;
 RETURN QUERY SELECT a,b,c,d;
END $$;

-- Requeue only interrupted or retryable orchestration runs. Validation results
-- such as invalid/encrypted/malware PDFs stay terminal; processing work has no
-- terminal external side effect before its fenced finish command succeeds.
CREATE OR REPLACE FUNCTION public.reconcile_document_processing_work(p_batch_size integer DEFAULT 100)
RETURNS TABLE(validation_requeued integer, processing_requeued integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE validation_count integer:=0; processing_count integer:=0;
BEGIN
 IF p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid batch size'; END IF;
 WITH candidates AS (
   SELECT sar.id,sar.outbox_event_id FROM public.source_analysis_runs sar
   WHERE sar.outbox_event_id IS NOT NULL AND ((sar.state='running' AND sar.lease_expires_at<=now()) OR (sar.state='failed' AND sar.safe_error_code='storage_missing'))
   ORDER BY coalesce(sar.lease_expires_at,sar.failed_at,sar.created_at) FOR UPDATE SKIP LOCKED LIMIT p_batch_size
 ), reset_runs AS (
   UPDATE public.source_analysis_runs sar SET state='queued',started_at=NULL,failed_at=NULL,safe_error_code='work_requeued',lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now() FROM candidates c WHERE sar.id=c.id RETURNING c.outbox_event_id
 ), reset_events AS (
   UPDATE public.outbox_events oe SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now() FROM reset_runs r WHERE oe.id=r.outbox_event_id AND oe.delivery_state='delivered' RETURNING oe.id
 ) SELECT count(*) INTO validation_count FROM reset_events;
 WITH candidates AS (
   SELECT dpr.id,dpr.outbox_event_id FROM public.document_processing_runs dpr
   WHERE dpr.outbox_event_id IS NOT NULL AND ((dpr.state='running' AND dpr.lease_expires_at<=now()) OR dpr.state='failed')
   ORDER BY coalesce(dpr.lease_expires_at,dpr.failed_at,dpr.created_at) FOR UPDATE SKIP LOCKED LIMIT p_batch_size
 ), reset_runs AS (
   UPDATE public.document_processing_runs dpr SET state='queued',stage='queued',started_at=NULL,failed_at=NULL,safe_error_code='work_requeued',lease_token=NULL,lease_expires_at=NULL,heartbeat_at=now() FROM candidates c WHERE dpr.id=c.id RETURNING c.outbox_event_id
 ), reset_events AS (
   UPDATE public.outbox_events oe SET delivery_state='pending',delivered_at=NULL,failed_at=NULL,lease_token=NULL,lease_expires_at=NULL,next_attempt_at=now(),last_error_code='dispatch_failed',updated_at=now() FROM reset_runs r WHERE oe.id=r.outbox_event_id AND oe.delivery_state='delivered' RETURNING oe.id
 ) SELECT count(*) INTO processing_count FROM reset_events;
 RETURN QUERY SELECT validation_count,processing_count;
END $$;

REVOKE ALL ON FUNCTION public.document_retained_asset_bytes(uuid), public.document_platform_retained_asset_bytes(), public.reconcile_document_processing_work(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_document_processing_work(integer) TO service_role;
COMMIT;
