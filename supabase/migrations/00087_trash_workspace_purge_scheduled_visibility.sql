-- Extend the authenticated Trash workspace projection to keep purge-scheduled
-- operations visible as read-only entries until purging actually begins.
--
-- The private Trash tables remain ungranted. This projection returns a bounded
-- root-operation list and, only for one selected root, its active inherited
-- membership tree. It deliberately exposes no retention, hold, restore, purge,
-- legal content, or raw storage locator data.
BEGIN;

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
STABLE
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
     AND root_membership.state = 'active'::public.resource_trash_membership_state
    LEFT JOIN public.clients AS root_client
      ON operation.root_resource_type = 'client'::public.trash_resource_type
     AND root_client.org_id = operation.org_id
     AND root_client.id = operation.root_resource_id
     AND root_client.record_state = 'trashed'::public.resource_record_state
     AND root_client.active_trash_membership_id = root_membership.id
    LEFT JOIN public.matters AS root_matter
      ON operation.root_resource_type = 'matter'::public.trash_resource_type
     AND root_matter.org_id = operation.org_id
     AND root_matter.id = operation.root_resource_id
     AND root_matter.record_state = 'trashed'::public.resource_record_state
     AND root_matter.active_trash_membership_id = root_membership.id
    LEFT JOIN public.clients AS root_matter_client
      ON root_matter_client.org_id = root_matter.org_id
     AND root_matter_client.id = root_matter.client_id
    LEFT JOIN public.documents AS root_document
      ON operation.root_resource_type = 'document'::public.trash_resource_type
     AND root_document.org_id = operation.org_id
     AND root_document.id = operation.root_resource_id
     AND root_document.record_state::text = 'trashed'
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
          AND document_membership.state = 'active'::public.resource_trash_membership_state
      ) AS operation_asset
      JOIN public.file_assets AS asset
        ON asset.org_id = operation.org_id
       AND asset.id = operation_asset.asset_id
    ) AS operation_assets ON true
    WHERE operation.org_id = p_org_id
      AND operation.state IN (
        'trashed'::public.trash_operation_state,
        'restore_blocked'::public.trash_operation_state,
        'purge_scheduled'::public.trash_operation_state
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
       AND document_membership.state = 'active'::public.resource_trash_membership_state
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
        AND membership.state = 'active'::public.resource_trash_membership_state
      ORDER BY membership.created_at, membership.id
    ) AS member ON true
    LEFT JOIN public.clients AS member_client
      ON member.resource_type = 'client'::public.trash_resource_type
     AND member_client.org_id = member.org_id
     AND member_client.id = member.resource_id
     AND member_client.record_state = 'trashed'::public.resource_record_state
     AND member_client.active_trash_membership_id = member.id
    LEFT JOIN public.matters AS member_matter
      ON member.resource_type = 'matter'::public.trash_resource_type
     AND member_matter.org_id = member.org_id
     AND member_matter.id = member.resource_id
     AND member_matter.record_state = 'trashed'::public.resource_record_state
     AND member_matter.active_trash_membership_id = member.id
    LEFT JOIN public.documents AS member_document
      ON member.resource_type = 'document'::public.trash_resource_type
     AND member_document.org_id = member.org_id
     AND member_document.id = member.resource_id
     AND member_document.record_state::text = 'trashed'
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

REVOKE ALL ON FUNCTION public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer)
  FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer)
  TO authenticated;

COMMENT ON FUNCTION public.get_trash_workspace(uuid,text,public.trash_resource_type,uuid,integer) IS
  'Authenticated bounded Trash workspace projection. Returns root operations plus inherited members only for one selected root; no write authority or storage locators.';

COMMIT;
