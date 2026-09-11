-- Activate exact logical Trash expiry and authenticated shared-Intake reads.
-- Physical deletion remains an independently retried cleanup concern.
BEGIN;

ALTER FUNCTION public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer)
  RENAME TO get_trash_workspace_before_logical_expiry;
REVOKE ALL ON FUNCTION public.get_trash_workspace_before_logical_expiry(uuid,text,public.trash_resource_type,uuid,integer)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_trash_workspace(
  p_org_id uuid,
  p_query text DEFAULT NULL,
  p_resource_type public.trash_resource_type DEFAULT NULL,
  p_selected_operation_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  row_kind text,
  total_storage_bytes bigint,
  operation_id uuid,
  root_resource_type public.trash_resource_type,
  root_resource_id uuid,
  root_membership_id uuid,
  root_name text,
  root_parent_context text,
  root_client_id uuid,
  root_matter_id uuid,
  root_document_id uuid,
  deleted_at timestamptz,
  deleted_by_name text,
  reason text,
  included_client_count integer,
  included_matter_count integer,
  included_document_count integer,
  operation_storage_bytes bigint,
  member_membership_id uuid,
  member_parent_membership_id uuid,
  member_resource_type public.trash_resource_type,
  member_resource_id uuid,
  member_name text,
  member_client_id uuid,
  member_matter_id uuid,
  member_document_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
VOLATILE
SET search_path = pg_catalog, public
AS $$
DECLARE
  caller record;
  bounded_limit integer;
  normalized_query text;
BEGIN
  IF p_org_id IS NULL OR auth.uid() IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO caller
  FROM public.get_my_organisation_context() AS context
  WHERE context.org_id = p_org_id
    AND context.state = 'active'
  LIMIT 1;
  IF caller.org_id IS NULL THEN
    RETURN;
  END IF;

  normalized_query := NULLIF(btrim(p_query), '');
  IF normalized_query IS NOT NULL AND char_length(normalized_query) > 120 THEN
    RETURN;
  END IF;
  bounded_limit := greatest(1, least(coalesce(p_limit, 50), 100));

  RETURN QUERY
  WITH eligible_operations AS MATERIALIZED (
    SELECT
      operation.id,
      operation.root_resource_type,
      operation.root_resource_id,
      operation.root_client_id,
      operation.root_matter_id,
      operation.root_document_id,
      operation.actor_user_id,
      operation.reason,
      operation.created_at,
      operation.included_client_count,
      operation.included_matter_count,
      operation.included_document_count,
      root_membership.id AS root_membership_id,
      CASE operation.root_resource_type
        WHEN 'client'::public.trash_resource_type THEN root_client.name
        WHEN 'matter'::public.trash_resource_type THEN root_matter.title
        ELSE coalesce(root_document.display_title, root_document.effective_filename, 'Untitled document')
      END AS display_name,
      CASE operation.root_resource_type
        WHEN 'client'::public.trash_resource_type THEN 'Organisation client register'::text
        WHEN 'matter'::public.trash_resource_type THEN root_matter_client.name
        ELSE concat_ws(' · ', root_document_client.name, root_document_matter.title)
      END AS parent_context,
      coalesce(nullif(btrim(actor_profile.display_name), ''), 'Former team member') AS actor_name,
      greatest(operation.unique_storage_bytes, coalesce(operation_assets.storage_bytes, 0::bigint)) AS storage_bytes
    FROM public.trash_operations AS operation
    JOIN public.resource_trash_memberships AS root_membership
      ON root_membership.org_id = operation.org_id
     AND root_membership.operation_id = operation.id
     AND root_membership.resource_type = operation.root_resource_type
     AND root_membership.resource_id = operation.root_resource_id
     AND root_membership.cause = 'direct'::public.resource_trash_cause
     AND root_membership.parent_membership_id IS NULL
     AND root_membership.state IN ('active'::public.resource_trash_membership_state, 'purging'::public.resource_trash_membership_state)
    LEFT JOIN public.clients AS root_client
      ON operation.root_resource_type = 'client'::public.trash_resource_type
     AND root_client.org_id = operation.org_id
     AND root_client.id = operation.root_resource_id
     AND root_client.record_state IN ('trashed'::public.resource_record_state, 'purging'::public.resource_record_state)
     AND root_client.active_trash_membership_id = root_membership.id
    LEFT JOIN public.matters AS root_matter
      ON operation.root_resource_type = 'matter'::public.trash_resource_type
     AND root_matter.org_id = operation.org_id
     AND root_matter.id = operation.root_resource_id
     AND root_matter.record_state IN ('trashed'::public.resource_record_state, 'purging'::public.resource_record_state)
     AND root_matter.active_trash_membership_id = root_membership.id
    LEFT JOIN public.clients AS root_matter_client
      ON root_matter_client.org_id = root_matter.org_id
     AND root_matter_client.id = root_matter.client_id
    LEFT JOIN public.documents AS root_document
      ON operation.root_resource_type = 'document'::public.trash_resource_type
     AND root_document.org_id = operation.org_id
     AND root_document.id = operation.root_resource_id
     AND root_document.record_state::text IN ('trashed', 'purging')
     AND root_document.active_trash_membership_id = root_membership.id
    LEFT JOIN public.matters AS root_document_matter
      ON root_document_matter.org_id = root_document.org_id
     AND root_document_matter.id = root_document.matter_id
    LEFT JOIN public.clients AS root_document_client
      ON root_document_client.org_id = root_document_matter.org_id
     AND root_document_client.id = root_document_matter.client_id
    LEFT JOIN public.user_profiles AS actor_profile
      ON actor_profile.user_id = operation.actor_user_id
    LEFT JOIN LATERAL (
      SELECT coalesce(sum(asset.byte_size), 0)::bigint AS storage_bytes
      FROM (
        SELECT DISTINCT version.asset_id
        FROM public.resource_trash_memberships AS document_membership
        JOIN public.document_versions AS version
          ON version.org_id = document_membership.org_id
         AND version.document_id = document_membership.resource_id
        WHERE document_membership.org_id = operation.org_id
          AND document_membership.operation_id = operation.id
          AND document_membership.resource_type = 'document'::public.trash_resource_type
          AND document_membership.state IN ('active'::public.resource_trash_membership_state, 'purging'::public.resource_trash_membership_state)
      ) AS operation_asset
      JOIN public.file_assets AS asset
        ON asset.org_id = operation.org_id
       AND asset.id = operation_asset.asset_id
    ) AS operation_assets ON true
    WHERE operation.org_id = p_org_id
      AND (
        operation.auto_purge_at IS NULL
        OR clock_timestamp() < operation.auto_purge_at
        OR ((caller.is_owner OR caller.role = 'admin') AND EXISTS (
          SELECT 1
          FROM public.trash_purge_active_blockers(operation.org_id, operation.id)
        ))
      )
      AND operation.state IN (
        'trashed'::public.trash_operation_state,
        'restore_blocked'::public.trash_operation_state,
        'purge_scheduled'::public.trash_operation_state,
        'purging'::public.trash_operation_state,
        'purge_failed'::public.trash_operation_state
      )
      AND (
        (operation.root_resource_type = 'client'::public.trash_resource_type AND root_client.id IS NOT NULL)
        OR (operation.root_resource_type = 'matter'::public.trash_resource_type AND root_matter.id IS NOT NULL AND root_matter_client.id IS NOT NULL)
        OR (operation.root_resource_type = 'document'::public.trash_resource_type AND root_document.id IS NOT NULL AND root_document_matter.id IS NOT NULL AND root_document_client.id IS NOT NULL)
      )
  ), total_storage AS (
    SELECT coalesce(sum(asset.byte_size), 0)::bigint AS storage_bytes
    FROM (
      SELECT DISTINCT version.asset_id
      FROM eligible_operations AS operation
      JOIN public.resource_trash_memberships AS document_membership
        ON document_membership.operation_id = operation.id
       AND document_membership.org_id = p_org_id
       AND document_membership.resource_type = 'document'::public.trash_resource_type
       AND document_membership.state IN ('active'::public.resource_trash_membership_state, 'purging'::public.resource_trash_membership_state)
      JOIN public.document_versions AS version
        ON version.org_id = document_membership.org_id
       AND version.document_id = document_membership.resource_id
    ) AS trash_asset
    JOIN public.file_assets AS asset
      ON asset.org_id = p_org_id
     AND asset.id = trash_asset.asset_id
  ), filtered_operations AS MATERIALIZED (
    SELECT operation.*
    FROM eligible_operations AS operation
    WHERE (p_resource_type IS NULL OR operation.root_resource_type = p_resource_type)
      AND (
        normalized_query IS NULL
        OR position(lower(normalized_query) IN lower(concat_ws(' ', operation.display_name, operation.parent_context, operation.actor_name, operation.reason))) > 0
      )
    ORDER BY operation.created_at DESC, operation.id DESC
    LIMIT bounded_limit
  ), rows AS (
    SELECT
      0 AS sort_group,
      NULL::timestamptz AS sort_created_at,
      NULL::uuid AS sort_operation_id,
      NULL::uuid AS sort_member_id,
      'summary'::text AS row_kind,
      total_storage.storage_bytes AS total_storage_bytes,
      NULL::uuid AS operation_id,
      NULL::public.trash_resource_type AS root_resource_type,
      NULL::uuid AS root_resource_id,
      NULL::uuid AS root_membership_id,
      NULL::text AS root_name,
      NULL::text AS root_parent_context,
      NULL::uuid AS root_client_id,
      NULL::uuid AS root_matter_id,
      NULL::uuid AS root_document_id,
      NULL::timestamptz AS deleted_at,
      NULL::text AS deleted_by_name,
      NULL::text AS reason,
      NULL::integer AS included_client_count,
      NULL::integer AS included_matter_count,
      NULL::integer AS included_document_count,
      NULL::bigint AS operation_storage_bytes,
      NULL::uuid AS member_membership_id,
      NULL::uuid AS member_parent_membership_id,
      NULL::public.trash_resource_type AS member_resource_type,
      NULL::uuid AS member_resource_id,
      NULL::text AS member_name,
      NULL::uuid AS member_client_id,
      NULL::uuid AS member_matter_id,
      NULL::uuid AS member_document_id
    FROM total_storage

    UNION ALL

    SELECT
      1,
      operation.created_at,
      operation.id,
      member.id,
      'operation'::text,
      total_storage.storage_bytes,
      operation.id,
      operation.root_resource_type,
      operation.root_resource_id,
      operation.root_membership_id,
      operation.display_name,
      operation.parent_context,
      operation.root_client_id,
      CASE
        WHEN operation.root_resource_type = 'matter'::public.trash_resource_type THEN operation.root_matter_id
        WHEN operation.root_resource_type = 'document'::public.trash_resource_type THEN root_document.matter_id
      END,
      operation.root_document_id,
      operation.created_at,
      operation.actor_name,
      operation.reason,
      operation.included_client_count,
      operation.included_matter_count,
      operation.included_document_count,
      operation.storage_bytes,
      member.id,
      member.parent_membership_id,
      member.resource_type,
      member.resource_id,
      CASE member.resource_type
        WHEN 'matter'::public.trash_resource_type THEN member_matter.title
        WHEN 'document'::public.trash_resource_type THEN coalesce(member_document.display_title, member_document.effective_filename, 'Untitled document')
        ELSE member_client.name
      END,
      member_client.id,
      CASE
        WHEN member.resource_type = 'matter'::public.trash_resource_type THEN member_matter.id
        WHEN member.resource_type = 'document'::public.trash_resource_type THEN member_document.matter_id
      END,
      member_document.id
    FROM filtered_operations AS operation
    CROSS JOIN total_storage
    LEFT JOIN public.documents AS root_document
      ON operation.root_resource_type = 'document'::public.trash_resource_type
     AND root_document.org_id = p_org_id
     AND root_document.id = operation.root_resource_id
    LEFT JOIN LATERAL (
      SELECT membership.*
      FROM public.resource_trash_memberships AS membership
      WHERE operation.id = p_selected_operation_id
        AND membership.org_id = p_org_id
        AND membership.operation_id = operation.id
        AND membership.cause = 'inherited'::public.resource_trash_cause
        AND membership.state IN ('active'::public.resource_trash_membership_state, 'purging'::public.resource_trash_membership_state)
      ORDER BY membership.created_at, membership.id
    ) AS member ON true
    LEFT JOIN public.clients AS member_client
      ON member.resource_type = 'client'::public.trash_resource_type
     AND member_client.org_id = member.org_id
     AND member_client.id = member.resource_id
     AND member_client.record_state IN ('trashed'::public.resource_record_state, 'purging'::public.resource_record_state)
     AND member_client.active_trash_membership_id = member.id
    LEFT JOIN public.matters AS member_matter
      ON member.resource_type = 'matter'::public.trash_resource_type
     AND member_matter.org_id = member.org_id
     AND member_matter.id = member.resource_id
     AND member_matter.record_state IN ('trashed'::public.resource_record_state, 'purging'::public.resource_record_state)
     AND member_matter.active_trash_membership_id = member.id
    LEFT JOIN public.documents AS member_document
      ON member.resource_type = 'document'::public.trash_resource_type
     AND member_document.org_id = member.org_id
     AND member_document.id = member.resource_id
     AND member_document.record_state::text IN ('trashed', 'purging')
     AND member_document.active_trash_membership_id = member.id
    WHERE member.id IS NULL
       OR member_client.id IS NOT NULL
       OR member_matter.id IS NOT NULL
       OR member_document.id IS NOT NULL
  )
  SELECT
    rows.row_kind,
    rows.total_storage_bytes,
    rows.operation_id,
    rows.root_resource_type,
    rows.root_resource_id,
    rows.root_membership_id,
    rows.root_name,
    rows.root_parent_context,
    rows.root_client_id,
    rows.root_matter_id,
    rows.root_document_id,
    rows.deleted_at,
    rows.deleted_by_name,
    rows.reason,
    rows.included_client_count,
    rows.included_matter_count,
    rows.included_document_count,
    rows.operation_storage_bytes,
    rows.member_membership_id,
    rows.member_parent_membership_id,
    rows.member_resource_type,
    rows.member_resource_id,
    rows.member_name,
    rows.member_client_id,
    rows.member_matter_id,
    rows.member_document_id
  FROM rows
  ORDER BY rows.sort_group, rows.sort_created_at DESC NULLS LAST, rows.sort_operation_id DESC, rows.sort_member_id NULLS FIRST;
END;
$$;

CREATE FUNCTION public.get_trash_workspace_retention(
  p_org_id uuid, p_operation_ids uuid[]
)
RETURNS TABLE(
  operation_id uuid, auto_purge_at timestamptz, remaining_seconds bigint,
  blocker_count integer, retention_status text
)
LANGUAGE plpgsql SECURITY DEFINER VOLATILE SET search_path=pg_catalog,public AS $$
DECLARE caller record;
BEGIN
  IF p_org_id IS NULL OR auth.uid() IS NULL OR coalesce(cardinality(p_operation_ids),0)>100 THEN RETURN; END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=p_org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT operation.id,operation.auto_purge_at,
    CASE WHEN operation.auto_purge_at IS NULL THEN NULL::bigint
      ELSE greatest(0,floor(extract(epoch FROM operation.auto_purge_at-clock_timestamp())))::bigint END,
    blocker.total,
    CASE
      WHEN blocker.total>0 THEN 'blocked'
      WHEN operation.auto_purge_at IS NOT NULL AND operation.auto_purge_at-clock_timestamp()<=interval '7 days' THEN 'final_window'
      ELSE 'retained'
    END
  FROM public.trash_operations operation
  CROSS JOIN LATERAL (
    SELECT count(*)::integer AS total
    FROM public.trash_purge_active_blockers(operation.org_id,operation.id)
  ) blocker
  WHERE operation.org_id=p_org_id AND operation.id=ANY(coalesce(p_operation_ids,ARRAY[]::uuid[]))
    AND (operation.auto_purge_at IS NULL OR clock_timestamp()<operation.auto_purge_at
      OR ((caller.is_owner OR caller.role='admin') AND blocker.total>0));
END $$;

ALTER FUNCTION public.get_exact_resource_trash_context(public.trash_resource_type,uuid,uuid)
  RENAME TO get_exact_resource_trash_context_before_logical_expiry;
REVOKE ALL ON FUNCTION public.get_exact_resource_trash_context_before_logical_expiry(public.trash_resource_type,uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_exact_resource_trash_context(
  p_resource_type public.trash_resource_type, p_resource_id uuid,
  p_expected_matter_id uuid DEFAULT NULL
)
RETURNS TABLE(
  resource_id uuid, resource_type public.trash_resource_type, membership_id uuid,
  cause public.resource_trash_cause, parent_membership_id uuid, operation_id uuid,
  root_resource_id uuid, root_resource_type public.trash_resource_type,
  operation_state public.trash_operation_state, trashed_at timestamptz, trashed_by uuid,
  retention_mode public.trash_retention_mode, retention_days integer,
  purge_eligible_at timestamptz, auto_purge_enabled boolean, auto_purge_at timestamptz,
  purge_scheduled_at timestamptz, blocker_count integer, can_restore boolean
)
LANGUAGE sql SECURITY DEFINER VOLATILE SET search_path=pg_catalog,public AS $$
  SELECT source.*
  FROM public.get_exact_resource_trash_context_before_logical_expiry(
    p_resource_type,p_resource_id,p_expected_matter_id
  ) source
  WHERE source.auto_purge_at IS NULL OR clock_timestamp()<source.auto_purge_at
$$;

ALTER FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid)
  RENAME TO get_exact_trashed_resource_projection_before_logical_expiry;
REVOKE ALL ON FUNCTION public.get_exact_trashed_resource_projection_before_logical_expiry(public.trash_resource_type,uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_exact_trashed_resource_projection(
  p_resource_type public.trash_resource_type, p_resource_id uuid,
  p_expected_matter_id uuid DEFAULT NULL
)
RETURNS TABLE(
  resource_id uuid, resource_type public.trash_resource_type, membership_id uuid,
  cause public.resource_trash_cause, parent_membership_id uuid, operation_id uuid,
  root_resource_id uuid, root_resource_type public.trash_resource_type, root_resource_name text,
  operation_state public.trash_operation_state, trashed_at timestamptz, trashed_by uuid,
  trashed_by_name text, retention_mode public.trash_retention_mode, retention_days integer,
  purge_eligible_at timestamptz, auto_purge_enabled boolean, auto_purge_at timestamptz,
  purge_scheduled_at timestamptz, blocker_count integer, can_restore boolean,
  resource_record jsonb, related_matters jsonb, related_documents jsonb,
  related_links jsonb, related_wiki_sections jsonb, related_notes jsonb,
  related_inspector_metadata jsonb
)
LANGUAGE sql SECURITY DEFINER VOLATILE SET search_path=pg_catalog,public AS $$
  SELECT source.*
  FROM public.get_exact_trashed_resource_projection_before_logical_expiry(
    p_resource_type,p_resource_id,p_expected_matter_id
  ) source
  WHERE source.auto_purge_at IS NULL OR clock_timestamp()<source.auto_purge_at
$$;

ALTER FUNCTION public.get_trashed_document_version_read_grant(uuid,uuid,uuid)
  RENAME TO get_trashed_document_version_read_grant_before_logical_expiry;
REVOKE ALL ON FUNCTION public.get_trashed_document_version_read_grant_before_logical_expiry(uuid,uuid,uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_trashed_document_version_read_grant(
  p_document_id uuid,p_expected_matter_id uuid,p_document_version_id uuid
)
RETURNS TABLE(code text,bucket_id text,object_key text)
LANGUAGE sql SECURITY DEFINER VOLATILE SET search_path=pg_catalog,public AS $$
  SELECT grant_row.*
  FROM public.get_exact_trashed_resource_projection('document',p_document_id,p_expected_matter_id) exact
  CROSS JOIN LATERAL public.get_trashed_document_version_read_grant_before_logical_expiry(
    p_document_id,p_expected_matter_id,p_document_version_id
  ) grant_row
  LIMIT 1
$$;

-- Enforce the retention deadline at the state-changing boundary as well as
-- in the public command. This closes a restore race when wall-clock time
-- advances beyond the deadline after the initial command check.
CREATE OR REPLACE FUNCTION public.resource_trash_operation_transition_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  IF TG_OP='INSERT' THEN
    IF NEW.state<>'trashed' THEN RAISE EXCEPTION 'trash operation must begin in trashed state'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.state=OLD.state THEN RETURN NEW; END IF;
  IF NEW.state IN ('restoring','restored')
     AND NEW.auto_purge_at IS NOT NULL
     AND clock_timestamp()>=NEW.auto_purge_at THEN
    RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='trash_restore_deadline_expired';
  END IF;
  IF OLD.state IN ('restored','purged')
     OR (OLD.state='trashed' AND NEW.state NOT IN ('restore_blocked','restoring','purge_scheduled','purging'))
     OR (OLD.state='restore_blocked' AND NEW.state NOT IN ('trashed','restoring','purge_scheduled','purging'))
     OR (OLD.state='restoring' AND NEW.state NOT IN ('restore_blocked','restored'))
     OR (OLD.state='purge_scheduled' AND NEW.state NOT IN ('trashed','purging'))
     OR (OLD.state='purging' AND NEW.state NOT IN ('purge_failed','purged'))
     OR (OLD.state='purge_failed' AND NEW.state<>'purging') THEN
    RAISE EXCEPTION 'invalid or terminal trash operation transition';
  END IF;
  RETURN NEW;
END $$;

ALTER FUNCTION public.get_trash_restore_preflight(uuid)
  RENAME TO get_trash_restore_preflight_before_logical_expiry;
REVOKE ALL ON FUNCTION public.get_trash_restore_preflight_before_logical_expiry(uuid)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_trash_restore_preflight(p_operation_id uuid)
RETURNS TABLE(code text,can_restore boolean,blocker_code text,blocking_operation_id uuid)
LANGUAGE plpgsql SECURITY DEFINER VOLATILE SET search_path=pg_catalog,public AS $$
DECLARE operation public.trash_operations%ROWTYPE; caller record;
BEGIN
  IF p_operation_id IS NULL OR auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id;
  IF operation.id IS NULL THEN RETURN; END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL THEN RETURN; END IF;
  IF operation.auto_purge_at IS NOT NULL AND clock_timestamp()>=operation.auto_purge_at THEN
    RETURN QUERY SELECT 'not_available'::text,false,NULL::text,NULL::uuid; RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.get_trash_restore_preflight_before_logical_expiry(p_operation_id);
END $$;

ALTER FUNCTION public.restore_trash_operation(uuid,text)
  RENAME TO restore_trash_operation_before_logical_expiry;
REVOKE ALL ON FUNCTION public.restore_trash_operation_before_logical_expiry(uuid,text)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.restore_trash_operation(p_operation_id uuid,p_idempotency_key text)
RETURNS TABLE(
  code text,operation_id uuid,blocker_code text,blocking_operation_id uuid,
  root_resource_type public.trash_resource_type,root_resource_id uuid,
  root_client_id uuid,root_matter_id uuid,root_document_id uuid
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE operation public.trash_operations%ROWTYPE; caller record;
BEGIN
  IF p_operation_id IS NULL OR auth.uid() IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO operation FROM public.trash_operations WHERE id=p_operation_id FOR UPDATE;
  IF operation.id IS NULL THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  SELECT * INTO caller FROM public.get_my_organisation_context() context
    WHERE context.org_id=operation.org_id AND context.state='active' LIMIT 1;
  IF caller.org_id IS NULL THEN
    RETURN QUERY SELECT 'not_allowed'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  IF operation.auto_purge_at IS NOT NULL AND clock_timestamp()>=operation.auto_purge_at THEN
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid; RETURN;
  END IF;
  BEGIN
    RETURN QUERY SELECT * FROM public.restore_trash_operation_before_logical_expiry(p_operation_id,p_idempotency_key);
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM<>'trash_restore_deadline_expired' THEN RAISE; END IF;
    RETURN QUERY SELECT 'not_available'::text,NULL::uuid,NULL::text,NULL::uuid,
      NULL::public.trash_resource_type,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
  END;
END $$;

-- Browser-facing Intake rows are capability-scoped and carry no storage locator.
CREATE FUNCTION public.get_document_hub_intake(
  p_scope text DEFAULT 'mine',p_offset integer DEFAULT 0,p_limit integer DEFAULT 50,
  p_include_id uuid DEFAULT NULL
)
RETURNS TABLE(
  id uuid,state public.intake_item_state,failure_code text,created_at timestamptz,
  intended_matter_id uuid,declared_filename text,is_mine boolean,total_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
DECLARE actor record; bounded_offset integer; bounded_limit integer;
BEGIN
  IF p_scope NOT IN ('mine','all') OR auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO actor FROM public.get_my_organisation_context() context
    WHERE context.state='active' AND 'document.intake.assign'=ANY(context.capabilities) LIMIT 1;
  IF actor.org_id IS NULL THEN RETURN; END IF;
  bounded_offset:=greatest(0,coalesce(p_offset,0));
  bounded_limit:=greatest(1,least(coalesce(p_limit,50),100));
  RETURN QUERY
  WITH eligible AS MATERIALIZED (
    SELECT intake.id,intake.state,intake.failure_code,intake.created_at,
      intake.intended_matter_id,session.declared_filename,
      intake.uploaded_by=auth.uid() AS is_mine
    FROM public.intake_items intake
    JOIN public.upload_sessions session ON session.org_id=intake.org_id AND session.id=intake.upload_session_id
    WHERE intake.org_id=actor.org_id
      AND intake.state IN ('awaiting_upload','uploaded','validating','processing','ready','duplicate','failed')
      AND (p_scope='all' OR intake.uploaded_by=auth.uid())
  ), page AS (
    SELECT eligible.* FROM eligible
    ORDER BY eligible.created_at,eligible.id OFFSET bounded_offset LIMIT bounded_limit
  ), selected AS (
    SELECT eligible.* FROM eligible WHERE eligible.id=p_include_id
      AND NOT EXISTS (SELECT 1 FROM page WHERE page.id=eligible.id)
  )
  SELECT result.*, (SELECT count(*) FROM eligible)
  FROM (SELECT * FROM page UNION ALL SELECT * FROM selected) result
  ORDER BY result.created_at,result.id;
END $$;

CREATE FUNCTION public.get_intake_item_triage_context(p_intake_id uuid)
RETURNS TABLE(code text,uploaded_by uuid,declared_filename text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  SELECT 'ok'::text,intake.uploaded_by,session.declared_filename
  FROM public.get_my_organisation_context() actor
  JOIN public.intake_items intake ON intake.org_id=actor.org_id AND intake.id=p_intake_id
  JOIN public.upload_sessions session ON session.org_id=intake.org_id AND session.id=intake.upload_session_id
  WHERE actor.state='active' AND 'document.intake.assign'=ANY(actor.capabilities)
    AND auth.uid() IS NOT NULL AND intake.state='ready'
  LIMIT 1
$$;

-- Preview authority follows shared Intake triage; Viewers receive no row or locator.
CREATE OR REPLACE FUNCTION public.get_intake_item_read_grant(p_intake_id uuid)
RETURNS TABLE(code text,bucket_id text,object_key text)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path=pg_catalog,public AS $$
  SELECT 'ok'::text,asset.bucket_id,asset.object_key
  FROM public.get_my_organisation_context() actor
  JOIN public.intake_items intake ON intake.org_id=actor.org_id AND intake.id=p_intake_id
  JOIN public.file_assets asset ON asset.org_id=intake.org_id AND asset.id=intake.asset_id
  WHERE actor.state='active' AND 'document.intake.assign'=ANY(actor.capabilities)
    AND auth.uid() IS NOT NULL AND intake.state='ready'
    AND asset.availability='available' AND asset.detected_mime_type='application/pdf'
    AND asset.storage_deleted_at IS NULL
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION
  public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer),
  public.get_trash_workspace_retention(uuid,uuid[]),
  public.get_exact_resource_trash_context(public.trash_resource_type,uuid,uuid),
  public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid),
  public.get_trashed_document_version_read_grant(uuid,uuid,uuid),
  public.get_trash_restore_preflight(uuid),public.restore_trash_operation(uuid,text),
  public.get_document_hub_intake(text,integer,integer,uuid),
  public.get_intake_item_triage_context(uuid),public.get_intake_item_read_grant(uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION
  public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer),
  public.get_trash_workspace_retention(uuid,uuid[]),
  public.get_exact_resource_trash_context(public.trash_resource_type,uuid,uuid),
  public.get_exact_trashed_resource_projection(public.trash_resource_type,uuid,uuid),
  public.get_trashed_document_version_read_grant(uuid,uuid,uuid),
  public.get_trash_restore_preflight(uuid),public.restore_trash_operation(uuid,text),
  public.get_document_hub_intake(text,integer,integer,uuid),
  public.get_intake_item_triage_context(uuid),public.get_intake_item_read_grant(uuid)
  TO authenticated;

COMMIT;
