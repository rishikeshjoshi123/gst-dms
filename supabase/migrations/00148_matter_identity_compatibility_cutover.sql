-- Remove the obsolete client/financial-year identity boundary while retaining
-- organisation-scoped internal codes and governed external-identifier keys.
BEGIN;

DO $matter_identity_cutover_audit$
DECLARE
  v_duplicate_groups integer;
  v_duplicate_rows integer;
  v_group record;
BEGIN
  IF to_regclass('public.idx_matters_unique_client_fy') IS NULL
     OR to_regclass('public.matters_org_matter_code_unique') IS NULL
     OR to_regclass('public.matter_identifiers_verified_identity_reservation') IS NULL THEN
    RAISE EXCEPTION 'Matter identity cutover prerequisites are missing';
  END IF;

  SELECT count(*)::integer, coalesce(sum(grouped.row_count), 0)::integer
  INTO v_duplicate_groups, v_duplicate_rows
  FROM (
    SELECT count(*) AS row_count
    FROM public.matters
    GROUP BY org_id, client_id, financial_year
    HAVING count(*) > 1
  ) AS grouped;

  RAISE NOTICE
    'Matter identity cutover audit: % duplicate client/year groups across % retained rows; no records modified',
    v_duplicate_groups, v_duplicate_rows;
  FOR v_group IN
    SELECT org_id, client_id, financial_year, count(*) AS row_count
    FROM public.matters
    GROUP BY org_id, client_id, financial_year
    HAVING count(*) > 1
    ORDER BY org_id, client_id, financial_year
  LOOP
    RAISE NOTICE 'Matter identity cutover duplicate group: org %, client %, FY %, rows %',
      v_group.org_id, v_group.client_id, v_group.financial_year, v_group.row_count;
  END LOOP;
END $matter_identity_cutover_audit$;

DROP INDEX public.idx_matters_unique_client_fy;

CREATE INDEX matters_active_client_financial_year_lookup_idx
  ON public.matters(org_id, client_id, financial_year, id)
  WHERE record_state = 'active' AND deleted_at IS NULL;

-- The trigger remains the sole live allocator used by create_matter_command.
-- One organisation-wide transaction lock makes concurrent allocations linear;
-- the next suffix follows the maximum currently retained non-null code across
-- record states, including active and Trash rows.
CREATE OR REPLACE FUNCTION public.generate_matter_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
  v_client_name text;
  v_consonants text;
  v_abbreviation text;
  v_financial_year_digits text;
  v_financial_year_short text;
  v_prefix text;
  v_maximum_sequence numeric;
  v_sequence numeric;
  v_candidate text;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(NEW.org_id::text, 148)
  );

  SELECT client.name INTO v_client_name
  FROM public.clients AS client
  WHERE client.id = NEW.client_id AND client.org_id = NEW.org_id;

  v_consonants := upper(regexp_replace(coalesce(v_client_name, ''), '[AaEeIiOoUu\s\W0-9]', '', 'g'));
  v_abbreviation := left(v_consonants, 3);
  IF length(v_abbreviation) < 3 THEN
    v_abbreviation := upper(left(regexp_replace(coalesce(v_client_name, ''), '[^A-Za-z0-9]', '', 'g'), 3));
  END IF;
  v_abbreviation := rpad(v_abbreviation, 3, 'X');

  v_financial_year_digits := regexp_replace(NEW.financial_year, '[^0-9]', '', 'g');
  IF length(v_financial_year_digits) >= 6 THEN
    v_financial_year_short := substring(v_financial_year_digits FROM 3 FOR 2)
      || substring(v_financial_year_digits FROM 5 FOR 2);
  ELSE
    v_financial_year_short := v_financial_year_digits;
  END IF;
  v_prefix := v_abbreviation || '-' || v_financial_year_short || '-';

  IF EXISTS (
    SELECT 1
    FROM public.matters AS matter
    WHERE matter.org_id = NEW.org_id
      AND matter.matter_code LIKE v_prefix || '%'
      AND substring(matter.matter_code FROM length(v_prefix) + 1) !~ '^[0-9]+$'
  ) THEN
    RAISE EXCEPTION 'Matter code sequence is malformed for organisation prefix'
      USING ERRCODE = '23505';
  END IF;

  SELECT max(substring(matter.matter_code FROM length(v_prefix) + 1)::numeric)
  INTO v_maximum_sequence
  FROM public.matters AS matter
  WHERE matter.org_id = NEW.org_id
    AND matter.matter_code LIKE v_prefix || '%';

  IF v_maximum_sequence IS NOT NULL AND v_maximum_sequence >= 999999999999999999::numeric THEN
    RAISE EXCEPTION 'Matter code sequence is exhausted for organisation prefix'
      USING ERRCODE = '23505';
  END IF;
  v_sequence := coalesce(v_maximum_sequence, 0) + 1;
  v_candidate := v_prefix || lpad(v_sequence::text, 2, '0');

  NEW.matter_code := v_candidate;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trash_restore_blocker(
  p_org_id uuid,
  p_operation_id uuid
)
RETURNS TABLE(blocker_code text, blocking_operation_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, public
AS $$
DECLARE
  operation public.trash_operations%ROWTYPE;
  root_matter public.matters%ROWTYPE;
  root_document public.documents%ROWTYPE;
  parent_operation uuid;
BEGIN
  SELECT * INTO operation FROM public.trash_operations
  WHERE org_id = p_org_id AND id = p_operation_id;
  IF operation.id IS NULL THEN
    RETURN QUERY SELECT 'invalid_operation'::text, NULL::uuid; RETURN;
  END IF;

  IF (SELECT count(*) FROM public.resource_trash_memberships membership
      WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
        AND membership.state='active')
     <> operation.included_client_count + operation.included_matter_count + operation.included_document_count
     OR (SELECT count(*) FROM public.resource_trash_memberships membership
         WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
           AND membership.state='active' AND membership.cause='direct'
           AND membership.parent_membership_id IS NULL
           AND membership.resource_type=operation.root_resource_type
           AND membership.resource_id=operation.root_resource_id) <> 1
     OR EXISTS (
       SELECT 1 FROM public.resource_trash_memberships membership
       WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
         AND membership.state<>'active'
     ) THEN
    RETURN QUERY SELECT 'membership_drift'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    LEFT JOIN public.clients client ON membership.resource_type='client'
      AND client.org_id=membership.org_id AND client.id=membership.resource_id
      AND client.record_state='trashed' AND client.deleted_at IS NOT NULL
      AND client.active_trash_membership_id=membership.id
    LEFT JOIN public.matters matter ON membership.resource_type='matter'
      AND matter.org_id=membership.org_id AND matter.id=membership.resource_id
      AND matter.record_state='trashed' AND matter.deleted_at IS NOT NULL
      AND matter.active_trash_membership_id=membership.id
    LEFT JOIN public.documents document ON membership.resource_type='document'
      AND document.org_id=membership.org_id AND document.id=membership.resource_id
      AND document.record_state::text='trashed' AND document.deleted_at IS NOT NULL
      AND document.active_trash_membership_id=membership.id
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
      AND membership.state='active'
      AND ((membership.resource_type='client' AND client.id IS NULL)
        OR (membership.resource_type='matter' AND matter.id IS NULL)
        OR (membership.resource_type='document' AND document.id IS NULL))
  ) THEN
    RETURN QUERY SELECT 'resource_state_drift'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships child
    LEFT JOIN public.resource_trash_memberships parent
      ON parent.org_id=child.org_id AND parent.id=child.parent_membership_id
      AND parent.operation_id=child.operation_id AND parent.state='active'
    LEFT JOIN public.matters matter
      ON child.resource_type='matter' AND matter.org_id=child.org_id AND matter.id=child.resource_id
    LEFT JOIN public.documents document
      ON child.resource_type='document' AND document.org_id=child.org_id AND document.id=child.resource_id
    WHERE child.org_id=p_org_id AND child.operation_id=p_operation_id
      AND child.state='active' AND child.cause='inherited'
      AND (parent.id IS NULL
        OR (child.resource_type='matter' AND (parent.resource_type<>'client' OR parent.resource_id<>matter.client_id))
        OR (child.resource_type='document' AND (parent.resource_type<>'matter' OR parent.resource_id<>document.matter_id)))
  ) THEN
    RETURN QUERY SELECT 'membership_lineage_drift'::text, NULL::uuid; RETURN;
  END IF;

  IF operation.root_resource_type='matter' THEN
    SELECT * INTO root_matter FROM public.matters WHERE org_id=p_org_id AND id=operation.root_resource_id;
    IF root_matter.id IS NULL THEN
      RETURN QUERY SELECT 'invalid_parent'::text, NULL::uuid; RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.clients client WHERE client.org_id=p_org_id
      AND client.id=root_matter.client_id AND client.record_state='active' AND client.deleted_at IS NULL) THEN
      SELECT membership.operation_id INTO parent_operation
      FROM public.clients client
      JOIN public.resource_trash_memberships membership
        ON membership.org_id=client.org_id AND membership.id=client.active_trash_membership_id
      WHERE client.org_id=p_org_id AND client.id=root_matter.client_id AND membership.state='active';
      RETURN QUERY SELECT 'parent_in_trash'::text, parent_operation; RETURN;
    END IF;
  ELSIF operation.root_resource_type='document' THEN
    SELECT * INTO root_document FROM public.documents WHERE org_id=p_org_id AND id=operation.root_resource_id;
    SELECT * INTO root_matter FROM public.matters WHERE org_id=p_org_id AND id=root_document.matter_id;
    IF root_document.id IS NULL OR root_matter.id IS NULL THEN
      RETURN QUERY SELECT 'invalid_parent'::text, NULL::uuid; RETURN;
    END IF;
    IF root_matter.record_state<>'active' OR root_matter.deleted_at IS NOT NULL THEN
      SELECT membership.operation_id INTO parent_operation
      FROM public.resource_trash_memberships membership
      WHERE membership.org_id=p_org_id AND membership.id=root_matter.active_trash_membership_id
        AND membership.state='active';
      RETURN QUERY SELECT 'parent_in_trash'::text, parent_operation; RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.clients client WHERE client.org_id=p_org_id
      AND client.id=root_matter.client_id AND client.record_state='active' AND client.deleted_at IS NULL) THEN
      SELECT membership.operation_id INTO parent_operation
      FROM public.clients client
      JOIN public.resource_trash_memberships membership
        ON membership.org_id=client.org_id AND membership.id=client.active_trash_membership_id
      WHERE client.org_id=p_org_id AND client.id=root_matter.client_id AND membership.state='active';
      RETURN QUERY SELECT 'parent_in_trash'::text, parent_operation; RETURN;
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    JOIN public.clients restoring ON membership.resource_type='client'
      AND restoring.org_id=membership.org_id AND restoring.id=membership.resource_id
    JOIN public.clients active ON active.org_id=restoring.org_id AND active.id<>restoring.id
      AND active.record_state='active' AND active.deleted_at IS NULL
      AND ((restoring.gstin IS NOT NULL AND active.gstin=restoring.gstin)
        OR (restoring.pan IS NOT NULL AND active.pan=restoring.pan))
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id AND membership.state='active'
  ) THEN
    RETURN QUERY SELECT 'client_identifier_conflict'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    JOIN public.matters restoring ON membership.resource_type='matter'
      AND restoring.org_id=membership.org_id AND restoring.id=membership.resource_id
    JOIN public.matters active ON active.org_id=restoring.org_id AND active.id<>restoring.id
      AND active.record_state='active' AND active.deleted_at IS NULL
      AND restoring.matter_code IS NOT NULL AND active.matter_code=restoring.matter_code
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id AND membership.state='active'
  ) OR EXISTS (
    SELECT 1
    FROM public.resource_trash_memberships AS membership
    JOIN public.matter_identifiers AS restoring_identifier
      ON membership.resource_type='matter'
      AND restoring_identifier.org_id=membership.org_id
      AND restoring_identifier.matter_id=membership.resource_id
      AND restoring_identifier.lifecycle_state='active'
      AND restoring_identifier.identifier_role='self_identifier'
      AND restoring_identifier.verification_method='human_source'
      AND restoring_identifier.identity_eligible
    JOIN public.matter_identifiers AS active_identifier
      ON active_identifier.org_id=restoring_identifier.org_id
      AND active_identifier.matter_id<>restoring_identifier.matter_id
      AND active_identifier.issuer_namespace_normalized=restoring_identifier.issuer_namespace_normalized
      AND active_identifier.identifier_kind=restoring_identifier.identifier_kind
      AND active_identifier.normalized_value=restoring_identifier.normalized_value
      AND active_identifier.lifecycle_state='active'
      AND active_identifier.identifier_role='self_identifier'
      AND active_identifier.verification_method='human_source'
      AND active_identifier.identity_eligible
    JOIN public.matters AS active_matter
      ON active_matter.org_id=active_identifier.org_id
      AND active_matter.id=active_identifier.matter_id
      AND active_matter.record_state='active'
      AND active_matter.deleted_at IS NULL
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id
      AND membership.state='active'
  ) THEN
    RETURN QUERY SELECT 'matter_identifier_conflict'::text, NULL::uuid; RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.resource_trash_memberships membership
    JOIN public.document_versions restoring_version
      ON membership.resource_type='document' AND restoring_version.org_id=membership.org_id
      AND restoring_version.document_id=membership.resource_id
    JOIN public.file_assets restoring_asset
      ON restoring_asset.org_id=restoring_version.org_id AND restoring_asset.id=restoring_version.asset_id
      AND restoring_asset.sha256 IS NOT NULL
    JOIN public.file_assets active_asset
      ON active_asset.org_id=restoring_asset.org_id AND active_asset.sha256=restoring_asset.sha256
    JOIN public.document_versions active_version
      ON active_version.org_id=active_asset.org_id AND active_version.asset_id=active_asset.id
      AND active_version.document_id<>membership.resource_id
    JOIN public.documents active_document
      ON active_document.org_id=active_version.org_id AND active_document.id=active_version.document_id
      AND active_document.record_state::text='active' AND active_document.deleted_at IS NULL
    WHERE membership.org_id=p_org_id AND membership.operation_id=p_operation_id AND membership.state='active'
  ) THEN
    RETURN QUERY SELECT 'document_content_conflict'::text, NULL::uuid; RETURN;
  END IF;

  RETURN;
END $$;

DO $matter_identity_cutover_assertions$
BEGIN
  IF to_regclass('public.idx_matters_unique_client_fy') IS NOT NULL
     OR to_regclass('public.matters_active_client_financial_year_lookup_idx') IS NULL
     OR to_regclass('public.matters_org_matter_code_unique') IS NULL
     OR to_regclass('public.matter_identifiers_verified_identity_reservation') IS NULL THEN
    RAISE EXCEPTION 'Matter identity cutover index contract failed';
  END IF;
END $matter_identity_cutover_assertions$;

COMMIT;
