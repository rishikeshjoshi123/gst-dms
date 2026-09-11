-- Preserve original upload provenance through shared Intake triage and expose
-- only a content-safe uploader comparison label to authorised legal workers.
BEGIN;

ALTER FUNCTION public.get_document_hub_intake(text,integer,integer,uuid)
  RENAME TO get_document_hub_intake_before_uploader_context;
REVOKE ALL ON FUNCTION public.get_document_hub_intake_before_uploader_context(text,integer,integer,uuid)
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.get_document_hub_intake(
  p_scope text DEFAULT 'mine',p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,
  p_include_id uuid DEFAULT NULL
)
RETURNS TABLE(
  id uuid,state public.intake_item_state,failure_code text,created_at timestamptz,
  intended_matter_id uuid,declared_filename text,is_mine boolean,
  uploaded_by uuid,uploaded_by_name text,total_count bigint
)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  SELECT source.id,source.state,source.failure_code,source.created_at,
    source.intended_matter_id,source.declared_filename,source.is_mine,
    intake.uploaded_by,
    coalesce(nullif(btrim(profile.display_name),''),'Team member') AS uploaded_by_name,
    source.total_count
  FROM public.get_document_hub_intake_before_uploader_context(
    p_scope,p_offset,p_limit,p_include_id
  ) source
  JOIN public.intake_items intake ON intake.id=source.id
  LEFT JOIN public.user_profiles profile ON profile.user_id=intake.uploaded_by
$$;

CREATE OR REPLACE FUNCTION public.assign_intake_to_new_document(
  p_intake_id uuid,p_matter_id uuid,p_display_title text,
  p_expected_intake_uploader uuid,p_idempotency uuid
)
RETURNS TABLE(code text,document_id uuid,document_version_id uuid,lifecycle_revision bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE
  x record;
  i public.intake_items%ROWTYPE;
  asset public.file_assets%ROWTYPE;
  d uuid;
  v uuid;
  rev bigint;
  prior public.document_command_receipts%ROWTYPE;
BEGIN
  SELECT * INTO x FROM public.document_materialization_actor('document.intake.assign') LIMIT 1;
  IF x.org_id IS NULL OR p_idempotency IS NULL OR p_display_title IS NULL
     OR char_length(p_display_title) NOT BETWEEN 1 AND 255 OR p_display_title ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(x.org_id::text),
    pg_catalog.hashtext(x.actor_id::text||':assign_intake:'||p_idempotency::text)
  );
  SELECT * INTO prior FROM public.document_command_receipts
  WHERE org_id=x.org_id AND actor_user_id=x.actor_id
    AND command_kind='assign_intake' AND idempotency_key=p_idempotency;
  IF prior.id IS NOT NULL THEN
    IF prior.subject_id IS DISTINCT FROM p_intake_id THEN
      RETURN QUERY SELECT 'idempotency_subject_mismatch'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    ELSE
      RETURN QUERY SELECT prior.result_code,prior.document_id,
        prior.document_version_id,prior.lifecycle_revision;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO i FROM public.intake_items
  WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  IF i.id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;
  IF i.uploaded_by IS DISTINCT FROM p_expected_intake_uploader OR i.uploaded_by IS NULL THEN
    RETURN QUERY SELECT 'uploader_mismatch'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;
  IF i.state<>'ready' OR EXISTS(
    SELECT 1 FROM public.intake_item_assignments assignment
    WHERE assignment.org_id=x.org_id AND assignment.intake_item_id=i.id
  ) THEN
    RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;
  SELECT * INTO asset FROM public.file_assets
  WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF asset.id IS NULL OR asset.sha256 IS NULL OR asset.sha256 !~ '^[0-9a-f]{64}$' THEN
    RETURN QUERY SELECT 'intake_unavailable'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(x.org_id::text),pg_catalog.hashtext(asset.sha256)
  );
  SELECT * INTO i FROM public.intake_items
  WHERE id=p_intake_id AND org_id=x.org_id FOR UPDATE;
  SELECT * INTO asset FROM public.file_assets
  WHERE id=i.asset_id AND org_id=x.org_id FOR UPDATE;
  IF i.state<>'ready' OR asset.id IS NULL OR asset.sha256 IS NULL OR EXISTS(
    SELECT 1 FROM public.document_versions existing
    WHERE existing.org_id=x.org_id AND existing.asset_id=asset.id
      AND existing.validation_state='valid'
      AND existing.state IN ('current','superseded')
  ) THEN
    INSERT INTO public.document_command_receipts(
      org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code
    ) VALUES(x.org_id,x.actor_id,'assign_intake',p_idempotency,i.id,'duplicate_reference');
    RETURN QUERY SELECT 'duplicate_reference'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.matters matter
    JOIN public.clients client
      ON client.id=matter.client_id AND client.org_id=matter.org_id
    WHERE matter.id=p_matter_id AND matter.org_id=x.org_id AND matter.status='active'
      AND matter.deleted_at IS NULL AND matter.record_state='active'
      AND client.deleted_at IS NULL AND client.record_state='active'
  ) THEN
    RETURN QUERY SELECT 'invalid_matter'::text,NULL::uuid,NULL::uuid,NULL::bigint;
    RETURN;
  END IF;

  INSERT INTO public.documents AS document_record(
    org_id,matter_id,display_title,origin_kind,record_state,content_availability,
    status,storage_path,created_by
  ) VALUES(
    x.org_id,p_matter_id,p_display_title,'upload','active','metadata_only',
    'placed',NULL,i.uploaded_by
  ) RETURNING document_record.id INTO d;
  v:=public.document_materialization_insert_version(x.org_id,d,i.id,i.uploaded_by,NULL);
  UPDATE public.documents AS document_record
  SET current_version_id=v,content_availability='source_attached',
    effective_filename=(
      SELECT version.original_filename FROM public.document_versions version WHERE version.id=v
    ),
    effective_size_bytes=(
      SELECT source.byte_size FROM public.file_assets source
      JOIN public.document_versions version ON version.asset_id=source.id
      WHERE version.id=v
    )
  WHERE document_record.id=d
  RETURNING document_record.lifecycle_revision INTO rev;
  INSERT INTO public.intake_item_assignments(
    org_id,intake_item_id,document_id,document_version_id,assigned_by
  ) VALUES(x.org_id,i.id,d,v,x.actor_id);
  UPDATE public.intake_items
  SET state='assigned',assigned_at=now(),updated_at=now()
  WHERE id=i.id;
  INSERT INTO public.activity_logs(
    org_id,user_id,action,entity_type,entity_id,description,metadata
  ) VALUES(
    x.org_id,x.actor_id,'document.intake_assigned','document',d,
    'Assigned validated intake to a new document',
    jsonb_build_object('document_id',d::text,'version_id',v::text)
  );
  INSERT INTO public.document_command_receipts(
    org_id,actor_user_id,command_kind,idempotency_key,subject_id,result_code,
    document_id,document_version_id,lifecycle_revision
  ) VALUES(x.org_id,x.actor_id,'assign_intake',p_idempotency,i.id,'ok',d,v,rev);
  PERFORM public.document_materialization_safe_event(
    x.org_id,d,'document.processing_requested.v1','document.processing.assign.'||v::text,
    jsonb_build_object('document_id',d::text,'version_id',v::text,'intake_id',i.id::text)
  );
  RETURN QUERY SELECT 'ok'::text,d,v,rev;
END $$;

REVOKE ALL ON FUNCTION
  public.get_document_hub_intake(text,integer,integer,uuid),
  public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION
  public.get_document_hub_intake(text,integer,integer,uuid),
  public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_document_hub_intake(text,integer,integer,uuid) IS
  'Capability-scoped Intake projection with original uploader id and content-safe display name; no email or storage locator.';
COMMENT ON FUNCTION public.assign_intake_to_new_document(uuid,uuid,text,uuid,uuid) IS
  'Authenticated Intake assignment preserving original uploader document/version provenance while recording the assigning actor separately.';

COMMIT;
