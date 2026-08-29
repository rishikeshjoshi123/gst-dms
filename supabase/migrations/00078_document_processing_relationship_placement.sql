-- Service-only, replay-safe relationship placement for a validated processing
-- version. The command consumes only the bounded current-effective projection;
-- it deliberately has no raw AI payload or legacy document-metadata input.
BEGIN;

CREATE TABLE public.document_relationship_placement_effects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  document_id uuid NOT NULL REFERENCES public.documents(id) ON DELETE CASCADE,
  document_version_id uuid NOT NULL REFERENCES public.document_versions(id) ON DELETE CASCADE,
  effect_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_relationship_placement_effects_unique
    UNIQUE (document_version_id, effect_key)
);

CREATE FUNCTION public.place_document_processing_relationships(
  p_org_id uuid,
  p_matter_id uuid,
  p_document_id uuid,
  p_document_version_id uuid,
  p_uploaded_by uuid
)
RETURNS TABLE(code text, link_count integer, notification_count integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  source_document public.documents%ROWTYPE;
  source_version public.document_versions%ROWTYPE;
  source_type text;
  source_references text[];
  reference_value text;
  target record;
  cross_target record;
  cross_target_current boolean;
  target_count integer;
  inferred_link_type public.link_type;
  effect_created boolean;
  links_created integer := 0;
  notifications_created integer := 0;
BEGIN
  IF p_org_id IS NULL OR p_matter_id IS NULL OR p_document_id IS NULL
     OR p_document_version_id IS NULL OR p_uploaded_by IS NULL THEN
    RETURN QUERY SELECT 'invalid_request'::text, 0, 0;
    RETURN;
  END IF;

  -- Serialize same-version replay and same-matter placement attempts. These
  -- advisory locks do not coordinate provenance commands, so row-lock order
  -- and the NOWAIT target fence below remain the deadlock remediation.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_document_version_id::text, 78));
  PERFORM pg_advisory_xact_lock(hashtextextended(p_org_id::text || ':' || p_matter_id::text, 78));

  SELECT * INTO source_version FROM public.document_versions
  WHERE id = p_document_version_id
    AND document_id = p_document_id
    AND org_id = p_org_id
    AND state = 'current'::public.document_version_state
    AND validation_state = 'valid'::public.document_version_validation_state
  FOR UPDATE;
  SELECT document.* INTO source_document
  FROM public.documents AS document
  WHERE document.id = p_document_id
    AND document.org_id = p_org_id
    AND document.matter_id = p_matter_id
    AND document.current_version_id = p_document_version_id
    AND document.created_by = p_uploaded_by
    AND document.deleted_at IS NULL
    AND document.record_state = 'active'::public.document_record_state
  FOR UPDATE;
  IF source_document.id IS NULL OR source_version.id IS NULL THEN
    RETURN QUERY SELECT 'identity_mismatch'::text, 0, 0;
    RETURN;
  END IF;

  -- Provenance begin/finish commands acquire version -> document -> matter ->
  -- client. Keep that production order for the source before taking the
  -- target-set fence. The matter/client lock then prevents lifecycle changes
  -- and new documents joining this matter while the snapshot is assembled.
  PERFORM 1
  FROM public.matters AS matter
  JOIN public.clients AS client
    ON client.id = matter.client_id
    AND client.org_id = matter.org_id
  WHERE matter.id = p_matter_id
    AND matter.org_id = p_org_id
    AND matter.deleted_at IS NULL
    AND matter.status = 'active'::public.matter_status
    AND client.deleted_at IS NULL
  FOR UPDATE OF matter, client;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'identity_mismatch'::text, 0, 0;
    RETURN;
  END IF;

  -- Corrections replace rows in this projection. Holding the source before
  -- its values are read prevents a stale effective reference from creating an
  -- automatic link after a concurrent correction.
  PERFORM 1 FROM public.document_effective_metadata
  WHERE org_id = p_org_id AND document_id = p_document_id
    AND document_version_id = p_document_version_id
  FOR UPDATE;

  -- Lock every active, non-deleted current-version document in this matter,
  -- not just an initially selected exact match. Trashed rows are deliberately
  -- excluded so their ordinary unmatched-reference pending fallback is not
  -- converted into a transient busy result. A concurrent correction can
  -- otherwise make a second target exact after target_count has been read.
  -- Each candidate uses the production
  -- version -> document -> effective order. The UUID ordering is deterministic
  -- for multiple candidates, but we must not wait after holding the matter:
  -- begin/finish may already hold a different candidate's version/document and
  -- be waiting for this matter. A busy or changed candidate aborts this nested
  -- lock pass, rolls back its partial candidate locks, and returns no effect;
  -- the worker may retry from a fresh snapshot.
  BEGIN
    FOR target IN
      SELECT document.id, document.current_version_id
      FROM public.documents AS document
      JOIN public.document_versions AS version
        ON version.id = document.current_version_id
        AND version.org_id = document.org_id
        AND version.document_id = document.id
      WHERE document.org_id = p_org_id
        AND document.matter_id = p_matter_id
        AND document.deleted_at IS NULL
        AND document.record_state = 'active'::public.document_record_state
      ORDER BY document.id
    LOOP
      PERFORM 1
      FROM public.document_versions AS version
      WHERE version.id = target.current_version_id
        AND version.org_id = p_org_id
        AND version.document_id = target.id
      FOR UPDATE NOWAIT;
      IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '55P03', MESSAGE = 'relationship target changed';
      END IF;
      PERFORM 1 FROM public.documents AS document
      WHERE document.id = target.id
        AND document.org_id = p_org_id
        AND document.matter_id = p_matter_id
        AND document.current_version_id = target.current_version_id
        AND document.deleted_at IS NULL
        AND document.record_state = 'active'::public.document_record_state
      FOR UPDATE NOWAIT;
      IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = '55P03', MESSAGE = 'relationship target changed';
      END IF;
      PERFORM 1
      FROM public.document_effective_metadata AS effective
      JOIN public.documents AS document
        ON document.id = effective.document_id
        AND document.current_version_id = effective.document_version_id
      WHERE effective.org_id = p_org_id
        AND effective.document_id = target.id
        AND effective.document_version_id = target.current_version_id
      FOR UPDATE OF effective NOWAIT;
    END LOOP;
  EXCEPTION WHEN lock_not_available THEN
    RETURN QUERY SELECT 'target_snapshot_busy'::text, 0, 0;
    RETURN;
  END;

  -- This is the only same-matter target snapshot used for decisions. It is
  -- read only after every potentially eligible target has been locked and its
  -- current effective values have been refreshed by the projection reader.
  SELECT relationship.doc_type, relationship.referenced_document_numbers
  INTO source_type, source_references
  FROM public.read_current_matter_relationship_projection(p_org_id, p_matter_id) AS relationship
  WHERE relationship.document_id = p_document_id
    AND relationship.document_version_id = p_document_version_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'current_effective_relationship_unavailable'::text, 0, 0;
    RETURN;
  END IF;
  IF coalesce(cardinality(source_references), 0) = 0 THEN
    -- Absent, cleared, rejected, ambiguous, stale, or invalid relationship
    -- values must never revive progression inference.
    RETURN QUERY SELECT 'no_effective_references'::text, 0, 0;
    RETURN;
  END IF;

  FOR reference_value IN SELECT DISTINCT value FROM unnest(source_references) AS value
    WHERE value IS NOT NULL AND btrim(value) <> ''
  LOOP
    SELECT count(*) INTO target_count
    FROM public.read_current_matter_relationship_projection(p_org_id, p_matter_id) AS relationship
    WHERE relationship.document_id <> p_document_id
      AND relationship.reference_number = reference_value;

    IF target_count = 1 THEN
      -- target.doc_type is deliberately selected from the post-lock projection,
      -- never from the pre-lock candidate used to identify the target set.
      SELECT relationship.document_id, relationship.doc_type INTO target
      FROM public.read_current_matter_relationship_projection(p_org_id, p_matter_id) AS relationship
      WHERE relationship.document_id <> p_document_id
        AND relationship.reference_number = reference_value;
      inferred_link_type := CASE
        WHEN source_type = 'APL-01' AND target.doc_type IN ('OIO', 'DRC-01') THEN 'challenges'::public.link_type
        WHEN source_type = 'APL-05' AND target.doc_type IN ('APL-02', 'OIA') THEN 'challenges'::public.link_type
        WHEN source_type = 'APL-02' AND target.doc_type = 'APL-01' THEN 'arises_from'::public.link_type
        WHEN source_type = 'OIO' AND target.doc_type IN ('DRC-01', 'SCN') THEN 'arises_from'::public.link_type
        WHEN source_type = 'DRC-07' AND target.doc_type IN ('OIO', 'APL-02') THEN 'summarizes'::public.link_type
        WHEN source_type IN ('DRC-03', 'REPLY') AND target.doc_type IS NOT NULL THEN 'responds_to'::public.link_type
        WHEN source_type = 'HC_WRIT' AND target.doc_type IN ('GSTAT', 'APL-02') THEN 'challenges'::public.link_type
        ELSE 'responds_to'::public.link_type END;
      INSERT INTO public.document_links(from_doc_id, to_doc_id, link_type, confidence, status, match_method)
      VALUES (p_document_id, target.document_id, inferred_link_type, 0.95, 'confirmed', 'exact_reference')
      ON CONFLICT (from_doc_id, to_doc_id, link_type) DO NOTHING;
      IF FOUND THEN links_created := links_created + 1; END IF;
      CONTINUE;
    END IF;

    -- Fuzzy selection is also from the post-lock projection. It is a pending
    -- fallback, even when an exact collision exists in this stable snapshot.
    SELECT relationship.document_id, relationship.doc_type INTO target
    FROM public.read_current_matter_relationship_projection(p_org_id, p_matter_id) AS relationship
    WHERE relationship.document_id <> p_document_id
      AND relationship.reference_number IS NOT NULL
      AND similarity(relationship.reference_number, reference_value) > 0.6
    ORDER BY similarity(relationship.reference_number, reference_value) DESC, relationship.document_id
    LIMIT 1;
    IF FOUND THEN
      -- Re-read the chosen fuzzy target from the locked projection. This is
      -- intentionally redundant with selection so its current document type
      -- can never be inherited from a pre-lock candidate snapshot.
      SELECT relationship.document_id, relationship.doc_type INTO target
      FROM public.read_current_matter_relationship_projection(p_org_id, p_matter_id) AS relationship
      WHERE relationship.document_id = target.document_id
        AND relationship.reference_number IS NOT NULL
        AND similarity(relationship.reference_number, reference_value) > 0.6;
      IF NOT FOUND THEN CONTINUE; END IF;
      inferred_link_type := 'responds_to'::public.link_type;
      INSERT INTO public.document_links(from_doc_id, to_doc_id, link_type, confidence, status, match_method)
      VALUES (p_document_id, target.document_id, inferred_link_type, 0.70, 'pending', 'fuzzy_reference')
      ON CONFLICT (from_doc_id, to_doc_id, link_type) DO NOTHING;
      IF FOUND THEN links_created := links_created + 1; END IF;
      INSERT INTO public.document_relationship_placement_effects(org_id, document_id, document_version_id, effect_key)
      VALUES (p_org_id, p_document_id, p_document_version_id, 'fuzzy:' || reference_value || ':' || target.document_id::text)
      ON CONFLICT DO NOTHING RETURNING true INTO effect_created;
      IF effect_created THEN
        INSERT INTO public.notifications(org_id, user_id, type, title, body, entity_type, entity_id)
        VALUES (p_org_id, p_uploaded_by, 'chain_suggestion', 'Confirm Document Link',
          'A link was automatically inferred. Please confirm it is correct.', 'document', p_document_id);
        notifications_created := notifications_created + 1;
      END IF;
      CONTINUE;
    END IF;

    -- Do not use the unlocked cross-matter existence reader for a Review
    -- effect. Candidates are only hints; each is locked and revalidated below.
    cross_target_current := false;
    FOR cross_target IN
      SELECT document.id AS document_id,
        document.current_version_id AS document_version_id,
        matter.id AS matter_id
      FROM public.documents AS document
      JOIN public.matters AS matter
        ON matter.id = document.matter_id
        AND matter.org_id = document.org_id
      JOIN public.clients AS client
        ON client.id = matter.client_id
        AND client.org_id = matter.org_id
      JOIN public.document_versions AS version
        ON version.id = document.current_version_id
        AND version.org_id = document.org_id
        AND version.document_id = document.id
        AND version.state = 'current'::public.document_version_state
        AND version.validation_state = 'valid'::public.document_version_validation_state
      CROSS JOIN LATERAL (
        SELECT count(*) AS rows,
          array_agg(metadata.normalized_value #>> '{}') FILTER (
            WHERE jsonb_typeof(metadata.normalized_value) = 'string'
          ) AS values
        FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
        WHERE metadata.field_path = 'document.reference_number'
      ) AS reference
      WHERE document.org_id = p_org_id
        AND document.matter_id <> p_matter_id
        AND document.deleted_at IS NULL
        AND document.record_state = 'active'::public.document_record_state
        AND matter.deleted_at IS NULL
        AND matter.status = 'active'::public.matter_status
        AND client.deleted_at IS NULL
        AND reference.rows = 1
        AND cardinality(reference.values) = 1
        AND reference.values[1] = reference_value
      ORDER BY document.id
    LOOP
      -- Lock cross-matter hints in the same version -> document -> matter /
      -- client -> effective order. Every acquisition is NOWAIT, so candidates
      -- from another matter cannot form a cross-document/cross-matter cycle;
      -- unavailable or changed candidates safely fall through to pending.
      BEGIN
        PERFORM 1
        FROM public.document_versions AS version
        WHERE version.id = cross_target.document_version_id
          AND version.org_id = p_org_id
          AND version.document_id = cross_target.document_id
          AND version.state = 'current'::public.document_version_state
          AND version.validation_state = 'valid'::public.document_version_validation_state
        FOR UPDATE NOWAIT;
        IF NOT FOUND THEN
          RAISE EXCEPTION USING ERRCODE = '55P03', MESSAGE = 'cross-matter target changed';
        END IF;
        PERFORM 1 FROM public.documents AS document
        WHERE document.id = cross_target.document_id
          AND document.org_id = p_org_id
          AND document.matter_id = cross_target.matter_id
          AND document.current_version_id = cross_target.document_version_id
          AND document.deleted_at IS NULL
          AND document.record_state = 'active'::public.document_record_state
        FOR UPDATE NOWAIT;
        IF NOT FOUND THEN
          RAISE EXCEPTION USING ERRCODE = '55P03', MESSAGE = 'cross-matter target changed';
        END IF;
        PERFORM 1
        FROM public.matters AS matter
        JOIN public.clients AS client
          ON client.id = matter.client_id
          AND client.org_id = matter.org_id
        WHERE matter.id = cross_target.matter_id
          AND matter.org_id = p_org_id
          AND matter.deleted_at IS NULL
          AND matter.status = 'active'::public.matter_status
          AND client.deleted_at IS NULL
        FOR UPDATE OF matter, client NOWAIT;
        IF NOT FOUND THEN
          RAISE EXCEPTION USING ERRCODE = '55P03', MESSAGE = 'cross-matter target changed';
        END IF;
        PERFORM 1
        FROM public.document_effective_metadata AS effective
        JOIN public.documents AS document
          ON document.id = effective.document_id
          AND document.current_version_id = effective.document_version_id
        WHERE effective.org_id = p_org_id
          AND effective.document_id = cross_target.document_id
          AND effective.document_version_id = cross_target.document_version_id
        FOR UPDATE OF effective NOWAIT;
      EXCEPTION WHEN lock_not_available THEN
        CONTINUE;
      END;

      SELECT EXISTS (
        SELECT 1
        FROM public.documents AS document
        JOIN public.matters AS matter
          ON matter.id = document.matter_id
          AND matter.org_id = document.org_id
        JOIN public.clients AS client
          ON client.id = matter.client_id
          AND client.org_id = matter.org_id
        JOIN public.document_versions AS version
          ON version.id = document.current_version_id
          AND version.org_id = document.org_id
          AND version.document_id = document.id
          AND version.state = 'current'::public.document_version_state
          AND version.validation_state = 'valid'::public.document_version_validation_state
        CROSS JOIN LATERAL (
          SELECT count(*) AS rows,
            array_agg(metadata.normalized_value #>> '{}') FILTER (
              WHERE jsonb_typeof(metadata.normalized_value) = 'string'
            ) AS values
          FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
          WHERE metadata.field_path = 'document.reference_number'
        ) AS reference
        WHERE document.id = cross_target.document_id
          AND document.org_id = p_org_id
          AND document.matter_id = cross_target.matter_id
          AND document.matter_id <> p_matter_id
          AND document.deleted_at IS NULL
          AND document.record_state = 'active'::public.document_record_state
          AND matter.deleted_at IS NULL
          AND matter.status = 'active'::public.matter_status
          AND client.deleted_at IS NULL
          AND reference.rows = 1
          AND cardinality(reference.values) = 1
          AND reference.values[1] = reference_value
      ) INTO cross_target_current;
      IF cross_target_current THEN EXIT; END IF;
    END LOOP;

    IF cross_target_current THEN
      UPDATE public.documents SET status = 'needs_review'::public.doc_status,
        review_reason = 'Referenced document found in a different matter — manual review required before linking.'
      WHERE id = p_document_id AND org_id = p_org_id AND current_version_id = p_document_version_id
        AND deleted_at IS NULL AND record_state = 'active'::public.document_record_state;
      INSERT INTO public.document_relationship_placement_effects(org_id, document_id, document_version_id, effect_key)
      VALUES (p_org_id, p_document_id, p_document_version_id, 'cross_matter:' || reference_value)
      ON CONFLICT DO NOTHING RETURNING true INTO effect_created;
      IF effect_created THEN
        INSERT INTO public.notifications(org_id, user_id, type, title, body, entity_type, entity_id)
        VALUES (p_org_id, p_uploaded_by, 'chain_suggestion', 'Possible Misfiled Document',
          'Document references ' || reference_value || ' which was found in a different matter. Please review.', 'document', p_document_id);
        notifications_created := notifications_created + 1;
      END IF;
      CONTINUE;
    END IF;

    inferred_link_type := 'responds_to'::public.link_type;
    -- Pending links have no database uniqueness constraint: this command's
    -- source-version advisory lock plus this guarded read/insert make retries
    -- and concurrent calls for the same processing version idempotent.
    IF NOT EXISTS (SELECT 1 FROM public.document_links
      WHERE from_doc_id = p_document_id AND to_doc_id IS NULL AND pending_ref_number = reference_value) THEN
      INSERT INTO public.document_links(from_doc_id, to_doc_id, link_type, confidence, status, match_method, pending_ref_number)
      VALUES (p_document_id, NULL, inferred_link_type, NULL, 'pending', 'pending', reference_value);
      links_created := links_created + 1;
    END IF;
  END LOOP;

  RETURN QUERY SELECT 'placed'::text, links_created, notifications_created;
END $$;

-- The 00077 cross-matter reader was intentionally bounded to document/version
-- validity. Processing placement must additionally reject a deleted or
-- inactive target matter/client before it can open Review on the source.
CREATE OR REPLACE FUNCTION public.current_relationship_reference_exists_in_other_matter(
  p_org_id uuid,
  p_matter_id uuid,
  p_reference_number text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.documents AS document
    JOIN public.matters AS matter
      ON matter.id = document.matter_id AND matter.org_id = document.org_id
    JOIN public.clients AS client
      ON client.id = matter.client_id AND client.org_id = matter.org_id
    JOIN public.document_versions AS version
      ON version.org_id = document.org_id
      AND version.id = document.current_version_id
      AND version.document_id = document.id
      AND version.state = 'current'::public.document_version_state
      AND version.validation_state = 'valid'::public.document_version_validation_state
    CROSS JOIN LATERAL (
      SELECT count(*) AS rows,
        array_agg(metadata.normalized_value #>> '{}') FILTER (
          WHERE jsonb_typeof(metadata.normalized_value) = 'string'
        ) AS values
      FROM public.read_current_document_effective_metadata(p_org_id, ARRAY[document.id]) AS metadata
      WHERE metadata.field_path = 'document.reference_number'
    ) AS reference
    WHERE document.org_id = p_org_id
      AND document.matter_id <> p_matter_id
      AND document.deleted_at IS NULL
      AND document.record_state = 'active'::public.document_record_state
      AND matter.deleted_at IS NULL
      AND matter.status = 'active'::public.matter_status
      AND client.deleted_at IS NULL
      AND reference.rows = 1
      AND cardinality(reference.values) = 1
      AND reference.values[1] = p_reference_number
  )
$$;

-- The ledger is private command state. Keep normal SECURITY DEFINER owner
-- access for placement, but require RLS as a second fence against any future
-- accidental browser grant; no browser policies are intentionally provided.
ALTER TABLE public.document_relationship_placement_effects ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.document_relationship_placement_effects FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.place_document_processing_relationships(uuid, uuid, uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.place_document_processing_relationships(uuid, uuid, uuid, uuid, uuid)
  TO service_role;

COMMENT ON FUNCTION public.place_document_processing_relationships(uuid, uuid, uuid, uuid, uuid) IS
  'Service-only current-effective processing relationship placement. Fences organisation, matter, current valid version, lifecycle, and uploader identity; replay-safe links and notifications never read legacy AI payloads.';

COMMIT;
