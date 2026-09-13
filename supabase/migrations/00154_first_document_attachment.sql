-- D05-T01: immutable, server-authorised first-PDF intent; no replacement path.
BEGIN;
ALTER TABLE public.organisation_memberships ADD CONSTRAINT memberships_attachment_lineage UNIQUE(org_id,user_id,id);
ALTER TABLE public.upload_sessions ADD CONSTRAINT sessions_attachment_lineage UNIQUE(org_id,created_by,id);
ALTER TABLE public.intake_items ADD CONSTRAINT intake_attachment_lineage UNIQUE(org_id,upload_session_id,id);
CREATE TABLE public.document_attachment_intents (
  upload_session_id uuid PRIMARY KEY,
  intake_item_id uuid NOT NULL UNIQUE,
  org_id uuid NOT NULL REFERENCES public.organisations(id),
  document_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  document_revision bigint NOT NULL CHECK(document_revision>0),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  membership_id uuid NOT NULL,
  state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','attached','rejected')),
  result_code text CHECK(result_code IN ('ok','target_unavailable','stale_target','source_already_attached','upload_unavailable','duplicate_reference','not_allowed','expired')),
  document_version_id uuid,
  result_revision bigint,
  FOREIGN KEY(org_id,actor_user_id,upload_session_id) REFERENCES public.upload_sessions(org_id,created_by,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,upload_session_id,intake_item_id) REFERENCES public.intake_items(org_id,upload_session_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,document_id) REFERENCES public.documents(org_id,id) ON DELETE CASCADE,
  FOREIGN KEY(org_id,matter_id) REFERENCES public.matters(org_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,actor_user_id,membership_id) REFERENCES public.organisation_memberships(org_id,user_id,id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,document_id,document_version_id) REFERENCES public.document_versions(org_id,document_id,id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK((state='pending' AND result_code IS NULL AND document_version_id IS NULL) OR (state='attached' AND result_code='ok' AND document_version_id IS NOT NULL AND result_revision IS NOT NULL) OR (state='rejected' AND result_code<>'ok' AND document_version_id IS NULL))
);
CREATE INDEX document_attachment_intents_document ON public.document_attachment_intents(org_id,document_id,created_at DESC);
CREATE TABLE public.document_attachment_baselines (
  document_version_id uuid PRIMARY KEY,
  org_id uuid NOT NULL REFERENCES public.organisations(id),
  document_id uuid NOT NULL,
  record_created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  FOREIGN KEY(org_id,document_id,document_version_id) REFERENCES public.document_versions(org_id,document_id,id) ON DELETE CASCADE,
  origin_kind text NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  metadata jsonb NOT NULL CHECK(jsonb_typeof(metadata)='object' AND metadata-ARRAY['doc_type','reference_number','doc_date','direction','issued_by','financial_year','summary','raw_metadata','ai_prompt_version']='{}'::jsonb)
);
CREATE FUNCTION public.document_attachment_baseline_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  -- The governed purge deletes the bound version; ordinary table writes cannot
  -- invoke an FK cascade, and neither application role can delete versions.
  IF TG_OP='DELETE' AND pg_trigger_depth()>1 THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'Attachment baseline is immutable';
END $$;
CREATE TRIGGER document_attachment_baselines_immutable BEFORE UPDATE OR DELETE ON public.document_attachment_baselines FOR EACH ROW EXECUTE FUNCTION public.document_attachment_baseline_guard();
CREATE FUNCTION public.document_attachment_intent_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='DELETE' AND pg_trigger_depth()>1 THEN RETURN OLD; END IF;
  IF TG_OP='DELETE' OR ROW(NEW.upload_session_id,NEW.intake_item_id,NEW.org_id,NEW.document_id,NEW.matter_id,NEW.document_revision,NEW.actor_user_id,NEW.membership_id,NEW.created_at) IS DISTINCT FROM ROW(OLD.upload_session_id,OLD.intake_item_id,OLD.org_id,OLD.document_id,OLD.matter_id,OLD.document_revision,OLD.actor_user_id,OLD.membership_id,OLD.created_at) OR OLD.state<>'pending' THEN RAISE EXCEPTION 'Attachment intent is immutable'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_attachment_intents_immutable BEFORE UPDATE OR DELETE ON public.document_attachment_intents FOR EACH ROW EXECUTE FUNCTION public.document_attachment_intent_guard();

CREATE FUNCTION public.document_attachment_actor(p_lock boolean DEFAULT false)
RETURNS TABLE(org_id uuid,actor_user_id uuid,membership_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE member public.organisation_memberships%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  IF p_lock THEN PERFORM 1 FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended') ORDER BY m.id FOR SHARE; END IF;
  IF (SELECT count(*) FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state IN ('active','suspended'))<>1 THEN RETURN; END IF;
  SELECT * INTO member FROM public.organisation_memberships m WHERE m.user_id=auth.uid() AND m.state='active';
  IF member.id IS NULL OR NOT EXISTS(SELECT 1 FROM public.organisations o WHERE o.id=member.org_id AND 'document.version.attach'=ANY(public.organisation_member_capabilities(member.role,o.owner_membership_id=member.id,member.state))) THEN RETURN; END IF;
  RETURN QUERY SELECT member.org_id,member.user_id,member.id;
END $$;

ALTER FUNCTION public.reserve_document_upload(text,text,bigint,uuid,uuid) RENAME TO reserve_document_upload_before_attachment;
CREATE FUNCTION public.reserve_document_upload(p_filename text,p_mime text,p_declared_bytes bigint,p_intended_matter uuid,p_idempotency uuid)
RETURNS TABLE(code text,upload_session_id uuid,intake_item_id uuid,asset_id uuid,bucket_id text,object_key text,expires_at timestamptz,retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record;
BEGIN
  SELECT * INTO actor FROM public.document_attachment_actor();
  IF actor.org_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtext(actor.org_id::text),hashtext(actor.actor_user_id::text||':'||p_idempotency::text));
    IF EXISTS(SELECT 1 FROM public.upload_sessions s JOIN public.document_attachment_intents a ON a.upload_session_id=s.id WHERE s.org_id=actor.org_id AND s.created_by=actor.actor_user_id AND s.idempotency_key=p_idempotency) THEN RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
  END IF;
  RETURN QUERY SELECT * FROM public.reserve_document_upload_before_attachment(p_filename,p_mime,p_declared_bytes,p_intended_matter,p_idempotency);
END $$;

CREATE FUNCTION public.reserve_document_attachment(p_document_id uuid,p_filename text,p_declared_bytes bigint,p_idempotency uuid)
RETURNS TABLE(code text,upload_session_id uuid,intake_item_id uuid,asset_id uuid,bucket_id text,object_key text,expires_at timestamptz,retry_after timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; d public.documents%ROWTYPE; prior public.upload_sessions%ROWTYPE; intent public.document_attachment_intents%ROWTYPE; reserved record;
BEGIN
  SELECT * INTO actor FROM public.document_attachment_actor(true);
  IF actor.org_id IS NULL OR p_document_id IS NULL OR p_idempotency IS NULL THEN RETURN QUERY SELECT 'not_allowed',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
  -- Same actor/key fence as ordinary upload, so its intent cannot be rebound.
  PERFORM pg_advisory_xact_lock(hashtext(actor.org_id::text),hashtext(actor.actor_user_id::text||':'||p_idempotency::text));
  SELECT * INTO prior FROM public.upload_sessions s WHERE s.org_id=actor.org_id AND s.created_by=actor.actor_user_id AND s.idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    SELECT * INTO intent FROM public.document_attachment_intents a WHERE a.upload_session_id=prior.id;
    IF intent.document_id IS DISTINCT FROM p_document_id OR prior.declared_filename IS DISTINCT FROM p_filename OR prior.declared_byte_size IS DISTINCT FROM p_declared_bytes THEN RETURN QUERY SELECT 'idempotency_conflict',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
    -- Replay binds immutable subject/bytes before consulting mutable target
    -- state. Completed transfers never mint another Storage upload token.
    IF prior.state='finalized' THEN RETURN QUERY SELECT 'already_completed',prior.id,intent.intake_item_id,prior.asset_id,NULL::text,NULL::text,prior.expires_at,NULL::timestamptz; RETURN; END IF;
    IF prior.state<>'reserved' OR prior.expires_at<=clock_timestamp() THEN RETURN QUERY SELECT * FROM public.reserve_document_upload_before_attachment(p_filename,'application/pdf',p_declared_bytes,intent.matter_id,p_idempotency); RETURN; END IF;
  END IF;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended(p_document_id::text,1521));
  PERFORM 1 FROM public.clients c JOIN public.matters m ON m.client_id=c.id AND m.org_id=c.org_id JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=p_document_id AND doc.org_id=actor.org_id FOR SHARE OF c;
  PERFORM 1 FROM public.matters m JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=p_document_id AND doc.org_id=actor.org_id FOR SHARE OF m;
  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=actor.org_id FOR UPDATE;
  IF d.id IS NULL OR NOT public.review_document_available(actor.org_id,p_document_id) THEN RETURN QUERY SELECT 'target_unavailable',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
  IF d.content_availability<>'metadata_only' OR d.current_version_id IS NOT NULL OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=d.id) THEN RETURN QUERY SELECT 'source_already_attached',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
  IF intent.document_revision IS NOT NULL AND (intent.document_revision<>d.lifecycle_revision OR intent.matter_id<>d.matter_id OR intent.membership_id<>actor.membership_id) THEN RETURN QUERY SELECT 'stale_target',NULL::uuid,NULL::uuid,NULL::uuid,NULL::text,NULL::text,NULL::timestamptz,NULL::timestamptz; RETURN; END IF;
  SELECT * INTO reserved FROM public.reserve_document_upload_before_attachment(p_filename,'application/pdf',p_declared_bytes,d.matter_id,p_idempotency);
  IF reserved.code='ok' AND prior.id IS NULL THEN
    INSERT INTO public.document_attachment_intents(upload_session_id,intake_item_id,org_id,document_id,matter_id,document_revision,actor_user_id,membership_id)
      VALUES(reserved.upload_session_id,reserved.intake_item_id,actor.org_id,d.id,d.matter_id,d.lifecycle_revision,actor.actor_user_id,actor.membership_id);
  END IF;
  RETURN QUERY SELECT reserved.code::text,reserved.upload_session_id::uuid,reserved.intake_item_id::uuid,reserved.asset_id::uuid,reserved.bucket_id::text,reserved.object_key::text,reserved.expires_at::timestamptz,reserved.retry_after::timestamptz;
END $$;

ALTER FUNCTION public.complete_document_upload(uuid,bigint,text,text,uuid,uuid,uuid) RENAME TO complete_document_upload_before_attachment;
CREATE FUNCTION public.complete_document_upload(p_session uuid,p_observed_bytes bigint,p_sha256 text,p_detected_mime text,p_idempotency uuid,p_actor uuid,p_org uuid)
RETURNS TABLE(code text,upload_session_id uuid,intake_item_id uuid,asset_id uuid,duplicate_asset_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE intent public.document_attachment_intents%ROWTYPE; d public.documents%ROWTYPE; failed text;
BEGIN
  SELECT a.* INTO intent FROM public.document_attachment_intents a JOIN public.upload_sessions s ON s.id=a.upload_session_id WHERE a.upload_session_id=p_session AND a.org_id=p_org AND a.actor_user_id=p_actor AND s.idempotency_key=p_idempotency;
  IF intent.upload_session_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock_shared(hashtextextended(intent.document_id::text,1521));
    PERFORM 1 FROM public.clients c JOIN public.matters m ON m.client_id=c.id AND m.org_id=c.org_id JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=intent.document_id AND doc.org_id=intent.org_id FOR SHARE OF c;
    PERFORM 1 FROM public.matters m JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=intent.document_id AND doc.org_id=intent.org_id FOR SHARE OF m;
    SELECT * INTO d FROM public.documents WHERE id=intent.document_id AND org_id=intent.org_id FOR UPDATE;
    IF NOT EXISTS(SELECT 1 FROM public.document_upload_command_receipts receipt WHERE receipt.upload_session_id=p_session AND receipt.command='complete' AND receipt.idempotency_key=p_idempotency) THEN
      IF d.id IS NULL OR NOT public.review_document_available(intent.org_id,intent.document_id) THEN failed:='target_unavailable';
      ELSIF d.current_version_id IS NOT NULL OR d.content_availability<>'metadata_only' OR EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=d.id) THEN failed:='source_already_attached';
      ELSIF d.lifecycle_revision<>intent.document_revision OR d.matter_id<>intent.matter_id THEN failed:='stale_target'; END IF;
      IF failed IS NOT NULL THEN RETURN QUERY SELECT failed,p_session,intent.intake_item_id,NULL::uuid,NULL::uuid; RETURN; END IF;
    END IF;
  END IF;
  RETURN QUERY SELECT * FROM public.complete_document_upload_before_attachment(p_session,p_observed_bytes,p_sha256,p_detected_mime,p_idempotency,p_actor,p_org);
END $$;

CREATE FUNCTION public.read_document_attachment(p_document_id uuid,p_intake_id uuid DEFAULT NULL)
RETURNS TABLE(eligible boolean,state text,document_version_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; d public.documents%ROWTYPE; intent public.document_attachment_intents%ROWTYPE; intake public.intake_items%ROWTYPE; session public.upload_sessions%ROWTYPE;
BEGIN
  SELECT * INTO actor FROM public.document_attachment_actor();
  IF actor.org_id IS NULL THEN RETURN; END IF;
  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=actor.org_id;
  IF d.id IS NULL OR NOT public.review_document_available(actor.org_id,d.id) THEN RETURN; END IF;
  IF p_intake_id IS NOT NULL THEN
    SELECT * INTO intent FROM public.document_attachment_intents a WHERE a.intake_item_id=p_intake_id AND a.document_id=d.id AND a.org_id=actor.org_id AND a.actor_user_id=actor.actor_user_id;
    IF intent.upload_session_id IS NULL THEN RETURN; END IF;
    SELECT * INTO intake FROM public.intake_items WHERE id=p_intake_id AND org_id=actor.org_id;
    SELECT * INTO session FROM public.upload_sessions WHERE id=intent.upload_session_id AND org_id=actor.org_id;
    RETURN QUERY SELECT false,CASE WHEN intent.state='attached' THEN 'attached' WHEN intent.state='rejected' THEN intent.result_code WHEN intake.state='duplicate' THEN 'duplicate' WHEN session.state='cancelled' THEN 'cancelled' WHEN session.state='expired' OR (session.state<>'finalized' AND session.expires_at<=clock_timestamp()) THEN 'expired' WHEN intake.state IN ('failed','discarded') OR session.state='failed' THEN 'upload_unavailable' ELSE 'validating' END,intent.document_version_id;
  ELSE
    RETURN QUERY SELECT d.current_version_id IS NULL AND d.content_availability='metadata_only' AND NOT EXISTS(SELECT 1 FROM public.document_versions WHERE document_id=d.id),'available',d.current_version_id;
  END IF;
END $$;

-- Other assignment paths cannot consume a targeted attachment as a new record.
CREATE FUNCTION public.document_attachment_assignment_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE intent public.document_attachment_intents%ROWTYPE;
BEGIN
  SELECT * INTO intent FROM public.document_attachment_intents WHERE intake_item_id=NEW.intake_item_id;
  IF intent.upload_session_id IS NOT NULL AND (intent.org_id<>NEW.org_id OR intent.document_id<>NEW.document_id OR intent.actor_user_id<>NEW.assigned_by OR NOT EXISTS(SELECT 1 FROM public.document_versions WHERE id=NEW.document_version_id AND document_id=intent.document_id AND version_number=1)) THEN RAISE EXCEPTION 'Attachment cannot be assigned to another document'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_attachment_assignment_guard BEFORE INSERT OR UPDATE ON public.intake_item_assignments FOR EACH ROW EXECUTE FUNCTION public.document_attachment_assignment_guard();

INSERT INTO public.activity_event_definitions(event_type,event_version,category,subject_types,default_visibility,metadata_contract,renderer_key)
VALUES('document.file_attached',1,'document',ARRAY['document'],'matter','{"version_number":"integer"}','document.file_attached.v1');

CREATE FUNCTION public.materialize_document_attachment(p_intake_id uuid,p_validation_event_id uuid)
RETURNS TABLE(code text,document_id uuid,document_version_id uuid,lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE intent public.document_attachment_intents%ROWTYPE; d public.documents%ROWTYPE; i public.intake_items%ROWTYPE; s public.upload_sessions%ROWTYPE; asset public.file_assets%ROWTYPE; ev public.outbox_events%ROWTYPE; member public.organisation_memberships%ROWTYPE; outcome text; version_id uuid; rev bigint; client_id_value uuid;
BEGIN
  SELECT * INTO intent FROM public.document_attachment_intents WHERE intake_item_id=p_intake_id;
  IF intent.upload_session_id IS NULL THEN RETURN QUERY SELECT 'not_attachment',NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO ev FROM public.outbox_events WHERE id=p_validation_event_id AND org_id=intent.org_id AND aggregate_type='document' AND aggregate_id=p_intake_id AND event_kind='document.intake_validated.v1' FOR UPDATE;
  IF ev.id IS NULL THEN RETURN QUERY SELECT 'invalid_event',NULL::uuid,NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO member FROM public.organisation_memberships WHERE id=intent.membership_id FOR SHARE;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended(intent.document_id::text,1521));
  SELECT m.client_id INTO client_id_value FROM public.matters m JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=intent.document_id AND doc.org_id=intent.org_id;
  PERFORM 1 FROM public.clients WHERE id=client_id_value AND org_id=intent.org_id FOR SHARE;
  PERFORM 1 FROM public.matters WHERE id=intent.matter_id AND org_id=intent.org_id FOR SHARE;
  SELECT * INTO d FROM public.documents WHERE id=intent.document_id AND org_id=intent.org_id FOR UPDATE;
  SELECT * INTO s FROM public.upload_sessions WHERE id=intent.upload_session_id AND org_id=intent.org_id FOR UPDATE;
  SELECT * INTO i FROM public.intake_items WHERE id=p_intake_id AND org_id=intent.org_id FOR UPDATE;
  SELECT * INTO intent FROM public.document_attachment_intents WHERE intake_item_id=p_intake_id FOR UPDATE;
  IF intent.state<>'pending' THEN RETURN QUERY SELECT intent.result_code,intent.document_id,intent.document_version_id,intent.result_revision; RETURN; END IF;
  IF member.id IS NULL OR member.state<>'active' OR member.user_id<>intent.actor_user_id OR member.org_id<>intent.org_id OR NOT EXISTS(SELECT 1 FROM public.organisations o WHERE o.id=member.org_id AND 'document.version.attach'=ANY(public.organisation_member_capabilities(member.role,o.owner_membership_id=member.id,member.state))) THEN outcome:='not_allowed';
  ELSIF d.id IS NULL OR NOT public.review_document_available(intent.org_id,intent.document_id) THEN outcome:='target_unavailable';
  ELSIF d.current_version_id IS NOT NULL OR d.content_availability<>'metadata_only' OR EXISTS(SELECT 1 FROM public.document_versions v WHERE v.document_id=d.id) THEN outcome:='source_already_attached';
  ELSIF d.lifecycle_revision<>intent.document_revision OR d.matter_id<>intent.matter_id THEN outcome:='stale_target';
  ELSIF s.state<>'finalized' AND s.expires_at<=clock_timestamp() THEN outcome:='expired';
  ELSIF s.id IS NULL OR s.state<>'finalized' OR s.created_by<>intent.actor_user_id OR i.id IS NULL OR i.uploaded_by<>intent.actor_user_id OR i.upload_session_id<>s.id OR i.intended_matter_id IS DISTINCT FROM intent.matter_id OR i.state<>'ready' OR EXISTS(SELECT 1 FROM public.intake_item_assignments WHERE intake_item_id=i.id) THEN outcome:='upload_unavailable';
  END IF;
  IF outcome IS NULL THEN
    SELECT * INTO asset FROM public.file_assets WHERE id=i.asset_id AND org_id=intent.org_id FOR UPDATE;
    IF asset.id IS NULL OR asset.availability<>'available' OR asset.validated_page_count IS NULL OR asset.sha256 IS NULL THEN outcome:='upload_unavailable';
    ELSE
      PERFORM pg_advisory_xact_lock(hashtext(intent.org_id::text),hashtext(asset.sha256));
      IF EXISTS(SELECT 1 FROM public.document_versions WHERE org_id=intent.org_id AND asset_id=asset.id AND validation_state='valid' AND state IN ('current','superseded')) THEN outcome:='duplicate_reference'; END IF;
    END IF;
  END IF;
  IF outcome IS NOT NULL THEN
    UPDATE public.document_attachment_intents SET state='rejected',result_code=outcome WHERE upload_session_id=intent.upload_session_id;
    RETURN QUERY SELECT outcome,intent.document_id,NULL::uuid,NULL::bigint; RETURN;
  END IF;
  version_id:=public.document_materialization_insert_version(intent.org_id,d.id,i.id,intent.actor_user_id,NULL);
  INSERT INTO public.document_attachment_baselines(document_version_id,org_id,document_id,record_created_by,origin_kind,metadata)
    VALUES(version_id,d.org_id,d.id,d.created_by,d.origin_kind,jsonb_build_object('doc_type',d.doc_type,'reference_number',d.reference_number,'doc_date',d.doc_date,'direction',d.direction,'issued_by',d.issued_by,'financial_year',d.financial_year,'summary',d.summary,'raw_metadata',d.raw_metadata,'ai_prompt_version',d.ai_prompt_version));
  UPDATE public.documents SET current_version_id=version_id,content_availability='source_attached',effective_filename=s.declared_filename,effective_size_bytes=asset.byte_size WHERE id=d.id RETURNING documents.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(org_id,intake_item_id,document_id,document_version_id,assigned_by) VALUES(intent.org_id,i.id,d.id,version_id,intent.actor_user_id);
  UPDATE public.intake_items SET state='assigned',assigned_at=clock_timestamp(),updated_at=clock_timestamp() WHERE id=i.id;
  UPDATE public.document_attachment_intents SET state='attached',result_code='ok',document_version_id=version_id,result_revision=rev WHERE upload_session_id=intent.upload_session_id;
  PERFORM public.append_activity_event(d.org_id,'document.file_attached',1::smallint,'user',intent.actor_user_id,'Member','document',d.id,client_id_value,d.matter_id,'Document','First PDF attached',jsonb_build_object('version_number',1),'document',d.id,version_id,intent.upload_session_id,NULL,'document.attach.'||intent.upload_session_id,clock_timestamp());
  PERFORM public.document_materialization_safe_event(d.org_id,d.id,'document.processing_requested.v1','document.processing.attach.'||version_id,jsonb_build_object('document_id',d.id,'version_id',version_id,'intake_id',i.id));
  RETURN QUERY SELECT 'ok',d.id,version_id,rev;
END $$;

ALTER FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) RENAME TO auto_assign_intended_matter_intake_before_attachment;
CREATE FUNCTION public.auto_assign_intended_matter_intake(p_intake_id uuid,p_validation_event_id uuid)
RETURNS TABLE(code text,document_id uuid,document_version_id uuid,lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM public.document_attachment_intents WHERE intake_item_id=p_intake_id) THEN RETURN QUERY SELECT * FROM public.materialize_document_attachment(p_intake_id,p_validation_event_id);
  ELSE RETURN QUERY SELECT * FROM public.auto_assign_intended_matter_intake_before_attachment(p_intake_id,p_validation_event_id); END IF;
END $$;

-- Preserve the accepted Intake command, but never trust its browser-supplied
-- uploader hint or let it consume an immutable first-upload target.
ALTER FUNCTION public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid) RENAME TO attach_intake_to_document_before_attachment;
CREATE FUNCTION public.attach_intake_to_document(p_document_id uuid,p_intake_id uuid,p_expected_revision bigint,p_expected_intake_uploader uuid,p_idempotency uuid)
RETURNS TABLE(code text,document_version_id uuid,lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE actor record; d public.documents%ROWTYPE; uploader uuid; result record; client_value uuid; inserted integer;
BEGIN
  SELECT * INTO actor FROM public.document_attachment_actor(true);
  IF actor.org_id IS NULL OR p_idempotency IS NULL THEN RETURN QUERY SELECT 'invalid_request',NULL::uuid,NULL::bigint; RETURN; END IF;
  IF EXISTS(SELECT 1 FROM public.document_attachment_intents WHERE intake_item_id=p_intake_id) THEN RETURN QUERY SELECT 'intake_unavailable',NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT uploaded_by INTO uploader FROM public.intake_items WHERE id=p_intake_id AND org_id=actor.org_id;
  IF uploader IS NULL THEN RETURN QUERY SELECT 'not_found',NULL::uuid,NULL::bigint; RETURN; END IF;
  PERFORM pg_advisory_xact_lock(hashtext(actor.org_id::text),hashtext(actor.actor_user_id::text||':attach_intake:'||p_idempotency::text));
  -- Receipt replay remains governed by the original subject-bound authority.
  IF EXISTS(SELECT 1 FROM public.document_command_receipts WHERE org_id=actor.org_id AND actor_user_id=actor.actor_user_id AND command_kind='attach_intake' AND idempotency_key=p_idempotency) THEN RETURN QUERY SELECT * FROM public.attach_intake_to_document_before_attachment(p_document_id,p_intake_id,p_expected_revision,uploader,p_idempotency); RETURN; END IF;
  PERFORM pg_advisory_xact_lock_shared(hashtextextended(p_document_id::text,1521));
  SELECT m.client_id INTO client_value FROM public.matters m JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=p_document_id AND doc.org_id=actor.org_id;
  PERFORM 1 FROM public.clients WHERE id=client_value AND org_id=actor.org_id FOR SHARE;
  PERFORM 1 FROM public.matters m JOIN public.documents doc ON doc.matter_id=m.id AND doc.org_id=m.org_id WHERE doc.id=p_document_id AND doc.org_id=actor.org_id FOR SHARE OF m;
  SELECT * INTO d FROM public.documents WHERE id=p_document_id AND org_id=actor.org_id FOR UPDATE;
  IF d.id IS NULL OR NOT public.review_document_available(actor.org_id,d.id) THEN RETURN QUERY SELECT 'record_trashed',NULL::uuid,NULL::bigint; RETURN; END IF;
  SELECT * INTO result FROM public.attach_intake_to_document_before_attachment(p_document_id,p_intake_id,p_expected_revision,uploader,p_idempotency);
  IF result.code='ok' THEN
    INSERT INTO public.document_attachment_baselines(document_version_id,org_id,document_id,record_created_by,origin_kind,metadata)
      VALUES(result.document_version_id,d.org_id,d.id,d.created_by,d.origin_kind,jsonb_build_object('doc_type',d.doc_type,'reference_number',d.reference_number,'doc_date',d.doc_date,'direction',d.direction,'issued_by',d.issued_by,'financial_year',d.financial_year,'summary',d.summary,'raw_metadata',d.raw_metadata,'ai_prompt_version',d.ai_prompt_version)) ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS inserted=ROW_COUNT;
    IF inserted=1 THEN PERFORM public.append_activity_event(d.org_id,'document.file_attached',1::smallint,'user',actor.actor_user_id,'Member','document',d.id,client_value,d.matter_id,'Document','First PDF attached',jsonb_build_object('version_number',1),'document',d.id,result.document_version_id,NULL,NULL,'document.attach.intake.'||p_intake_id,clock_timestamp()); END IF;
  END IF;
  RETURN QUERY SELECT result.code::text,result.document_version_id::uuid,result.lifecycle_revision::bigint;
END $$;

-- Record provenance is not PDF evidence. Compare only exact scalar contracts;
-- structured references/periods/actors and summaries are intentionally excluded.
CREATE FUNCTION public.attachment_review_baseline(p_version uuid,p_field text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT jsonb_build_object('value',b.metadata->CASE p_field WHEN 'document.type' THEN 'doc_type' WHEN 'document.reference_number' THEN 'reference_number' WHEN 'document.date' THEN 'doc_date' WHEN 'document.issued_by' THEN 'issued_by' WHEN 'document.direction' THEN 'direction' END,'origin_kind',b.origin_kind,'captured_at',b.captured_at)
  FROM public.document_attachment_baselines b WHERE b.document_version_id=p_version
    AND jsonb_typeof(b.metadata->CASE p_field WHEN 'document.type' THEN 'doc_type' WHEN 'document.reference_number' THEN 'reference_number' WHEN 'document.date' THEN 'doc_date' WHEN 'document.issued_by' THEN 'issued_by' WHEN 'document.direction' THEN 'direction' END)='string'
    AND btrim(b.metadata->>CASE p_field WHEN 'document.type' THEN 'doc_type' WHEN 'document.reference_number' THEN 'reference_number' WHEN 'document.date' THEN 'doc_date' WHEN 'document.issued_by' THEN 'issued_by' WHEN 'document.direction' THEN 'direction' END)<>''
$$;
CREATE FUNCTION public.attachment_scalar_comparison(p_field text,p_value text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE value text;
BEGIN
  IF p_value IS NULL OR char_length(p_value)>4000 OR p_field IS NULL OR p_field NOT IN ('document.type','document.direction','document.reference_number','document.issued_by','document.date') THEN RETURN NULL; END IF;
  -- NFKC and Unicode dash folding mirror the conservative identifier contract.
  -- Whitespace and separator boundaries remain boundaries; digits/year segments
  -- are never removed, parsed as numbers, padded, or matched approximately.
  value:=normalize(p_value,NFKC);
  value:=translate(value,U&'\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000',repeat(' ',19));
  value:=btrim(regexp_replace(value,'[[:space:]]+',' ','g'));
  IF p_field='document.reference_number' THEN
    value:=translate(upper(value),U&'\2010\2011\2012\2013\2014\2212','------');
    RETURN regexp_replace(value,'[[:space:]]*[/.:_-]+[[:space:]]*','/','g');
  ELSIF p_field='document.date' THEN
    -- Only year-first numeric spelling is normalized. Never infer a locale or
    -- swap day/month, and reject impossible dates through the date validator.
    IF value ~ '^[0-9]{4}[-/.][0-9]{2}[-/.][0-9]{2}$' THEN
      value:=translate(value,'/.','--');
      IF pg_input_is_valid(value,'date') THEN RETURN value; END IF;
    END IF;
    RETURN value;
  END IF;
  RETURN upper(value);
END $$;
CREATE FUNCTION public.attachment_scalar_disagrees(p_version uuid,p_field text,p_key text,p_value jsonb) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT coalesce(jsonb_typeof(p_value)='string'
    AND NOT EXISTS(SELECT 1 FROM public.document_field_decisions WHERE document_version_id=p_version AND field_path=p_field AND semantic_candidate_key=p_key)
    AND public.attachment_scalar_comparison(p_field,public.attachment_review_baseline(p_version,p_field)->>'value')<>public.attachment_scalar_comparison(p_field,p_value#>>'{}'),false)
$$;
CREATE FUNCTION public.attachment_preserve_finisher_metadata() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF current_setting('casechain.attachment_finisher_version',true)=OLD.current_version_id::text
    AND EXISTS(SELECT 1 FROM public.document_attachment_baselines WHERE document_version_id=OLD.current_version_id AND document_id=OLD.id AND org_id=OLD.org_id) THEN
    NEW.doc_type:=OLD.doc_type; NEW.reference_number:=OLD.reference_number; NEW.doc_date:=OLD.doc_date;
    NEW.direction:=OLD.direction; NEW.issued_by:=OLD.issued_by; NEW.financial_year:=OLD.financial_year;
    NEW.summary:=OLD.summary; NEW.raw_metadata:=OLD.raw_metadata; NEW.ai_prompt_version:=OLD.ai_prompt_version;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER attachment_preserve_finisher_metadata BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.attachment_preserve_finisher_metadata();

ALTER FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) RENAME TO finish_document_processing_ai_extraction_before_attachment;
CREATE FUNCTION public.finish_document_processing_ai_extraction(p_processing_run_id uuid,p_processing_lease_token uuid,p_source_analysis_run_id uuid,p_source_analysis_lease_token uuid,p_outcome text,p_input_tokens bigint,p_output_tokens bigint,p_latency_ms integer,p_candidates jsonb DEFAULT '[]',p_review_required boolean DEFAULT false,p_legacy_metadata jsonb DEFAULT NULL)
RETURNS TABLE(code text,binding_id uuid) LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE version_id uuid; prior_context text:=current_setting('casechain.attachment_finisher_version',true); baseline_conflict boolean:=false;
BEGIN
  SELECT p.document_version_id INTO version_id FROM public.document_processing_runs p JOIN public.document_attachment_baselines b ON b.document_version_id=p.document_version_id AND b.org_id=p.org_id AND b.document_id=p.document_id WHERE p.id=p_processing_run_id;
  IF version_id IS NOT NULL THEN
    PERFORM set_config('casechain.attachment_finisher_version',version_id::text,true);
    IF p_outcome='validated' AND jsonb_typeof(p_candidates)='array' THEN
      SELECT coalesce(bool_or(public.attachment_scalar_disagrees(version_id,c->>'field_path',c->>'semantic_candidate_key',c->'normalized_value')),false) INTO baseline_conflict
        FROM jsonb_array_elements(p_candidates) c WHERE c->>'validation_state' IN ('eligible','provisional');
    END IF;
  END IF;
  RETURN QUERY SELECT * FROM public.finish_document_processing_ai_extraction_before_attachment(p_processing_run_id,p_processing_lease_token,p_source_analysis_run_id,p_source_analysis_lease_token,p_outcome,p_input_tokens,p_output_tokens,p_latency_ms,p_candidates,p_review_required OR baseline_conflict,p_legacy_metadata);
  PERFORM set_config('casechain.attachment_finisher_version',coalesce(prior_context,''),true);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('casechain.attachment_finisher_version',coalesce(prior_context,''),true); RAISE;
END $$;

CREATE OR REPLACE FUNCTION public.reconcile_extraction_conflict_review(p_binding_id uuid,p_create boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE binding public.document_version_analysis_bindings%ROWTYPE; group_row record; item_id uuid; selectable_count integer; candidate_ids uuid[]; key text; conflict boolean; baseline_conflict boolean;
BEGIN
  SELECT * INTO binding FROM public.document_version_analysis_bindings WHERE id=p_binding_id;
  IF binding.id IS NULL OR NOT public.review_document_available(binding.org_id,binding.document_id)
    OR NOT EXISTS(SELECT 1 FROM public.documents WHERE id=binding.document_id AND current_version_id=binding.document_version_id) THEN RETURN; END IF;
  FOR group_row IN
    SELECT DISTINCT c.field_path,c.semantic_candidate_key
    FROM public.document_field_candidates c
    WHERE c.document_version_analysis_binding_id=binding.id
  LOOP
    SELECT array_agg(c.id ORDER BY c.id),count(DISTINCT public.review_candidate_value(c.normalized_value)) FILTER(WHERE c.validation_state IN ('eligible','provisional') AND coalesce(c.normalized_value->>'conflict','false')<>'true'),
      coalesce(bool_or(c.validation_state='conflicting'),false) OR count(DISTINCT public.review_candidate_value(c.normalized_value)) FILTER(WHERE c.validation_state IN ('eligible','provisional'))>1
    INTO candidate_ids,selectable_count,conflict FROM public.review_comparison_candidates(binding.id,group_row.field_path,group_row.semantic_candidate_key,p_create) c;
    SELECT coalesce(bool_or(public.attachment_scalar_disagrees(binding.document_version_id,c.field_path,c.semantic_candidate_key,c.normalized_value)),false) INTO baseline_conflict FROM public.document_field_candidates c WHERE c.id=ANY(candidate_ids) AND c.validation_state IN ('eligible','provisional');
    conflict:=conflict OR baseline_conflict;
    IF NOT conflict THEN
      UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
        WHERE org_id=binding.org_id AND document_id=binding.document_id AND document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key AND status='needs_review';
      CONTINUE;
    END IF;
    IF NOT p_create THEN CONTINUE; END IF;
    key:=md5(binding.document_version_id::text||':'||group_row.field_path||':'||group_row.semantic_candidate_key||':'||candidate_ids::text);
    IF EXISTS(SELECT 1 FROM public.review_items WHERE dedupe_key=key) THEN CONTINUE; END IF;
    UPDATE public.review_items SET status='closed',closure_reason='source_replaced',closed_at=now(),updated_at=now(),revision=revision+1
      WHERE org_id=binding.org_id AND document_id=binding.document_id AND document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key AND status='needs_review';
    INSERT INTO public.review_items(org_id,document_id,document_version_id,binding_id,candidate_sequence,field_path,semantic_candidate_key,can_select,dedupe_key,field_decision_sequence)
      VALUES(binding.org_id,binding.document_id,binding.document_version_id,binding.id,
        (SELECT max(materialization_sequence) FROM public.document_field_candidates WHERE document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key),group_row.field_path,group_row.semantic_candidate_key,selectable_count>=2 AND NOT baseline_conflict,key,
        (SELECT coalesce(max(decision_sequence),0) FROM public.document_field_decisions WHERE document_version_id=binding.document_version_id AND field_path=group_row.field_path AND semantic_candidate_key=group_row.semantic_candidate_key)) RETURNING id INTO item_id;
    INSERT INTO public.review_item_evidence(org_id,review_item_id,candidate_id,ordinal,selectable)
      SELECT binding.org_id,item_id,c.id,row_number() OVER(ORDER BY c.page_number,c.materialization_sequence,c.id),selectable_count>=2 AND NOT baseline_conflict AND c.validation_state IN ('eligible','provisional') AND coalesce(c.normalized_value->>'conflict','false')<>'true'
      FROM public.document_field_candidates c WHERE c.id=ANY(candidate_ids);
  END LOOP;
  PERFORM public.recompute_document_effective_metadata(binding.document_version_id);
END $$;

ALTER FUNCTION public.read_review_detail(uuid) RENAME TO read_review_detail_before_attachment;
CREATE FUNCTION public.read_review_detail(p_review_item_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE detail jsonb;
BEGIN
  detail:=public.read_review_detail_before_attachment(p_review_item_id);
  IF detail IS NULL THEN RETURN NULL; END IF;
  RETURN detail||jsonb_build_object('record_baseline',public.attachment_review_baseline((detail->>'document_version_id')::uuid,detail->>'field_path'));
END $$;

ALTER TABLE public.document_attachment_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_attachment_intents FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_attachment_baselines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_attachment_baselines FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.document_attachment_intents,public.document_attachment_baselines FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.document_attachment_actor(boolean),public.document_attachment_baseline_guard(),public.document_attachment_intent_guard(),public.document_attachment_assignment_guard(),public.materialize_document_attachment(uuid,uuid),public.auto_assign_intended_matter_intake_before_attachment(uuid,uuid),public.attach_intake_to_document_before_attachment(uuid,uuid,bigint,uuid,uuid),public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.attach_intake_to_document(uuid,uuid,bigint,uuid,uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.reserve_document_attachment(uuid,text,bigint,uuid),public.auto_assign_intended_matter_intake(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reserve_document_upload_before_attachment(text,text,bigint,uuid,uuid),public.complete_document_upload_before_attachment(uuid,bigint,text,text,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reserve_document_upload(text,text,bigint,uuid,uuid),public.complete_document_upload(uuid,bigint,text,text,uuid,uuid,uuid),public.read_document_attachment(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reserve_document_upload(text,text,bigint,uuid,uuid),public.read_document_attachment(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_document_upload(uuid,bigint,text,text,uuid,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.reserve_document_attachment(uuid,text,bigint,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auto_assign_intended_matter_intake(uuid,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.attachment_scalar_comparison(text,text),public.attachment_review_baseline(uuid,text),public.attachment_scalar_disagrees(uuid,text,text,jsonb),public.attachment_preserve_finisher_metadata(),public.finish_document_processing_ai_extraction_before_attachment(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb),public.read_review_detail_before_attachment(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb),public.read_review_detail(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finish_document_processing_ai_extraction(uuid,uuid,uuid,uuid,text,bigint,bigint,integer,jsonb,boolean,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_review_detail(uuid) TO authenticated;
COMMIT;
