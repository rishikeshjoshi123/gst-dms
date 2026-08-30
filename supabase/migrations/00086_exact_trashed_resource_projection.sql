-- Authenticated legal-content projection for an exact canonical Trash route.
-- Ordinary collections remain active-only; this function opens only one
-- lineage-validated trashed Client, Matter, or Document and the readable
-- trashed hierarchy needed by its existing canonical page composition.
BEGIN;

CREATE OR REPLACE FUNCTION public.get_exact_trashed_resource_projection(
  p_resource_type public.trash_resource_type,
  p_resource_id uuid,
  p_expected_matter_id uuid DEFAULT NULL
)
RETURNS TABLE(
  resource_id uuid,
  resource_type public.trash_resource_type,
  membership_id uuid,
  cause public.resource_trash_cause,
  parent_membership_id uuid,
  operation_id uuid,
  root_resource_id uuid,
  root_resource_type public.trash_resource_type,
  root_resource_name text,
  operation_state public.trash_operation_state,
  trashed_at timestamptz,
  trashed_by uuid,
  trashed_by_name text,
  retention_mode public.trash_retention_mode,
  retention_days integer,
  purge_eligible_at timestamptz,
  auto_purge_enabled boolean,
  auto_purge_at timestamptz,
  purge_scheduled_at timestamptz,
  blocker_count integer,
  can_restore boolean,
  resource_record jsonb,
  related_matters jsonb,
  related_documents jsonb,
  related_links jsonb,
  related_wiki_sections jsonb,
  related_notes jsonb,
  related_inspector_metadata jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  resource_org_id uuid;
  resource_state text;
  active_membership_id uuid;
  resource_matter_id uuid;
  resource_client_id uuid;
  resource_deleted_at timestamptz;
  caller record;
  selected_membership record;
  selected_operation record;
  target_matter_id uuid;
  projected_document_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF p_resource_type IS NULL OR p_resource_id IS NULL THEN RETURN; END IF;

  IF p_resource_type = 'client'::public.trash_resource_type THEN
    IF p_expected_matter_id IS NOT NULL THEN RETURN; END IF;
    SELECT client.org_id, client.record_state::text, client.active_trash_membership_id, NULL::uuid, client.id, client.deleted_at
      INTO resource_org_id, resource_state, active_membership_id, resource_matter_id, resource_client_id, resource_deleted_at
    FROM public.clients AS client
    WHERE client.id = p_resource_id;
  ELSIF p_resource_type = 'matter'::public.trash_resource_type THEN
    IF p_expected_matter_id IS NOT NULL THEN RETURN; END IF;
    SELECT matter.org_id, matter.record_state::text, matter.active_trash_membership_id, matter.id, matter.client_id, matter.deleted_at
      INTO resource_org_id, resource_state, active_membership_id, resource_matter_id, resource_client_id, resource_deleted_at
    FROM public.matters AS matter
    WHERE matter.id = p_resource_id;
  ELSE
    SELECT document.org_id, document.record_state::text, document.active_trash_membership_id,
           document.matter_id, matter.client_id, document.deleted_at
      INTO resource_org_id, resource_state, active_membership_id, resource_matter_id, resource_client_id, resource_deleted_at
    FROM public.documents AS document
    JOIN public.matters AS matter
      ON matter.org_id = document.org_id
     AND matter.id = document.matter_id
    WHERE document.id = p_resource_id;
    IF resource_matter_id IS DISTINCT FROM p_expected_matter_id THEN RETURN; END IF;
  END IF;

  SELECT * INTO caller
  FROM public.get_my_organisation_context() AS context
  WHERE context.org_id = resource_org_id
    AND context.state = 'active'
    AND auth.uid() IS NOT NULL
  LIMIT 1;
  IF caller.org_id IS NULL OR resource_state <> 'trashed' OR active_membership_id IS NULL OR resource_deleted_at IS NULL THEN RETURN; END IF;

  SELECT membership.* INTO selected_membership
  FROM public.resource_trash_memberships AS membership
  WHERE membership.org_id = resource_org_id
    AND membership.id = active_membership_id
    AND membership.resource_type = p_resource_type
    AND membership.resource_id = p_resource_id
    AND membership.state = 'active'::public.resource_trash_membership_state;
  IF selected_membership.id IS NULL THEN RETURN; END IF;

  SELECT operation.* INTO selected_operation
  FROM public.trash_operations AS operation
  WHERE operation.org_id = resource_org_id
    AND operation.id = selected_membership.operation_id
    AND operation.state IN (
      'trashed'::public.trash_operation_state,
      'restore_blocked'::public.trash_operation_state,
      'purge_scheduled'::public.trash_operation_state
    );
  IF selected_operation.id IS NULL THEN RETURN; END IF;

  -- The selected membership must still reach the operation's one valid direct
  -- root, and that root record must itself remain in readable Trash state.
  IF NOT EXISTS (
    WITH RECURSIVE lineage AS (
      SELECT membership.id, membership.parent_membership_id
      FROM public.resource_trash_memberships AS membership
      WHERE membership.org_id = resource_org_id
        AND membership.id = selected_membership.id
        AND membership.operation_id = selected_operation.id
        AND membership.state = 'active'::public.resource_trash_membership_state
      UNION ALL
      SELECT parent.id, parent.parent_membership_id
      FROM public.resource_trash_memberships AS parent
      JOIN lineage AS child ON child.parent_membership_id = parent.id
      WHERE parent.org_id = resource_org_id
        AND parent.operation_id = selected_operation.id
        AND parent.state = 'active'::public.resource_trash_membership_state
    )
    SELECT 1
    FROM lineage
    JOIN public.resource_trash_memberships AS root_membership ON root_membership.id = lineage.id
    WHERE root_membership.org_id = resource_org_id
      AND root_membership.operation_id = selected_operation.id
      AND root_membership.resource_type = selected_operation.root_resource_type
      AND root_membership.resource_id = selected_operation.root_resource_id
      AND root_membership.cause = 'direct'::public.resource_trash_cause
      AND root_membership.parent_membership_id IS NULL
  ) THEN RETURN; END IF;

  IF NOT (
    (selected_operation.root_resource_type = 'client'::public.trash_resource_type AND EXISTS (
      SELECT 1 FROM public.clients AS root
      JOIN public.resource_trash_memberships AS root_membership ON root_membership.id = root.active_trash_membership_id
      WHERE root.org_id = resource_org_id AND root.id = selected_operation.root_resource_id
        AND root.record_state = 'trashed'::public.resource_record_state
        AND root.deleted_at IS NOT NULL
        AND root_membership.org_id = resource_org_id AND root_membership.operation_id = selected_operation.id
        AND root_membership.resource_type = 'client'::public.trash_resource_type AND root_membership.resource_id = root.id
        AND root_membership.state = 'active'::public.resource_trash_membership_state
        AND root_membership.cause = 'direct'::public.resource_trash_cause AND root_membership.parent_membership_id IS NULL
    ))
    OR (selected_operation.root_resource_type = 'matter'::public.trash_resource_type AND EXISTS (
      SELECT 1 FROM public.matters AS root
      JOIN public.resource_trash_memberships AS root_membership ON root_membership.id = root.active_trash_membership_id
      WHERE root.org_id = resource_org_id AND root.id = selected_operation.root_resource_id
        AND root.record_state = 'trashed'::public.resource_record_state
        AND root.deleted_at IS NOT NULL
        AND root_membership.org_id = resource_org_id AND root_membership.operation_id = selected_operation.id
        AND root_membership.resource_type = 'matter'::public.trash_resource_type AND root_membership.resource_id = root.id
        AND root_membership.state = 'active'::public.resource_trash_membership_state
        AND root_membership.cause = 'direct'::public.resource_trash_cause AND root_membership.parent_membership_id IS NULL
    ))
    OR (selected_operation.root_resource_type = 'document'::public.trash_resource_type AND EXISTS (
      SELECT 1 FROM public.documents AS root
      JOIN public.resource_trash_memberships AS root_membership ON root_membership.id = root.active_trash_membership_id
      WHERE root.org_id = resource_org_id AND root.id = selected_operation.root_resource_id
        AND root.record_state::text = 'trashed'
        AND root.deleted_at IS NOT NULL
        AND root_membership.org_id = resource_org_id AND root_membership.operation_id = selected_operation.id
        AND root_membership.resource_type = 'document'::public.trash_resource_type AND root_membership.resource_id = root.id
        AND root_membership.state = 'active'::public.resource_trash_membership_state
        AND root_membership.cause = 'direct'::public.resource_trash_cause AND root_membership.parent_membership_id IS NULL
    ))
  ) THEN RETURN; END IF;

  target_matter_id := CASE
    WHEN p_resource_type = 'client'::public.trash_resource_type THEN NULL
    ELSE resource_matter_id
  END;

  IF target_matter_id IS NOT NULL THEN
    SELECT coalesce(array_agg(document.id ORDER BY document.created_at DESC, document.id), ARRAY[]::uuid[])
      INTO projected_document_ids
    FROM public.documents AS document
    JOIN public.resource_trash_memberships AS membership
      ON membership.org_id = document.org_id
     AND membership.id = document.active_trash_membership_id
     AND membership.resource_type = 'document'::public.trash_resource_type
     AND membership.resource_id = document.id
     AND membership.state = 'active'::public.resource_trash_membership_state
    JOIN public.trash_operations AS operation
      ON operation.org_id = membership.org_id
     AND operation.id = membership.operation_id
     AND operation.state IN (
       'trashed'::public.trash_operation_state,
       'restore_blocked'::public.trash_operation_state,
       'purge_scheduled'::public.trash_operation_state
     )
    WHERE document.org_id = resource_org_id
      AND document.matter_id = target_matter_id
      AND document.record_state::text = 'trashed'
      AND document.deleted_at IS NOT NULL;
  END IF;

  RETURN QUERY
  SELECT
    p_resource_id,
    p_resource_type,
    selected_membership.id,
    selected_membership.cause,
    selected_membership.parent_membership_id,
    selected_operation.id,
    selected_operation.root_resource_id,
    selected_operation.root_resource_type,
    CASE selected_operation.root_resource_type
      WHEN 'client'::public.trash_resource_type THEN root_client.name
      WHEN 'matter'::public.trash_resource_type THEN root_matter.title
      ELSE coalesce(root_document.display_title, root_document.effective_filename, 'Untitled document')
    END,
    selected_operation.state,
    selected_membership.created_at,
    selected_operation.actor_user_id,
    coalesce(nullif(btrim(actor_profile.display_name), ''), 'Former team member'),
    selected_operation.retention_mode,
    selected_operation.retention_days::integer,
    selected_operation.purge_eligible_at,
    selected_operation.auto_purge_enabled_snapshot,
    selected_operation.auto_purge_at,
    selected_operation.purge_scheduled_at,
    selected_operation.blocker_count,
    (
      caller.is_owner
      OR caller.role = 'admin'::public.org_member_role
      OR (
        caller.role = 'associate'::public.org_member_role
        AND selected_membership.resource_type = 'document'::public.trash_resource_type
        AND selected_membership.cause = 'direct'::public.resource_trash_cause
        AND selected_operation.actor_user_id = auth.uid()
      )
    ),
    CASE p_resource_type
      WHEN 'client'::public.trash_resource_type THEN jsonb_build_object(
        'id', selected_client.id,
        'name', selected_client.name,
        'gstin', selected_client.gstin,
        'pan', selected_client.pan
      )
      WHEN 'matter'::public.trash_resource_type THEN jsonb_build_object(
        'id', selected_matter.id,
        'client_id', selected_matter.client_id,
        'title', selected_matter.title,
        'matter_code', selected_matter.matter_code,
        'financial_year', selected_matter.financial_year,
        'status', selected_matter.status,
        'description', selected_matter.description,
        'clients', jsonb_build_object(
          'id', selected_matter_client.id,
          'name', selected_matter_client.name,
          'gstin', selected_matter_client.gstin,
          'pan', selected_matter_client.pan
        )
      )
      ELSE jsonb_build_object(
        'id', selected_document.id,
        'matter_id', selected_document.matter_id,
        'display_title', selected_document.display_title,
        'effective_filename', selected_document.effective_filename,
        'document_class', selected_document.document_class,
        'document_category', selected_document.document_category,
        'financial_year', selected_document.financial_year,
        'reference_number', selected_document.reference_number,
        'status', selected_document.status,
        'review_reason', selected_document.review_reason,
        'summary', selected_document.summary,
        'current_version_id', selected_document.current_version_id,
        'created_at', selected_document.created_at,
        'matters', jsonb_build_object('id', selected_document_matter.id, 'title', selected_document_matter.title)
      )
    END,
    CASE WHEN p_resource_type = 'client'::public.trash_resource_type THEN coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', matter.id,
        'client_id', matter.client_id,
        'title', matter.title,
        'matter_code', matter.matter_code,
        'financial_year', matter.financial_year,
        'status', matter.status,
        'description', matter.description
      ) ORDER BY matter.created_at DESC, matter.id)
      FROM public.matters AS matter
      JOIN public.resource_trash_memberships AS membership
        ON membership.org_id = matter.org_id
       AND membership.id = matter.active_trash_membership_id
       AND membership.resource_type = 'matter'::public.trash_resource_type
       AND membership.resource_id = matter.id
       AND membership.state = 'active'::public.resource_trash_membership_state
      JOIN public.trash_operations AS operation
        ON operation.org_id = membership.org_id
       AND operation.id = membership.operation_id
       AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
      WHERE matter.org_id = resource_org_id
        AND matter.client_id = resource_client_id
        AND matter.record_state = 'trashed'::public.resource_record_state
        AND matter.deleted_at IS NOT NULL
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    CASE WHEN target_matter_id IS NOT NULL THEN coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', document.id,
        'matter_id', document.matter_id,
        'display_title', document.display_title,
        'effective_filename', document.effective_filename,
        'document_class', document.document_class,
        'document_category', document.document_category,
        'financial_year', document.financial_year,
        'reference_number', document.reference_number,
        'status', document.status,
        'review_reason', document.review_reason,
        'summary', document.summary,
        'current_version_id', document.current_version_id,
        'created_at', document.created_at
      ) ORDER BY document.created_at DESC, document.id)
      FROM public.documents AS document
      WHERE document.id = ANY(projected_document_ids)
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    CASE WHEN target_matter_id IS NOT NULL THEN coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', link.id,
        'from_doc_id', link.from_doc_id,
        'to_doc_id', link.to_doc_id,
        'link_type', link.link_type,
        'status', link.status,
        'match_method', link.match_method,
        'created_at', link.created_at
      ) ORDER BY link.created_at, link.id)
      FROM public.document_links AS link
      WHERE link.from_doc_id = ANY(projected_document_ids)
        AND link.to_doc_id = ANY(projected_document_ids)
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    CASE WHEN target_matter_id IS NOT NULL THEN coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', section.id,
        'section_key', section.section_key,
        'title', section.title,
        'content', section.content,
        'is_user_edited', section.is_user_edited,
        'updated_at', section.updated_at
      ) ORDER BY section.updated_at, section.id)
      FROM public.wiki_sections AS section
      WHERE section.matter_id = target_matter_id
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    CASE WHEN target_matter_id IS NOT NULL THEN coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', note.id,
          'matter_id', note.matter_id,
          'document_id', note.document_id,
          'content', note.content,
          'template_type', note.template_type,
          'is_action_item', note.is_action_item,
          'action_item_assignee', note.action_item_assignee,
          'action_item_due_date', note.action_item_due_date,
          'action_item_resolved', note.action_item_resolved,
          'parent_note_id', note.parent_note_id,
          'quote', note.quote,
          'page_number', note.page_number,
          'is_pinned', note.is_pinned,
          'created_at', note.created_at,
          'author', jsonb_build_object(
            'id', note.author_id,
            'email', coalesce(nullif(btrim(note_author.display_name), ''), concat('User (', left(note.author_id::text, 8), ')'))
          ),
          'documents', CASE WHEN note_document.id IS NULL THEN NULL ELSE jsonb_build_object(
            'id', note_document.id,
            'reference_number', note_document.reference_number,
            'display_title', note_document.display_title,
            'effective_filename', note_document.effective_filename
          ) END
        ) ORDER BY note.is_pinned DESC, note.created_at DESC, note.id
      )
      FROM public.case_notes AS note
      LEFT JOIN public.user_profiles AS note_author ON note_author.user_id = note.author_id
      LEFT JOIN public.documents AS note_document
        ON note_document.org_id = note.org_id
       AND note_document.id = note.document_id
       AND note_document.id = ANY(projected_document_ids)
      WHERE note.org_id = resource_org_id
        AND note.matter_id = target_matter_id
        AND note.deleted_at IS NULL
        AND (
          (p_resource_type = 'document'::public.trash_resource_type AND note.document_id = p_resource_id)
          OR (
            p_resource_type = 'matter'::public.trash_resource_type
            AND (note.document_id IS NULL OR note.document_id = ANY(projected_document_ids))
          )
        )
    ), '[]'::jsonb) ELSE '[]'::jsonb END,
    CASE WHEN target_matter_id IS NOT NULL THEN coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'document_id', effective.document_id,
        'document_version_id', effective.document_version_id,
        'document_field_candidate_id', effective.winning_document_field_candidate_id,
        'semantic_candidate_key', effective.semantic_candidate_key,
        'field_path', effective.field_path,
        'value_type', effective.value_type,
        'normalized_value', effective.normalized_value,
        'resolution', effective.resolution,
        'computed_at', effective.computed_at
      ) ORDER BY effective.document_id, effective.field_path, effective.semantic_candidate_key)
      FROM public.document_effective_metadata AS effective
      JOIN public.documents AS document
        ON document.org_id = effective.org_id
       AND document.id = effective.document_id
       AND document.current_version_id = effective.document_version_id
      JOIN public.document_versions AS version
        ON version.org_id = effective.org_id
       AND version.id = effective.document_version_id
       AND version.document_id = effective.document_id
       AND version.state = 'current'::public.document_version_state
       AND version.validation_state = 'valid'::public.document_version_validation_state
      WHERE effective.org_id = resource_org_id
        AND effective.document_id = ANY(projected_document_ids)
    ), '[]'::jsonb) ELSE '[]'::jsonb END
  FROM (SELECT 1) AS singleton
  LEFT JOIN public.user_profiles AS actor_profile ON actor_profile.user_id = selected_operation.actor_user_id
  LEFT JOIN public.clients AS root_client
    ON selected_operation.root_resource_type = 'client'::public.trash_resource_type
   AND root_client.org_id = resource_org_id AND root_client.id = selected_operation.root_resource_id
  LEFT JOIN public.matters AS root_matter
    ON selected_operation.root_resource_type = 'matter'::public.trash_resource_type
   AND root_matter.org_id = resource_org_id AND root_matter.id = selected_operation.root_resource_id
  LEFT JOIN public.documents AS root_document
    ON selected_operation.root_resource_type = 'document'::public.trash_resource_type
   AND root_document.org_id = resource_org_id AND root_document.id = selected_operation.root_resource_id
  LEFT JOIN public.clients AS selected_client
    ON p_resource_type = 'client'::public.trash_resource_type
   AND selected_client.org_id = resource_org_id AND selected_client.id = p_resource_id
  LEFT JOIN public.matters AS selected_matter
    ON p_resource_type = 'matter'::public.trash_resource_type
   AND selected_matter.org_id = resource_org_id AND selected_matter.id = p_resource_id
  LEFT JOIN public.clients AS selected_matter_client
    ON selected_matter_client.org_id = selected_matter.org_id AND selected_matter_client.id = selected_matter.client_id
  LEFT JOIN public.documents AS selected_document
    ON p_resource_type = 'document'::public.trash_resource_type
   AND selected_document.org_id = resource_org_id AND selected_document.id = p_resource_id
  LEFT JOIN public.matters AS selected_document_matter
    ON selected_document_matter.org_id = selected_document.org_id AND selected_document_matter.id = selected_document.matter_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_trashed_document_version_read_grant(
  p_document_id uuid,
  p_expected_matter_id uuid,
  p_document_version_id uuid
)
RETURNS TABLE(code text, bucket_id text, object_key text)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  SELECT 'ok'::text, asset.bucket_id, asset.object_key
  FROM public.get_my_organisation_context() AS actor
  JOIN public.documents AS document
    ON document.org_id = actor.org_id
   AND document.id = p_document_id
   AND document.matter_id = p_expected_matter_id
   AND document.record_state::text = 'trashed'
   AND document.deleted_at IS NOT NULL
  JOIN public.resource_trash_memberships AS membership
    ON membership.org_id = document.org_id
   AND membership.id = document.active_trash_membership_id
   AND membership.resource_type = 'document'::public.trash_resource_type
   AND membership.resource_id = document.id
   AND membership.state = 'active'::public.resource_trash_membership_state
  JOIN public.trash_operations AS operation
    ON operation.org_id = membership.org_id
   AND operation.id = membership.operation_id
   AND operation.state IN ('trashed','restore_blocked','purge_scheduled')
  JOIN public.document_versions AS version
    ON version.org_id = document.org_id
   AND version.document_id = document.id
   AND version.id = p_document_version_id
   AND version.validation_state = 'valid'
   AND version.state IN ('current','superseded')
  JOIN public.file_assets AS asset
    ON asset.org_id = version.org_id
   AND asset.id = version.asset_id
   AND asset.availability = 'available'
   AND asset.storage_deleted_at IS NULL
  WHERE actor.state = 'active'
    AND auth.uid() IS NOT NULL
    AND 'document.view' = ANY(actor.capabilities)
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid),
  public.get_trashed_document_version_read_grant(uuid,uuid,uuid)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid),
  public.get_trashed_document_version_read_grant(uuid,uuid,uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid) IS
  'Exact, authenticated, lineage-bound Trash legal-content projection for the canonical read-only Client, Matter, and Document routes.';
COMMENT ON FUNCTION public.get_trashed_document_version_read_grant(uuid,uuid,uuid) IS
  'Exact, authenticated Trash document-version grant; returns a storage locator only after organisation, route lineage, membership, operation, and document-view checks.';

COMMIT;
