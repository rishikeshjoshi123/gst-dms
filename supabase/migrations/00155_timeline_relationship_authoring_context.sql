-- Narrow manual-authoring projection. No direct catalogue/document grants.
BEGIN;
CREATE FUNCTION public.read_matter_relationship_authoring_context(p_matter_id uuid)
RETURNS TABLE(outcome text, documents jsonb, relationship_types jsonb, relationship_source_revision text)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_org uuid;
  v_count integer;
BEGIN
  SELECT count(*)::integer, min(m.org_id::text)::uuid INTO v_count, v_org
  FROM public.current_active_tenant_membership() m
  JOIN public.organisations o ON o.id = m.org_id
  WHERE 'relationship.manage' = ANY(public.organisation_member_capabilities(
    m.role, o.owner_membership_id = m.membership_id,
    'active'::public.organisation_membership_state));
  IF v_count <> 1 OR p_matter_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.matters m
    JOIN public.clients c ON c.id = m.client_id AND c.org_id = m.org_id
    WHERE m.id = p_matter_id AND m.org_id = v_org
      AND m.record_state = 'active' AND m.deleted_at IS NULL
      AND m.work_state <> 'closed'
      AND c.record_state = 'active' AND c.deleted_at IS NULL
  ) THEN
    RETURN QUERY SELECT 'unavailable', '[]'::jsonb, '[]'::jsonb, ''::text;
    RETURN;
  END IF;
  -- Never silently offer a partial endpoint set as the complete matter.
  SELECT count(*) INTO v_count FROM (
    SELECT 1 FROM public.documents d WHERE d.org_id = v_org AND d.matter_id = p_matter_id
      AND d.record_state = 'active' AND d.deleted_at IS NULL AND d.document_class = 'proceeding'
    LIMIT 1001
  ) bounded;
  IF v_count > 1000 THEN
    RETURN QUERY SELECT 'capacity', '[]'::jsonb, '[]'::jsonb, ''::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'ok', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', d.id,
      'title', coalesce(nullif(d.display_title, ''), nullif(d.reference_number, ''), 'Untitled proceeding'),
      'referenceNumber', nullif(btrim(d.reference_number), ''),
      'lifecycleRevision', d.lifecycle_revision) ORDER BY d.created_at, d.id)
    FROM public.documents d WHERE d.org_id = v_org AND d.matter_id = p_matter_id
      AND d.record_state = 'active' AND d.deleted_at IS NULL AND d.document_class = 'proceeding'
  ), '[]'::jsonb), coalesce((
    SELECT jsonb_agg(jsonb_build_object('relationshipType', c.relationship_type,
      'catalogueVersion', c.catalogue_version, 'canonicalPhrase', c.canonical_phrase,
      'progressionPhrase', c.progression_phrase) ORDER BY c.display_priority, c.relationship_type)
    FROM (SELECT DISTINCT ON (relationship_type) * FROM public.document_relationship_catalogue
      ORDER BY relationship_type, catalogue_version DESC) c
    WHERE c.timeline_visible AND c.acyclic
      AND c.relationship_type NOT IN ('refers_to', 'other')
      AND 'proceeding' = ANY(c.allowed_source_classes) AND 'proceeding' = ANY(c.allowed_target_classes)
  ), '[]'::jsonb), coalesce((SELECT projection.source_revision
    FROM public.read_matter_timeline_relationships(p_matter_id, NULL) projection), '');
END $$;
REVOKE ALL ON FUNCTION public.read_matter_relationship_authoring_context(uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.read_matter_relationship_authoring_context(uuid) TO authenticated;

-- The private catalogue is immutable and deployment-only. SHARE blocks version
-- INSERTs until the delegated command finishes; a row lock alone cannot prevent
-- a new latest version. Acquire the core idempotency lock first. Deployments must
-- not mix catalogue writes with runtime commands in the same transaction.
CREATE FUNCTION public.activate_matter_timeline_relationship(
  p_matter_id uuid, p_source_document_id uuid, p_target_document_id uuid,
  p_relationship_type public.document_relationship_type,
  p_expected_source_revision bigint, p_expected_target_revision bigint,
  p_expected_catalogue_version integer, p_reason text, p_idempotency_key uuid
)
RETURNS TABLE(code text, relationship_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_org uuid;
  v_count integer;
  v_catalogue public.document_relationship_catalogue%ROWTYPE;
  v_record_version integer;
BEGIN
  IF p_idempotency_key IS NULL OR p_expected_catalogue_version IS NULL OR p_expected_catalogue_version < 1 THEN
    RETURN QUERY SELECT 'invalid_request', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_idempotency_key::text, 146));
  SELECT count(*)::integer, min(m.org_id::text)::uuid INTO v_count, v_org
  FROM public.current_active_tenant_membership() m JOIN public.organisations o ON o.id=m.org_id
  WHERE 'relationship.manage'=ANY(public.organisation_member_capabilities(m.role,o.owner_membership_id=m.membership_id,'active'::public.organisation_membership_state));
  IF v_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  LOCK TABLE public.document_relationship_catalogue IN SHARE MODE;
  -- A genuine response-loss replay retains the originally confirmed immutable
  -- version even after withdrawal. Core checks actor, tenant and every other
  -- payload field; this wrapper additionally binds the catalogue version.
  SELECT r.catalogue_version INTO v_record_version
  FROM public.document_relationship_command_receipts receipt
  JOIN public.document_relationships r ON r.id=receipt.relationship_id
  WHERE receipt.idempotency_key=p_idempotency_key AND receipt.actor_user_id=auth.uid()
    AND receipt.org_id=v_org AND receipt.command='activate';
  IF FOUND AND v_record_version IS DISTINCT FROM p_expected_catalogue_version THEN
    RETURN QUERY SELECT 'idempotency_conflict', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  SELECT * INTO v_catalogue FROM public.document_relationship_catalogue c
  WHERE c.relationship_type=p_relationship_type
    AND (v_record_version IS NULL OR c.catalogue_version=v_record_version)
  ORDER BY c.catalogue_version DESC LIMIT 1;
  IF v_catalogue.relationship_type IS NULL OR NOT v_catalogue.timeline_visible OR NOT v_catalogue.acyclic
    OR v_catalogue.relationship_type IN ('refers_to','other')
    OR NOT ('proceeding'=ANY(v_catalogue.allowed_source_classes))
    OR NOT ('proceeding'=ANY(v_catalogue.allowed_target_classes)) THEN
    RETURN QUERY SELECT 'invalid_relationship_type', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_catalogue.catalogue_version <> p_expected_catalogue_version THEN
    RETURN QUERY SELECT 'catalogue_conflict', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.activate_document_relationship(p_matter_id,p_source_document_id,p_target_document_id,
    p_relationship_type,p_expected_source_revision,p_expected_target_revision,p_reason,p_idempotency_key);
END $$;
REVOKE ALL ON FUNCTION public.activate_matter_timeline_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,integer,text,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.activate_matter_timeline_relationship(uuid,uuid,uuid,public.document_relationship_type,bigint,bigint,integer,text,uuid) TO authenticated;

-- Bind the UI Matter context without changing the core command's replay semantics.
CREATE FUNCTION public.archive_matter_timeline_relationship(
  p_matter_id uuid, p_relationship_id uuid, p_expected_revision bigint,
  p_reason text, p_idempotency_key uuid
)
RETURNS TABLE(code text, relationship_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.current_active_tenant_membership() m
    JOIN public.organisations o ON o.id = m.org_id
    JOIN public.document_relationships r ON r.org_id = m.org_id
      AND r.matter_id = p_matter_id AND r.id = p_relationship_id
    JOIN public.document_relationship_catalogue c ON c.relationship_type = r.relationship_type
      AND c.catalogue_version = r.catalogue_version AND c.timeline_visible
    WHERE 'relationship.manage' = ANY(public.organisation_member_capabilities(
      m.role, o.owner_membership_id = m.membership_id, 'active'::public.organisation_membership_state))
  ) THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false;
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.archive_document_relationship(
    p_relationship_id, p_expected_revision, p_reason, p_idempotency_key);
END $$;
REVOKE ALL ON FUNCTION public.archive_matter_timeline_relationship(uuid,uuid,bigint,text,uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.archive_matter_timeline_relationship(uuid,uuid,bigint,text,uuid) TO authenticated;
COMMIT;
