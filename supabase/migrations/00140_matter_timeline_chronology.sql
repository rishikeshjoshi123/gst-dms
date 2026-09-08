-- Bounded, authenticated Matter Timeline chronology projection.
BEGIN;

-- Preserve the proven 00086 tenant/root/retention implementation behind a
-- non-callable base function, then extend only its already-authorised JSON
-- document projection with chronology-safe lifecycle facts.
ALTER FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type, uuid, uuid)
  RENAME TO get_exact_trashed_resource_projection_v00086;

REVOKE ALL ON FUNCTION public.get_exact_trashed_resource_projection_v00086(public.trash_resource_type, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

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
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
  WITH authorised AS (
    SELECT base.*
    FROM public.get_exact_trashed_resource_projection_v00086(
      p_resource_type,
      p_resource_id,
      p_expected_matter_id
    ) AS base
  ), enriched AS (
    SELECT
      authorised.*,
      CASE
        WHEN authorised.resource_type = 'document'::public.trash_resource_type
          AND selected_document.id IS NOT NULL
        THEN authorised.resource_record || jsonb_build_object(
          'content_availability', selected_document.content_availability,
          'doc_type', selected_document.doc_type,
          'reference_number', selected_document.reference_number,
          'doc_date', selected_document.doc_date,
          'direction', selected_document.direction,
          'current_version_id', selected_document.current_version_id,
          'has_any_version', EXISTS (
            SELECT 1
            FROM public.document_versions AS historical_version
            WHERE historical_version.org_id = selected_document.org_id
              AND historical_version.document_id = selected_document.id
          )
        )
        ELSE authorised.resource_record
      END AS safe_resource_record,
      coalesce(safe_documents.value, authorised.related_documents) AS safe_related_documents
    FROM authorised
    LEFT JOIN public.documents AS selected_document
      ON authorised.resource_type = 'document'::public.trash_resource_type
     AND selected_document.id = authorised.resource_id
    LEFT JOIN LATERAL (
      SELECT coalesce(jsonb_agg(
        document_item.value || jsonb_build_object(
          'content_availability', document.content_availability,
          'doc_type', document.doc_type,
          'reference_number', document.reference_number,
          'doc_date', document.doc_date,
          'direction', document.direction,
          'current_version_id', document.current_version_id,
          'has_any_version', EXISTS (
            SELECT 1
            FROM public.document_versions AS historical_version
            WHERE historical_version.org_id = document.org_id
              AND historical_version.document_id = document.id
          )
        ) ORDER BY document_item.ordinality
      ), '[]'::jsonb) AS value
      FROM jsonb_array_elements(authorised.related_documents) WITH ORDINALITY AS document_item(value, ordinality)
      JOIN public.documents AS document
        ON document.id = (document_item.value->>'id')::uuid
    ) AS safe_documents ON true
  )
  SELECT
    enriched.resource_id,
    enriched.resource_type,
    enriched.membership_id,
    enriched.cause,
    enriched.parent_membership_id,
    enriched.operation_id,
    enriched.root_resource_id,
    enriched.root_resource_type,
    enriched.root_resource_name,
    enriched.operation_state,
    enriched.trashed_at,
    enriched.trashed_by,
    enriched.trashed_by_name,
    enriched.retention_mode,
    enriched.retention_days,
    enriched.purge_eligible_at,
    enriched.auto_purge_enabled,
    enriched.auto_purge_at,
    enriched.purge_scheduled_at,
    enriched.blocker_count,
    enriched.can_restore,
    enriched.safe_resource_record,
    enriched.related_matters,
    enriched.safe_related_documents,
    enriched.related_links,
    enriched.related_wiki_sections,
    enriched.related_notes,
    enriched.related_inspector_metadata
  FROM enriched
$$;

REVOKE ALL ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type, uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type, uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_exact_trashed_resource_projection(public.trash_resource_type, uuid, uuid) IS
  'Exact authenticated Trash projection with chronology-safe document lifecycle facts; tenant, route lineage, membership, operation and retention fences are delegated to the locked 00086 base.';

CREATE OR REPLACE FUNCTION public.timeline_safe_iso_date(p_value text)
RETURNS date
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $$
BEGIN
  IF p_value IS NULL OR p_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
    RETURN NULL;
  END IF;
  RETURN p_value::date;
EXCEPTION WHEN others THEN
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.read_matter_timeline_chronology(
  p_matter_id uuid,
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 50,
  p_filters text[] DEFAULT ARRAY[]::text[],
  p_selected_document_id uuid DEFAULT NULL
)
RETURNS TABLE(
  outcome text,
  items jsonb,
  total integer,
  unfiltered_total integer,
  "offset" integer,
  "limit" integer,
  selected jsonb,
  source_revision text,
  fetched_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_org uuid;
  v_member_count integer;
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 100));
  v_offset integer;
  v_filters text[] := coalesce(p_filters, ARRAY[]::text[]);
  v_filter text;
  v_from date;
  v_to date;
BEGIN
  -- Reject shaped arrays before cardinality, unnest, array_position or FOREACH
  -- can apply one-dimensional semantics to hostile direct calls. PostgreSQL
  -- reports NULL dimensions for the canonical empty array, which is valid.
  IF array_ndims(v_filters) IS NOT NULL AND array_ndims(v_filters) <> 1 THEN
    RETURN QUERY SELECT 'unavailable', '[]'::jsonb, 0, 0, 0, v_limit, NULL::jsonb, NULL::text, clock_timestamp();
    RETURN;
  END IF;

  IF p_matter_id IS NULL
     OR p_offset IS NULL OR p_offset < 0 OR p_offset > 1000000
     OR p_limit IS NULL OR p_limit < 1 OR p_limit > 100
     OR cardinality(v_filters) > 12
     OR array_position(v_filters, NULL) IS NOT NULL THEN
    RETURN QUERY SELECT 'unavailable', '[]'::jsonb, 0, 0, 0, v_limit, NULL::jsonb, NULL::text, clock_timestamp();
    RETURN;
  END IF;

  FOREACH v_filter IN ARRAY v_filters LOOP
    IF NOT (
      v_filter IN ('incoming', 'outgoing', 'undated', 'dated',
        'attention:processing', 'attention:review', 'attention:failed',
        'attention:pdf-not-attached')
      OR (left(v_filter, 2) = 'q:' AND char_length(v_filter) BETWEEN 3 AND 80
        AND substr(v_filter, 3) !~ '^[[:space:]]|[[:space:]]$'
        AND substr(v_filter, 3) !~ '[[:cntrl:]]')
      OR (left(v_filter, 5) = 'type:' AND char_length(v_filter) BETWEEN 6 AND 80
        AND substr(v_filter, 6) !~ '^[[:space:]]|[[:space:]]$'
        AND substr(v_filter, 6) !~ '[[:cntrl:]]')
      OR (left(v_filter, 5) = 'from:' AND char_length(v_filter) = 15
        AND public.timeline_safe_iso_date(substr(v_filter, 6)) IS NOT NULL)
      OR (left(v_filter, 3) = 'to:' AND char_length(v_filter) = 13
        AND public.timeline_safe_iso_date(substr(v_filter, 4)) IS NOT NULL)
    ) THEN
      RETURN QUERY SELECT 'unavailable', '[]'::jsonb, 0, 0, 0, v_limit, NULL::jsonb, NULL::text, clock_timestamp();
      RETURN;
    END IF;
  END LOOP;

  IF cardinality(v_filters) <> (SELECT count(DISTINCT filter_value) FROM unnest(v_filters) AS filter_value)
     OR (SELECT count(*) FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 2) = 'q:') > 1
     OR (SELECT count(*) FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 5) = 'type:') > 1
     OR (SELECT count(*) FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 10) = 'attention:') > 1
     OR (SELECT count(*) FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 5) = 'from:') > 1
     OR (SELECT count(*) FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 3) = 'to:') > 1
     OR ('incoming' = ANY(v_filters) AND 'outgoing' = ANY(v_filters))
     OR ('dated' = ANY(v_filters) AND 'undated' = ANY(v_filters)) THEN
    RETURN QUERY SELECT 'unavailable', '[]'::jsonb, 0, 0, 0, v_limit, NULL::jsonb, NULL::text, clock_timestamp();
    RETURN;
  END IF;

  SELECT public.timeline_safe_iso_date(substr(filter_value, 6)) INTO v_from
  FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 5) = 'from:';
  SELECT public.timeline_safe_iso_date(substr(filter_value, 4)) INTO v_to
  FROM unnest(v_filters) AS filter_value WHERE left(filter_value, 3) = 'to:';
  IF v_from IS NOT NULL AND v_to IS NOT NULL AND v_from > v_to THEN
    RETURN QUERY SELECT 'unavailable', '[]'::jsonb, 0, 0, 0, v_limit, NULL::jsonb, NULL::text, clock_timestamp();
    RETURN;
  END IF;

  SELECT count(*)::integer, min(authorised.org_id::text)::uuid
  INTO v_member_count, v_org
  FROM (
    SELECT membership.org_id
    FROM public.current_active_tenant_membership() AS membership
    JOIN public.organisations AS organisation ON organisation.id = membership.org_id
    WHERE 'document.view' = ANY(public.organisation_member_capabilities(
      membership.role,
      organisation.owner_membership_id = membership.membership_id,
      'active'::public.organisation_membership_state
    ))
  ) AS authorised;

  IF v_member_count <> 1 OR NOT EXISTS (
    SELECT 1
    FROM public.matters AS matter
    JOIN public.clients AS client
      ON client.id = matter.client_id
      AND client.org_id = matter.org_id
      AND client.record_state = 'active'::public.resource_record_state
      AND client.deleted_at IS NULL
    WHERE matter.id = p_matter_id
      AND matter.org_id = v_org
      AND matter.record_state = 'active'::public.resource_record_state
      AND matter.deleted_at IS NULL
  ) THEN
    RETURN QUERY SELECT 'unavailable', '[]'::jsonb, 0, 0, 0, v_limit, NULL::jsonb, NULL::text, clock_timestamp();
    RETURN;
  END IF;

  v_offset := p_offset;
  RETURN QUERY
  WITH base AS (
    SELECT
      document.id,
      document.display_title,
      document.created_at,
      document.lifecycle_revision,
      document.content_availability,
      document.current_version_id,
      document.doc_type,
      document.reference_number,
      document.doc_date,
      document.direction,
      document.status,
      CASE WHEN document.document_class = 'proceeding' THEN 'canonical' ELSE 'legacy_compatible' END AS classification_state,
      CASE
        WHEN document.status = 'failed' THEN 'failed'
        WHEN document.status = 'needs_review' THEN 'review'
        WHEN document.status IN ('uploaded', 'processing', 'pending_placement') THEN 'processing'
        ELSE 'none'
      END AS attention_state,
      version.id AS version_id,
      document.content_availability = 'metadata_only'::public.document_content_availability
        AND document.current_version_id IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.document_versions AS any_version
          WHERE any_version.org_id = document.org_id AND any_version.document_id = document.id
        ) AS genuine_metadata_only
    FROM public.documents AS document
    LEFT JOIN public.document_versions AS version
      ON version.org_id = document.org_id
      AND version.document_id = document.id
      AND version.id = document.current_version_id
      AND version.state = 'current'::public.document_version_state
      AND version.validation_state = 'valid'::public.document_version_validation_state
    WHERE document.org_id = v_org
      AND document.matter_id = p_matter_id
      AND document.record_state = 'active'::public.document_record_state
      AND document.deleted_at IS NULL
      AND (document.document_class = 'proceeding' OR document.document_class IS NULL)
  ), metadata AS (
    SELECT
      base.*,
      effective.type_rows,
      effective.type_value,
      effective.reference_rows,
      effective.reference_value,
      effective.date_rows,
      effective.date_value,
      effective.direction_rows,
      effective.direction_value,
      effective.metadata_revision
    FROM base
    LEFT JOIN LATERAL (
      SELECT
        count(*) FILTER (WHERE item.field_path = 'document.type' AND item.resolution IN ('automatic', 'accepted', 'corrected')) AS type_rows,
        max(item.normalized_value #>> '{}') FILTER (WHERE item.field_path = 'document.type' AND item.resolution IN ('automatic', 'accepted', 'corrected') AND item.value_type = 'code' AND jsonb_typeof(item.normalized_value) = 'string') AS type_value,
        count(*) FILTER (WHERE item.field_path = 'document.reference_number' AND item.resolution IN ('automatic', 'accepted', 'corrected')) AS reference_rows,
        max(item.normalized_value #>> '{}') FILTER (WHERE item.field_path = 'document.reference_number' AND item.resolution IN ('automatic', 'accepted', 'corrected') AND item.value_type IN ('text', 'code') AND jsonb_typeof(item.normalized_value) = 'string') AS reference_value,
        count(*) FILTER (WHERE item.field_path = 'document.date' AND item.resolution IN ('automatic', 'accepted', 'corrected')) AS date_rows,
        max(item.normalized_value #>> '{}') FILTER (WHERE item.field_path = 'document.date' AND item.resolution IN ('automatic', 'accepted', 'corrected') AND item.value_type = 'date' AND jsonb_typeof(item.normalized_value) = 'string') AS date_value,
        count(*) FILTER (WHERE item.field_path = 'document.direction' AND item.resolution IN ('automatic', 'accepted', 'corrected')) AS direction_rows,
        max(item.normalized_value #>> '{}') FILTER (WHERE item.field_path = 'document.direction' AND item.resolution IN ('automatic', 'accepted', 'corrected') AND item.value_type = 'code' AND jsonb_typeof(item.normalized_value) = 'string') AS direction_value,
        md5(coalesce(string_agg(concat_ws(':', item.id::text, item.semantic_candidate_key, item.field_path, item.value_type::text, item.resolution::text, coalesce(item.normalized_value::text, 'null'), item.winning_document_field_candidate_id::text, coalesce(item.winning_document_field_decision_id::text, '')), '|' ORDER BY item.id), '')) AS metadata_revision
      FROM public.document_effective_metadata AS item
      WHERE item.org_id = v_org
        AND item.document_id = base.id
        AND item.document_version_id = base.version_id
        AND item.field_path IN ('document.type', 'document.reference_number', 'document.date', 'document.direction')
    ) AS effective ON true
  ), projected_values AS (
    SELECT
      metadata.*,
      CASE WHEN metadata.version_id IS NOT NULL AND metadata.type_rows = 1 THEN nullif(metadata.type_value, '') WHEN metadata.genuine_metadata_only THEN metadata.doc_type END AS document_type,
      CASE WHEN metadata.version_id IS NOT NULL AND metadata.reference_rows = 1 THEN nullif(metadata.reference_value, '') WHEN metadata.genuine_metadata_only THEN metadata.reference_number END AS resolved_reference,
      CASE WHEN metadata.version_id IS NOT NULL AND metadata.date_rows = 1 THEN public.timeline_safe_iso_date(metadata.date_value) WHEN metadata.genuine_metadata_only THEN metadata.doc_date END AS effective_date,
      CASE WHEN metadata.version_id IS NOT NULL AND metadata.direction_rows = 1 AND metadata.direction_value IN ('incoming', 'outgoing') THEN metadata.direction_value WHEN metadata.genuine_metadata_only THEN metadata.direction::text END AS effective_direction
    FROM metadata
  ), projected AS (
    SELECT
      projected_values.*,
      md5(concat_ws(':', projected_values.id::text, projected_values.lifecycle_revision::text, coalesce(projected_values.current_version_id::text, ''), coalesce(projected_values.version_id::text, ''), projected_values.content_availability::text, projected_values.status::text, coalesce(projected_values.metadata_revision, ''), coalesce(projected_values.document_type, ''), coalesce(projected_values.resolved_reference, ''), coalesce(projected_values.effective_date::text, ''), coalesce(projected_values.effective_direction, ''))) AS item_revision
    FROM projected_values
  ), filtered AS (
    SELECT projected.*
    FROM projected
    WHERE NOT EXISTS (
      SELECT 1
      FROM unnest(v_filters) AS filter_value
      WHERE (filter_value = 'incoming' AND projected.effective_direction IS DISTINCT FROM 'incoming')
        OR (filter_value = 'outgoing' AND projected.effective_direction IS DISTINCT FROM 'outgoing')
        OR (filter_value = 'undated' AND projected.effective_date IS NOT NULL)
        OR (filter_value = 'dated' AND projected.effective_date IS NULL)
        OR (filter_value = 'attention:processing' AND projected.attention_state <> 'processing')
        OR (filter_value = 'attention:review' AND projected.attention_state <> 'review')
        OR (filter_value = 'attention:failed' AND projected.attention_state <> 'failed')
        OR (filter_value = 'attention:pdf-not-attached' AND projected.content_availability <> 'metadata_only'::public.document_content_availability)
        OR (left(filter_value, 2) = 'q:' AND position(lower(substr(filter_value, 3)) IN lower(coalesce(projected.display_title, '') || ' ' || coalesce(projected.resolved_reference, ''))) = 0)
        OR (left(filter_value, 5) = 'type:' AND lower(projected.document_type) IS DISTINCT FROM lower(substr(filter_value, 6)))
        OR (left(filter_value, 5) = 'from:' AND (projected.effective_date IS NULL OR projected.effective_date < public.timeline_safe_iso_date(substr(filter_value, 6))))
        OR (left(filter_value, 3) = 'to:' AND (projected.effective_date IS NULL OR projected.effective_date > public.timeline_safe_iso_date(substr(filter_value, 4))))
    )
  ), counts AS (
    SELECT
      (SELECT count(*)::integer FROM projected) AS unfiltered_total,
      (SELECT count(*)::integer FROM filtered) AS filtered_total
  ), clamped AS (
    SELECT
      counts.unfiltered_total,
      counts.filtered_total,
      CASE
        WHEN counts.filtered_total = 0 THEN 0
        WHEN v_offset >= counts.filtered_total THEN ((counts.filtered_total - 1) / v_limit) * v_limit
        ELSE v_offset
      END AS canonical_offset
    FROM counts
  ), page AS (
    SELECT filtered.*
    FROM filtered
    ORDER BY filtered.effective_date NULLS LAST, filtered.created_at, filtered.id
    OFFSET (SELECT clamped.canonical_offset FROM clamped)
    LIMIT v_limit
  ), snapshot AS (
    SELECT
      clamped.unfiltered_total,
      clamped.filtered_total,
      clamped.canonical_offset,
      md5(coalesce(string_agg(projected.item_revision, '|' ORDER BY projected.id), '')) AS aggregate_revision
    FROM clamped
    LEFT JOIN projected ON true
    GROUP BY clamped.unfiltered_total, clamped.filtered_total, clamped.canonical_offset
  )
  SELECT
    'ok',
    coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', page.id,
        'title', page.display_title,
        'documentType', page.document_type,
        'referenceNumber', page.resolved_reference,
        'effectiveDate', page.effective_date,
        'direction', page.effective_direction,
        'classificationState', page.classification_state,
        'contentAvailability', page.content_availability,
        'attentionState', page.attention_state,
        'revision', page.item_revision
      ) ORDER BY page.effective_date NULLS LAST, page.created_at, page.id)
      FROM page
    ), '[]'::jsonb),
    snapshot.filtered_total,
    snapshot.unfiltered_total,
    snapshot.canonical_offset,
    v_limit,
    (
      SELECT jsonb_build_object(
        'id', selected_item.id,
        'title', selected_item.display_title,
        'documentType', selected_item.document_type,
        'referenceNumber', selected_item.resolved_reference,
        'effectiveDate', selected_item.effective_date,
        'direction', selected_item.effective_direction,
        'classificationState', selected_item.classification_state,
        'contentAvailability', selected_item.content_availability,
        'attentionState', selected_item.attention_state,
        'revision', selected_item.item_revision
      )
      FROM projected AS selected_item
      WHERE selected_item.id = p_selected_document_id
    ),
    snapshot.aggregate_revision,
    clock_timestamp()
  FROM snapshot;
END $$;

REVOKE ALL ON FUNCTION public.timeline_safe_iso_date(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.read_matter_timeline_chronology(uuid, integer, integer, text[], uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.read_matter_timeline_chronology(uuid, integer, integer, text[], uuid) TO authenticated;

COMMIT;
