-- 00156_matter_supporting_files.sql
-- CaseChain tranche D11-T10: Matter Files authority foundation.
-- Additive supporting-file category catalogue, document category assignment,
-- and optional same-matter supporting-to-proceeding evidence associations.
-- No Timeline/document_relationships interference; associations never enter
-- the procedural graph.
BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Enum — evidence association kinds
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TYPE public.document_evidence_association_kind AS ENUM (
  'supports',
  'submitted_with',
  'attachment_to',
  'background'
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Supporting-file category catalogue
-- ═══════════════════════════════════════════════════════════════════════════
-- Versioned rows with a stable UUID identity. System rows (org_id IS NULL)
-- are immutable. Org rows may be superseded by Owner/Admin only.  Retired
-- rows remain renderable via the selected-category reader but excluded from
-- active catalogue browsing.
CREATE TABLE public.supporting_file_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_key text NOT NULL CHECK (
    char_length(category_key) BETWEEN 1 AND 50
    AND category_key !~ '[[:cntrl:]]'
  ),
  label text NOT NULL CHECK (
    char_length(label) BETWEEN 1 AND 100
    AND label !~ '[[:cntrl:]]'
  ),
  sort_order smallint NOT NULL,
  lifecycle text NOT NULL CHECK (lifecycle IN ('active', 'retired')),
  org_id uuid REFERENCES public.organisations(id) ON DELETE RESTRICT,
  category_version bigint NOT NULL CHECK (category_version >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT
);

-- Scoped uniqueness: system (org_id IS NULL) and tenant (org_id IS NOT NULL)
-- 1. Version uniqueness per scope
CREATE UNIQUE INDEX supporting_file_categories_system_key_version_idx
  ON public.supporting_file_categories(category_key, category_version)
  WHERE org_id IS NULL;

CREATE UNIQUE INDEX supporting_file_categories_org_key_version_idx
  ON public.supporting_file_categories(org_id, category_key, category_version)
  WHERE org_id IS NOT NULL;

-- 2. Exactly one active version per key per scope
CREATE UNIQUE INDEX supporting_file_categories_system_active_key_idx
  ON public.supporting_file_categories(category_key)
  WHERE org_id IS NULL AND lifecycle = 'active';

CREATE UNIQUE INDEX supporting_file_categories_org_active_key_idx
  ON public.supporting_file_categories(org_id, category_key)
  WHERE org_id IS NOT NULL AND lifecycle = 'active';

ALTER TABLE public.supporting_file_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supporting_file_categories FORCE ROW LEVEL SECURITY;

-- Deterministic reserved UUIDs in the 00156 namespace.
INSERT INTO public.supporting_file_categories (id, category_key, label, sort_order, lifecycle, org_id, category_version) VALUES
  ('01560000-0000-0000-0000-000000000001', 'evidence',              'Evidence',                        10, 'active', NULL, 1),
  ('01560000-0000-0000-0000-000000000002', 'financial_records',     'Invoices & financial records',     20, 'active', NULL, 1),
  ('01560000-0000-0000-0000-000000000003', 'correspondence',        'Correspondence',                  30, 'active', NULL, 1),
  ('01560000-0000-0000-0000-000000000004', 'research_authorities',  'Research & authorities',           40, 'active', NULL, 1),
  ('01560000-0000-0000-0000-000000000005', 'media_site_material',   'Media & site material',            50, 'active', NULL, 1),
  ('01560000-0000-0000-0000-000000000006', 'other',                 'Other',                          9000, 'active', NULL, 1);

-- System rows are immutable.
CREATE OR REPLACE FUNCTION public.supporting_categories_system_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN
  IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') AND OLD.org_id IS NULL THEN
    RAISE EXCEPTION 'System supporting-file categories are immutable' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER supporting_file_categories_system_immutable
  BEFORE UPDATE OR DELETE ON public.supporting_file_categories
  FOR EACH ROW EXECUTE FUNCTION public.supporting_categories_system_immutable();

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Category command receipts (catalogue administration)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE public.supporting_category_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command IN ('supersede', 'retire')),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  category_id uuid NOT NULL REFERENCES public.supporting_file_categories(id) ON DELETE RESTRICT,
  result_revision bigint NOT NULL CHECK (result_revision >= 1),
  result_code text NOT NULL CHECK (result_code = 'ok'),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.supporting_category_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supporting_category_command_receipts FORCE ROW LEVEL SECURITY;

-- Decisions are append-only.
CREATE OR REPLACE FUNCTION public.supporting_category_receipts_prevent_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN RAISE EXCEPTION 'Supporting-category command receipts are append-only'; END $$;
CREATE TRIGGER supporting_category_command_receipts_no_mutation
  BEFORE UPDATE OR DELETE ON public.supporting_category_command_receipts
  FOR EACH ROW EXECUTE FUNCTION public.supporting_category_receipts_prevent_mutation();

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Document ← category assignment column + trigger
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS supporting_category_id uuid
    REFERENCES public.supporting_file_categories(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS supporting_category_revision bigint NOT NULL DEFAULT 1;

-- Backfill existing supporting documents to matching system category or deterministic Other fallback; proceedings remain NULL
UPDATE public.documents d
SET supporting_category_id = coalesce(
  (
    SELECT c.id FROM public.supporting_file_categories c
    WHERE c.org_id IS NULL AND c.lifecycle = 'active'
      AND (c.category_key = d.document_category OR lower(c.label) = lower(d.document_category))
    LIMIT 1
  ),
  '01560000-0000-0000-0000-000000000006'::uuid
)
WHERE d.document_class = 'supporting' AND d.supporting_category_id IS NULL;

-- Database-boundary enforcement: a supporting document may reference only a
-- system category or a category from its own org. A proceeding document must
-- never carry a supporting category. New or unassigned supporting documents
-- default to deterministic Other fallback.
CREATE OR REPLACE FUNCTION public.documents_enforce_supporting_category()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE v_cat public.supporting_file_categories%ROWTYPE;
BEGIN
  IF NEW.document_class = 'supporting' THEN
    IF NEW.supporting_category_id IS NULL THEN
      NEW.supporting_category_id := '01560000-0000-0000-0000-000000000006'::uuid;
    END IF;
  ELSIF NEW.document_class = 'proceeding' THEN
    IF NEW.supporting_category_id IS NOT NULL THEN
      RAISE EXCEPTION 'Only supporting documents can carry a supporting category'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.supporting_category_id IS NOT NULL THEN
    IF NEW.document_class IS DISTINCT FROM 'supporting' THEN
      RAISE EXCEPTION 'Only supporting documents can carry a supporting category'
        USING ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v_cat FROM public.supporting_file_categories
      WHERE id = NEW.supporting_category_id;
    IF v_cat.id IS NULL THEN
      RAISE EXCEPTION 'Supporting category not found'
        USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF v_cat.org_id IS NOT NULL AND v_cat.org_id <> NEW.org_id THEN
      RAISE EXCEPTION 'Supporting category belongs to a different organisation'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_supporting_category_integrity
  BEFORE INSERT OR UPDATE ON public.documents
  FOR EACH ROW EXECUTE FUNCTION public.documents_enforce_supporting_category();

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Document-category change decisions (audit trail)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE public.document_supporting_category_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command = 'change_category'),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  document_id uuid NOT NULL REFERENCES public.documents(id) ON DELETE RESTRICT,
  result_revision bigint NOT NULL CHECK (result_revision >= 1),
  result_code text NOT NULL CHECK (result_code = 'ok'),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.document_supporting_category_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_supporting_category_command_receipts FORCE ROW LEVEL SECURITY;

CREATE TABLE public.document_supporting_category_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  document_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  assigned_category_id uuid REFERENCES public.supporting_file_categories(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL REFERENCES public.document_supporting_category_command_receipts(idempotency_key) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_supporting_category_decisions_org_matter_fkey
    FOREIGN KEY (org_id, matter_id) REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_supporting_category_decisions_org_document_fkey
    FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE RESTRICT
);
ALTER TABLE public.document_supporting_category_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_supporting_category_decisions FORCE ROW LEVEL SECURITY;

-- Decision lineage trigger: document must belong to active matter and client
CREATE OR REPLACE FUNCTION public.enforce_document_supporting_category_decision()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.documents AS doc
    JOIN public.matters AS matter ON matter.id = doc.matter_id AND matter.org_id = doc.org_id
    JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
    WHERE doc.id = NEW.document_id
      AND doc.org_id = NEW.org_id
      AND doc.matter_id = NEW.matter_id
      AND doc.document_class = 'supporting'
      AND doc.record_state = 'active' AND doc.deleted_at IS NULL
      AND matter.record_state = 'active' AND matter.deleted_at IS NULL
      AND client.record_state = 'active' AND client.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Document category decision lineage mismatch or inactive document/matter/client' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_supporting_category_decisions_enforce_lineage
  BEFORE INSERT ON public.document_supporting_category_decisions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_document_supporting_category_decision();

-- Append-only decisions.
CREATE OR REPLACE FUNCTION public.doc_category_decisions_prevent_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN RAISE EXCEPTION 'Document-category decisions are append-only'; END $$;
CREATE TRIGGER document_supporting_category_decisions_no_mutation
  BEFORE UPDATE OR DELETE ON public.document_supporting_category_decisions
  FOR EACH ROW EXECUTE FUNCTION public.doc_category_decisions_prevent_mutation();

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Evidence associations
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE public.document_evidence_associations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  matter_id uuid NOT NULL,
  supporting_document_id uuid NOT NULL,
  proceeding_document_id uuid NOT NULL,
  kind public.document_evidence_association_kind NOT NULL,
  concise_note text CHECK (
    concise_note IS NULL
    OR (btrim(concise_note) = concise_note
        AND char_length(concise_note) BETWEEN 1 AND 200
        AND concise_note !~ '[[:cntrl:]]')
  ),
  record_state text NOT NULL CHECK (record_state IN ('active', 'archived')),
  revision bigint NOT NULL DEFAULT 1 CHECK (revision >= 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT now(),
  archived_at timestamptz,
  archived_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  archive_reason text CHECK (
    archive_reason IS NULL
    OR (btrim(archive_reason) = archive_reason
        AND char_length(archive_reason) BETWEEN 1 AND 500
        AND archive_reason !~ '[[:cntrl:]]')
  ),
  CONSTRAINT document_evidence_associations_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_evidence_associations_matter_org_fkey
    FOREIGN KEY (org_id, matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_evidence_associations_supporting_org_fkey
    FOREIGN KEY (org_id, supporting_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_evidence_associations_proceeding_org_fkey
    FOREIGN KEY (org_id, proceeding_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_evidence_associations_archive_shape CHECK (
    (record_state = 'active' AND archived_at IS NULL AND archived_by IS NULL AND archive_reason IS NULL)
    OR (record_state = 'archived' AND archived_at IS NOT NULL AND archived_by IS NOT NULL
        AND archive_reason IS NOT NULL)
  )
);

CREATE UNIQUE INDEX document_evidence_associations_active_uniq
  ON public.document_evidence_associations(org_id, matter_id, supporting_document_id, proceeding_document_id, kind)
  WHERE record_state = 'active';

CREATE INDEX document_evidence_associations_org_supp_idx
  ON public.document_evidence_associations(org_id, matter_id, supporting_document_id);

CREATE INDEX document_evidence_associations_org_proc_idx
  ON public.document_evidence_associations(org_id, matter_id, proceeding_document_id);

CREATE OR REPLACE FUNCTION public.enforce_document_evidence_association()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE
  v_proc public.documents%ROWTYPE;
  v_supp public.documents%ROWTYPE;
  v_matter public.matters%ROWTYPE;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id <> OLD.id OR NEW.org_id <> OLD.org_id OR NEW.matter_id <> OLD.matter_id
       OR NEW.supporting_document_id <> OLD.supporting_document_id
       OR NEW.proceeding_document_id <> OLD.proceeding_document_id
       OR NEW.kind <> OLD.kind OR NEW.created_by <> OLD.created_by
       OR NEW.created_at <> OLD.created_at THEN
      RAISE EXCEPTION 'Evidence association identity is immutable' USING ERRCODE = '23514';
    END IF;
    IF OLD.record_state = 'archived' THEN
      RAISE EXCEPTION 'Cannot modify an archived association' USING ERRCODE = '23514';
    END IF;
    NEW.revision := OLD.revision + 1;
    NEW.updated_at := now();
  END IF;

  -- Active same-matter and client lineage check
  SELECT matter.* INTO v_matter FROM public.matters AS matter
  JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = NEW.matter_id AND matter.org_id = NEW.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL;
  IF v_matter.id IS NULL THEN
    RAISE EXCEPTION 'Association matter or client is not active' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_supp FROM public.documents
    WHERE id = NEW.supporting_document_id AND org_id = NEW.org_id AND matter_id = NEW.matter_id;
  SELECT * INTO v_proc FROM public.documents
    WHERE id = NEW.proceeding_document_id AND org_id = NEW.org_id AND matter_id = NEW.matter_id;
  IF v_supp.id IS NULL OR v_proc.id IS NULL THEN
    RAISE EXCEPTION 'Association endpoint lineage mismatch' USING ERRCODE = '23514';
  END IF;
  IF v_supp.document_class IS DISTINCT FROM 'supporting' THEN
    RAISE EXCEPTION 'Supporting endpoint must be a supporting document' USING ERRCODE = '23514';
  END IF;
  IF v_proc.document_class IS DISTINCT FROM 'proceeding' THEN
    RAISE EXCEPTION 'Proceeding endpoint must be a proceeding document' USING ERRCODE = '23514';
  END IF;

  IF NEW.record_state = 'active' THEN
    IF v_supp.record_state <> 'active' OR v_supp.deleted_at IS NOT NULL
       OR v_proc.record_state <> 'active' OR v_proc.deleted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Association endpoints must be active' USING ERRCODE = '23514';
    END IF;
  END IF;

  RETURN NEW;
END $$;
CREATE TRIGGER document_evidence_associations_enforce_contract
  BEFORE INSERT OR UPDATE ON public.document_evidence_associations
  FOR EACH ROW EXECUTE FUNCTION public.enforce_document_evidence_association();

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Association command receipts + decisions
-- ═══════════════════════════════════════════════════════════════════════════
CREATE TABLE public.document_evidence_association_command_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  idempotency_key uuid NOT NULL UNIQUE,
  command text NOT NULL CHECK (command IN ('activate', 'archive')),
  request_fingerprint text NOT NULL CHECK (request_fingerprint ~ '^[0-9a-f]{64}$'),
  association_id uuid NOT NULL,
  result_revision bigint NOT NULL CHECK (result_revision >= 1),
  result_code text NOT NULL CHECK (result_code = 'ok'),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_evidence_association_command_receipts_assoc_org_fkey
    FOREIGN KEY (org_id, association_id)
    REFERENCES public.document_evidence_associations(org_id, id) ON DELETE RESTRICT
);
ALTER TABLE public.document_evidence_association_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_evidence_association_command_receipts FORCE ROW LEVEL SECURITY;

CREATE TABLE public.document_evidence_association_decisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
  org_id uuid NOT NULL,
  matter_id uuid NOT NULL,
  supporting_document_id uuid NOT NULL,
  proceeding_document_id uuid NOT NULL,
  association_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  decision_type text NOT NULL CHECK (decision_type IN ('activate', 'archive')),
  reason text CHECK (
    reason IS NULL OR (btrim(reason) = reason AND char_length(reason) BETWEEN 1 AND 500 AND reason !~ '[[:cntrl:]]')
  ),
  idempotency_key uuid NOT NULL REFERENCES public.document_evidence_association_command_receipts(idempotency_key) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_evidence_association_decisions_assoc_org_fkey
    FOREIGN KEY (org_id, association_id)
    REFERENCES public.document_evidence_associations(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_evidence_association_decisions_matter_org_fkey
    FOREIGN KEY (org_id, matter_id)
    REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_evidence_association_decisions_supporting_org_fkey
    FOREIGN KEY (org_id, supporting_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_evidence_association_decisions_proceeding_org_fkey
    FOREIGN KEY (org_id, proceeding_document_id)
    REFERENCES public.documents(org_id, id) ON DELETE RESTRICT
);
ALTER TABLE public.document_evidence_association_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.document_evidence_association_decisions FORCE ROW LEVEL SECURITY;

-- Decision lineage trigger: decision org/matter/document fields must agree
-- with the association they reference, and matter/client must be active.
CREATE OR REPLACE FUNCTION public.enforce_evidence_association_decision()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.document_evidence_associations AS assoc
    JOIN public.matters AS matter ON matter.id = assoc.matter_id AND matter.org_id = assoc.org_id
    JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
    WHERE assoc.id = NEW.association_id
      AND assoc.org_id = NEW.org_id
      AND assoc.matter_id = NEW.matter_id
      AND assoc.supporting_document_id = NEW.supporting_document_id
      AND assoc.proceeding_document_id = NEW.proceeding_document_id
      AND matter.record_state = 'active' AND matter.deleted_at IS NULL
      AND client.record_state = 'active' AND client.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Evidence association decision lineage mismatch or inactive matter/client' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER document_evidence_association_decisions_enforce_lineage
  BEFORE INSERT ON public.document_evidence_association_decisions
  FOR EACH ROW EXECUTE FUNCTION public.enforce_evidence_association_decision();

-- Append-only decisions.
CREATE OR REPLACE FUNCTION public.evidence_association_decisions_prevent_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog AS $$
BEGIN RAISE EXCEPTION 'Evidence association decisions are append-only'; END $$;
CREATE TRIGGER document_evidence_association_decisions_no_mutation
  BEFORE UPDATE OR DELETE ON public.document_evidence_association_decisions
  FOR EACH ROW EXECUTE FUNCTION public.evidence_association_decisions_prevent_mutation();

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. Activity event definitions for Matter Files
-- ═══════════════════════════════════════════════════════════════════════════
INSERT INTO public.activity_event_definitions(
  event_type, event_version, category, subject_types,
  default_visibility, metadata_contract, renderer_key
) VALUES
  ('document.category_changed', 1, 'record', ARRAY['document'], 'matter',
   '{"change":"code"}', 'document.category_changed'),
  ('document.evidence_association_changed', 1, 'relationship', ARRAY['document'], 'matter',
   '{"association_action":"code"}', 'document.evidence_association_changed');

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. Projection functions (SECURITY DEFINER, narrowly granted)
-- ═══════════════════════════════════════════════════════════════════════════

-- 9a. Active catalogue browser: returns active system + org categories.
CREATE OR REPLACE FUNCTION public.get_active_supporting_categories(p_org_id uuid)
RETURNS TABLE(id uuid, category_key text, label text, sort_order smallint)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = pg_catalog, public AS $$
DECLARE
  v_membership record;
  v_is_owner boolean := false;
BEGIN
  IF p_org_id IS NULL THEN RETURN; END IF;
  SELECT m.org_id, m.role, m.membership_id INTO v_membership
  FROM public.current_active_tenant_membership() m WHERE m.org_id = p_org_id;
  IF v_membership.org_id IS NULL THEN RETURN; END IF;
  SELECT (o.owner_membership_id = v_membership.membership_id) INTO v_is_owner
  FROM public.organisations o WHERE o.id = v_membership.org_id;
  IF NOT ('document.view' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false),
    'active'::public.organisation_membership_state
  ))) THEN RETURN; END IF;
  RETURN QUERY
  SELECT c.id, c.category_key, c.label, c.sort_order
  FROM public.supporting_file_categories c
  WHERE c.lifecycle = 'active'
    AND (c.org_id IS NULL OR c.org_id = p_org_id)
  ORDER BY c.sort_order, c.label;
END $$;

-- 9b. Selected-category reader: returns a document's current category even if
-- retired, fail-closed by active tenant + document lineage.
CREATE OR REPLACE FUNCTION public.get_document_supporting_category(p_document_id uuid)
RETURNS TABLE(id uuid, category_key text, label text, sort_order smallint, lifecycle text)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = pg_catalog, public AS $$
DECLARE
  v_membership record;
  v_is_owner boolean := false;
  v_doc record;
BEGIN
  IF p_document_id IS NULL THEN RETURN; END IF;
  SELECT d.org_id, d.supporting_category_id, d.matter_id, d.record_state, d.deleted_at
  INTO v_doc
  FROM public.documents d WHERE d.id = p_document_id;
  IF v_doc.org_id IS NULL OR v_doc.supporting_category_id IS NULL THEN RETURN; END IF;
  IF v_doc.record_state <> 'active' OR v_doc.deleted_at IS NOT NULL THEN RETURN; END IF;

  SELECT m.org_id, m.role, m.membership_id INTO v_membership
  FROM public.current_active_tenant_membership() m WHERE m.org_id = v_doc.org_id;
  IF v_membership.org_id IS NULL THEN RETURN; END IF;
  SELECT (o.owner_membership_id = v_membership.membership_id) INTO v_is_owner
  FROM public.organisations o WHERE o.id = v_membership.org_id;
  IF NOT ('document.view' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false),
    'active'::public.organisation_membership_state
  ))) THEN RETURN; END IF;

  -- Validate active matter and client lineage
  IF NOT EXISTS (
    SELECT 1 FROM public.matters m
    JOIN public.clients c ON c.id = m.client_id AND c.org_id = m.org_id
    WHERE m.id = v_doc.matter_id AND m.org_id = v_doc.org_id
      AND m.record_state = 'active' AND m.deleted_at IS NULL
      AND c.record_state = 'active' AND c.deleted_at IS NULL
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT c.id, c.category_key, c.label, c.sort_order, c.lifecycle
  FROM public.supporting_file_categories c WHERE c.id = v_doc.supporting_category_id;
END $$;

-- 9c. Active evidence associations for a document. Hides trashed/closed/moved endpoints.
CREATE OR REPLACE FUNCTION public.get_active_evidence_associations(
  p_org_id uuid, p_matter_id uuid, p_document_id uuid
)
RETURNS TABLE(
  id uuid, supporting_document_id uuid, proceeding_document_id uuid,
  kind public.document_evidence_association_kind, concise_note text,
  revision bigint, created_at timestamptz, created_by uuid
)
LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = pg_catalog, public AS $$
DECLARE
  v_membership record;
  v_is_owner boolean := false;
BEGIN
  IF p_org_id IS NULL OR p_matter_id IS NULL OR p_document_id IS NULL THEN RETURN; END IF;
  SELECT m.org_id, m.role, m.membership_id INTO v_membership
  FROM public.current_active_tenant_membership() m WHERE m.org_id = p_org_id;
  IF v_membership.org_id IS NULL THEN RETURN; END IF;
  SELECT (o.owner_membership_id = v_membership.membership_id) INTO v_is_owner
  FROM public.organisations o WHERE o.id = v_membership.org_id;
  IF NOT ('document.view' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false),
    'active'::public.organisation_membership_state
  ))) THEN RETURN; END IF;

  -- Validate active matter and client lineage; hide if closed or trashed
  IF NOT EXISTS (
    SELECT 1 FROM public.matters m
    JOIN public.clients c ON c.id = m.client_id AND c.org_id = m.org_id
    WHERE m.id = p_matter_id AND m.org_id = p_org_id
      AND m.record_state = 'active' AND m.deleted_at IS NULL
      AND m.status <> 'closed' AND m.work_state <> 'closed'
      AND c.record_state = 'active' AND c.deleted_at IS NULL
  ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT a.id, a.supporting_document_id, a.proceeding_document_id,
    a.kind, a.concise_note, a.revision, a.created_at, a.created_by
  FROM public.document_evidence_associations a
  JOIN public.documents supp ON supp.id = a.supporting_document_id
    AND supp.org_id = a.org_id AND supp.matter_id = a.matter_id
  JOIN public.documents proc ON proc.id = a.proceeding_document_id
    AND proc.org_id = a.org_id AND proc.matter_id = a.matter_id
  WHERE a.org_id = p_org_id AND a.matter_id = p_matter_id
    AND a.record_state = 'active'
    AND supp.record_state = 'active' AND supp.deleted_at IS NULL
    AND proc.record_state = 'active' AND proc.deleted_at IS NULL
    AND (a.supporting_document_id = p_document_id OR a.proceeding_document_id = p_document_id);
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. Commands
-- ═══════════════════════════════════════════════════════════════════════════

-- 10a. Catalogue administration: supersede an org category (Owner/Admin only).
-- CAS on expected_revision; immutable history; deterministic replay/conflict.
-- No outbox/Activity per user clarification.
CREATE OR REPLACE FUNCTION public.supersede_supporting_file_category(
  p_org_id uuid,
  p_category_key text,
  p_new_label text,
  p_new_sort_order smallint,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, category_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership public.organisation_memberships%ROWTYPE;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_is_owner boolean := false;
  v_fingerprint text;
  v_receipt public.supporting_category_command_receipts%ROWTYPE;
  v_cat public.supporting_file_categories%ROWTYPE;
  v_new_id uuid;
  v_new_rev bigint;
BEGIN
  IF v_actor IS NULL OR p_org_id IS NULL
     OR p_category_key IS NULL OR char_length(p_category_key) NOT BETWEEN 1 AND 50 OR p_category_key ~ '[[:cntrl:]]'
     OR p_new_label IS NULL OR char_length(p_new_label) NOT BETWEEN 1 AND 100 OR p_new_label ~ '[[:cntrl:]]'
     OR p_new_sort_order IS NULL OR p_expected_revision IS NULL OR p_expected_revision < 0
     OR p_idempotency_key IS NULL THEN
    RETURN QUERY SELECT 'invalid_request', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 156)
  );
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 OR v_membership.org_id <> p_org_id THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation WHERE organisation.id = v_membership.org_id;
  IF NOT (coalesce(v_is_owner, false) OR v_membership.role = 'admin') THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','supersede','org_id',p_org_id,'category_key',p_category_key,
    'new_label',p_new_label,'new_sort_order',p_new_sort_order,
    'expected_revision',p_expected_revision
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.supporting_category_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> p_org_id
       OR v_receipt.command <> 'supersede' OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict', NULL::uuid, NULL::bigint, false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code, v_receipt.category_id,
        v_receipt.result_revision, true;
    END IF;
    RETURN;
  END IF;

  -- Lock and find the active org category.
  SELECT * INTO v_cat FROM public.supporting_file_categories
  WHERE org_id = p_org_id AND category_key = p_category_key AND lifecycle = 'active'
  FOR UPDATE;

  -- System categories cannot be superseded through this function.
  IF EXISTS (SELECT 1 FROM public.supporting_file_categories
    WHERE org_id IS NULL AND category_key = p_category_key AND lifecycle = 'active') THEN
    RETURN QUERY SELECT 'system_immutable', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  IF v_cat.id IS NOT NULL AND v_cat.category_version <> p_expected_revision THEN
    RETURN QUERY SELECT 'conflict', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_cat.id IS NULL AND p_expected_revision <> 0 THEN
    RETURN QUERY SELECT 'conflict', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  v_new_rev := p_expected_revision + 1;
  IF v_cat.id IS NOT NULL THEN
    UPDATE public.supporting_file_categories SET lifecycle = 'retired'
    WHERE id = v_cat.id;
  END IF;

  INSERT INTO public.supporting_file_categories (
    category_key, label, sort_order, lifecycle, org_id, category_version, created_by
  ) VALUES (
    p_category_key, p_new_label, p_new_sort_order, 'active', p_org_id, v_new_rev, v_actor
  ) RETURNING id INTO v_new_id;

  INSERT INTO public.supporting_category_command_receipts (
    org_id, actor_user_id, idempotency_key, command, request_fingerprint,
    category_id, result_revision, result_code
  ) VALUES (
    p_org_id, v_actor, p_idempotency_key, 'supersede', v_fingerprint,
    v_new_id, v_new_rev, 'ok'
  );

  RETURN QUERY SELECT 'ok', v_new_id, v_new_rev, false;
END $$;

-- 10b. Change document supporting category (Associate/Admin/Owner).
CREATE OR REPLACE FUNCTION public.change_document_supporting_category(
  p_document_id uuid,
  p_matter_id uuid,
  p_new_category_id uuid,
  p_expected_revision bigint,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership public.organisation_memberships%ROWTYPE;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_is_owner boolean := false;
  v_fingerprint text;
  v_receipt public.document_supporting_category_command_receipts%ROWTYPE;
  v_doc public.documents%ROWTYPE;
  v_matter public.matters%ROWTYPE;
  v_cat public.supporting_file_categories%ROWTYPE;
  v_new_rev bigint;
BEGIN
  IF v_actor IS NULL OR p_document_id IS NULL OR p_matter_id IS NULL
     OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR p_idempotency_key IS NULL THEN
    RETURN QUERY SELECT 'invalid_request', NULL::bigint, false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 156)
  );
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed', NULL::bigint, false; RETURN;
  END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation WHERE organisation.id = v_membership.org_id;
  IF NOT ('document.metadata.decide' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false), v_membership.state
  ))) THEN
    RETURN QUERY SELECT 'not_allowed', NULL::bigint, false; RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','change_category','document_id',p_document_id,
    'new_category_id',p_new_category_id,'expected_revision',p_expected_revision
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.document_supporting_category_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_membership.org_id
       OR v_receipt.command <> 'change_category' OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict', NULL::bigint, false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code, v_receipt.result_revision, true;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO v_doc FROM public.documents AS document
  WHERE document.id = p_document_id AND document.org_id = v_membership.org_id
    AND document.matter_id = p_matter_id
  FOR UPDATE;
  IF v_doc.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::bigint, false; RETURN;
  END IF;
  IF v_doc.record_state <> 'active' OR v_doc.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::bigint, false; RETURN;
  END IF;
  IF v_doc.document_class IS DISTINCT FROM 'supporting' THEN
    RETURN QUERY SELECT 'invalid_endpoint_class', NULL::bigint, false; RETURN;
  END IF;
  IF v_doc.supporting_category_revision <> p_expected_revision THEN
    RETURN QUERY SELECT 'conflict', NULL::bigint, false; RETURN;
  END IF;

  SELECT matter.* INTO v_matter FROM public.matters AS matter
  JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = p_matter_id AND matter.org_id = v_membership.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::bigint, false; RETURN;
  END IF;
  IF v_matter.work_state = 'closed' THEN
    RETURN QUERY SELECT 'matter_read_only', NULL::bigint, false; RETURN;
  END IF;

  IF p_new_category_id IS NULL THEN
    RETURN QUERY SELECT 'invalid_request', NULL::bigint, false; RETURN;
  END IF;

  SELECT * INTO v_cat FROM public.supporting_file_categories WHERE id = p_new_category_id;
  IF v_cat.id IS NULL OR v_cat.lifecycle <> 'active'
     OR (v_cat.org_id IS NOT NULL AND v_cat.org_id <> v_membership.org_id) THEN
    RETURN QUERY SELECT 'invalid_request', NULL::bigint, false; RETURN;
  END IF;

  v_new_rev := p_expected_revision + 1;
  UPDATE public.documents SET
    supporting_category_id = p_new_category_id,
    supporting_category_revision = v_new_rev
  WHERE id = p_document_id;

  INSERT INTO public.document_supporting_category_command_receipts (
    org_id, actor_user_id, idempotency_key, command, request_fingerprint,
    document_id, result_revision, result_code
  ) VALUES (
    v_membership.org_id, v_actor, p_idempotency_key, 'change_category', v_fingerprint,
    p_document_id, v_new_rev, 'ok'
  );
  INSERT INTO public.document_supporting_category_decisions (
    org_id, matter_id, document_id, actor_user_id,
    assigned_category_id, idempotency_key
  ) VALUES (
    v_membership.org_id, p_matter_id, p_document_id, v_actor,
    p_new_category_id, p_idempotency_key
  );
  PERFORM public.append_activity_event(
    v_membership.org_id, 'document.category_changed', 1::smallint, 'user', v_actor, 'Member',
    'document', p_document_id, v_matter.client_id, p_matter_id, 'Document',
    'Document category changed',
    jsonb_build_object('change', 'category_assigned'),
    'document', p_document_id, NULL, p_idempotency_key, NULL,
    'document.category.' || p_idempotency_key::text, now()
  );
  INSERT INTO public.outbox_events (
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    v_membership.org_id, 'document', p_document_id,
    'document.supporting_category_changed.v1',
    jsonb_build_object(
      'document_id', p_document_id::text,
      'matter_id', p_matter_id::text,
      'category_id', p_new_category_id::text,
      'revision', v_new_rev::text
    ),
    p_idempotency_key
  );
  RETURN QUERY SELECT 'ok', v_new_rev, false;
END $$;

-- 10c. Activate evidence association (Associate/Admin/Owner).
CREATE OR REPLACE FUNCTION public.activate_document_evidence_association(
  p_matter_id uuid,
  p_supporting_document_id uuid,
  p_proceeding_document_id uuid,
  p_association_kind public.document_evidence_association_kind,
  p_concise_note text,
  p_expected_supp_revision bigint,
  p_expected_proc_revision bigint,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, association_id uuid, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership public.organisation_memberships%ROWTYPE;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_is_owner boolean := false;
  v_note text := nullif(btrim(p_concise_note), '');
  v_fingerprint text;
  v_receipt public.document_evidence_association_command_receipts%ROWTYPE;
  v_matter public.matters%ROWTYPE;
  v_supp public.documents%ROWTYPE;
  v_proc public.documents%ROWTYPE;
  v_assoc public.document_evidence_associations%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_matter_id IS NULL
     OR p_supporting_document_id IS NULL OR p_proceeding_document_id IS NULL
     OR p_association_kind IS NULL OR p_idempotency_key IS NULL
     OR p_expected_supp_revision IS NULL OR p_expected_supp_revision < 1
     OR p_expected_proc_revision IS NULL OR p_expected_proc_revision < 1 THEN
    RETURN QUERY SELECT 'invalid_request', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF p_supporting_document_id = p_proceeding_document_id THEN
    RETURN QUERY SELECT 'self_association', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_note IS NOT NULL AND (char_length(v_note) > 200 OR v_note ~ '[[:cntrl:]]') THEN
    RETURN QUERY SELECT 'invalid_request', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 156)
  );
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation WHERE organisation.id = v_membership.org_id;
  IF NOT ('document.metadata.decide' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false), v_membership.state
  ))) THEN
    RETURN QUERY SELECT 'not_allowed', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','activate','matter_id',p_matter_id,
    'supporting_document_id',p_supporting_document_id,
    'proceeding_document_id',p_proceeding_document_id,
    'association_kind',p_association_kind::text,
    'note',coalesce(v_note,''),
    'supp_rev',p_expected_supp_revision,'proc_rev',p_expected_proc_revision
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.document_evidence_association_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_membership.org_id
       OR v_receipt.command <> 'activate' OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict', NULL::uuid, NULL::bigint, false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code, v_receipt.association_id,
        v_receipt.result_revision, true;
    END IF;
    RETURN;
  END IF;

  -- Matter context check.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_membership.org_id::text || ':' || p_matter_id::text, 156)
  );
  SELECT matter.* INTO v_matter FROM public.matters AS matter
  JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = p_matter_id AND matter.org_id = v_membership.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL
  FOR UPDATE OF matter, client;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_matter.work_state = 'closed' THEN
    RETURN QUERY SELECT 'matter_read_only', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  -- Endpoint checks: lock, verify org+matter lineage, class, state, revision.
  PERFORM 1 FROM public.documents AS document
  WHERE document.id IN (p_supporting_document_id, p_proceeding_document_id)
  ORDER BY document.id FOR UPDATE;
  SELECT * INTO v_supp FROM public.documents AS document
  WHERE document.id = p_supporting_document_id
    AND document.org_id = v_membership.org_id AND document.matter_id = p_matter_id;
  SELECT * INTO v_proc FROM public.documents AS document
  WHERE document.id = p_proceeding_document_id
    AND document.org_id = v_membership.org_id AND document.matter_id = p_matter_id;
  IF v_supp.id IS NULL OR v_proc.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_supp.record_state <> 'active' OR v_supp.deleted_at IS NOT NULL
     OR v_proc.record_state <> 'active' OR v_proc.deleted_at IS NOT NULL THEN
    RETURN QUERY SELECT 'endpoint_unavailable', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_supp.document_class IS DISTINCT FROM 'supporting' THEN
    RETURN QUERY SELECT 'invalid_endpoint_class', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_proc.document_class IS DISTINCT FROM 'proceeding' THEN
    RETURN QUERY SELECT 'invalid_endpoint_class', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;
  IF v_supp.lifecycle_revision <> p_expected_supp_revision
     OR v_proc.lifecycle_revision <> p_expected_proc_revision THEN
    RETURN QUERY SELECT 'conflict', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  -- Advisory lock on active pair+kind to serialize concurrent activation attempts cleanly
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      v_membership.org_id::text || ':' || p_matter_id::text || ':' ||
      p_supporting_document_id::text || ':' || p_proceeding_document_id::text || ':' ||
      p_association_kind::text, 156
    )
  );
  IF EXISTS (
    SELECT 1 FROM public.document_evidence_associations
    WHERE org_id = v_membership.org_id AND matter_id = p_matter_id
      AND supporting_document_id = p_supporting_document_id
      AND proceeding_document_id = p_proceeding_document_id
      AND kind = p_association_kind
      AND record_state = 'active'
  ) THEN
    RETURN QUERY SELECT 'duplicate_active', NULL::uuid, NULL::bigint, false; RETURN;
  END IF;

  BEGIN
    INSERT INTO public.document_evidence_associations (
      org_id, matter_id, supporting_document_id, proceeding_document_id,
      kind, concise_note, record_state, created_by
    ) VALUES (
      v_membership.org_id, p_matter_id, p_supporting_document_id, p_proceeding_document_id,
      p_association_kind, v_note, 'active', v_actor
    ) RETURNING * INTO v_assoc;
  EXCEPTION
    WHEN unique_violation THEN
      RETURN QUERY SELECT 'duplicate_active', NULL::uuid, NULL::bigint, false; RETURN;
  END;

  INSERT INTO public.document_evidence_association_command_receipts (
    org_id, actor_user_id, idempotency_key, command, request_fingerprint,
    association_id, result_revision, result_code
  ) VALUES (
    v_membership.org_id, v_actor, p_idempotency_key, 'activate', v_fingerprint,
    v_assoc.id, v_assoc.revision, 'ok'
  );
  INSERT INTO public.document_evidence_association_decisions (
    org_id, matter_id, supporting_document_id, proceeding_document_id,
    association_id, actor_user_id, decision_type, reason, idempotency_key
  ) VALUES (
    v_membership.org_id, p_matter_id, p_supporting_document_id, p_proceeding_document_id,
    v_assoc.id, v_actor, 'activate', v_note, p_idempotency_key
  );
  PERFORM public.append_activity_event(
    v_membership.org_id, 'document.evidence_association_changed', 1::smallint,
    'user', v_actor, 'Member',
    'document', p_supporting_document_id, v_matter.client_id, p_matter_id, 'Document',
    'Evidence association activated',
    jsonb_build_object('association_action', 'activate.' || p_association_kind::text),
    'document', p_proceeding_document_id, NULL, p_idempotency_key, NULL,
    'evidence.activate.' || p_idempotency_key::text, now()
  );
  INSERT INTO public.outbox_events (
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    v_membership.org_id, 'document', p_supporting_document_id,
    'document.evidence_association_changed.v1',
    jsonb_build_object(
      'document_id', p_supporting_document_id::text,
      'matter_id', p_matter_id::text,
      'association_id', v_assoc.id::text,
      'revision', v_assoc.revision::text
    ),
    p_idempotency_key
  );
  RETURN QUERY SELECT 'ok', v_assoc.id, v_assoc.revision, false;
END $$;

-- 10d. Archive evidence association (Associate/Admin/Owner).
CREATE OR REPLACE FUNCTION public.archive_document_evidence_association(
  p_matter_id uuid,
  p_association_id uuid,
  p_expected_revision bigint,
  p_reason text,
  p_idempotency_key uuid
)
RETURNS TABLE(code text, revision bigint, replayed boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_membership public.organisation_memberships%ROWTYPE;
  v_current_count integer := 0;
  v_active_count integer := 0;
  v_is_owner boolean := false;
  v_reason text := nullif(btrim(p_reason), '');
  v_fingerprint text;
  v_receipt public.document_evidence_association_command_receipts%ROWTYPE;
  v_assoc public.document_evidence_associations%ROWTYPE;
  v_matter public.matters%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_matter_id IS NULL OR p_association_id IS NULL
     OR p_expected_revision IS NULL OR p_expected_revision < 1
     OR p_idempotency_key IS NULL
     OR v_reason IS NULL OR char_length(v_reason) NOT BETWEEN 1 AND 500 OR v_reason ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid_request', NULL::bigint, false; RETURN;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_idempotency_key::text, 156)
  );
  FOR v_membership IN
    SELECT * FROM public.organisation_memberships AS membership
    WHERE membership.user_id = v_actor AND membership.state IN ('active', 'suspended')
    FOR UPDATE
  LOOP
    v_current_count := v_current_count + 1;
    IF v_membership.state = 'active' THEN v_active_count := v_active_count + 1; END IF;
  END LOOP;
  IF v_current_count <> 1 OR v_active_count <> 1 THEN
    RETURN QUERY SELECT 'not_allowed', NULL::bigint, false; RETURN;
  END IF;
  SELECT organisation.owner_membership_id = v_membership.id INTO v_is_owner
  FROM public.organisations AS organisation WHERE organisation.id = v_membership.org_id;
  IF NOT ('document.metadata.decide' = ANY(public.organisation_member_capabilities(
    v_membership.role, coalesce(v_is_owner, false), v_membership.state
  ))) THEN
    RETURN QUERY SELECT 'not_allowed', NULL::bigint, false; RETURN;
  END IF;

  v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
    'command','archive','association_id',p_association_id,
    'expected_revision',p_expected_revision,'reason',v_reason
  )::text,'utf8'),'sha256'),'hex');
  SELECT * INTO v_receipt FROM public.document_evidence_association_command_receipts AS receipt
  WHERE receipt.idempotency_key = p_idempotency_key;
  IF v_receipt.id IS NOT NULL THEN
    IF v_receipt.actor_user_id <> v_actor OR v_receipt.org_id <> v_membership.org_id
       OR v_receipt.command <> 'archive' OR v_receipt.request_fingerprint <> v_fingerprint THEN
      RETURN QUERY SELECT 'idempotency_conflict', NULL::bigint, false;
    ELSE
      RETURN QUERY SELECT v_receipt.result_code, v_receipt.result_revision, true;
    END IF;
    RETURN;
  END IF;

  SELECT * INTO v_assoc FROM public.document_evidence_associations AS assoc
  WHERE assoc.id = p_association_id AND assoc.org_id = v_membership.org_id
  FOR UPDATE;
  IF v_assoc.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::bigint, false; RETURN;
  END IF;
  IF v_assoc.record_state = 'archived' THEN
    RETURN QUERY SELECT 'already_archived', NULL::bigint, false; RETURN;
  END IF;
  IF v_assoc.revision <> p_expected_revision THEN
    RETURN QUERY SELECT 'conflict', NULL::bigint, false; RETURN;
  END IF;

  -- Validate matter context.
  SELECT matter.* INTO v_matter FROM public.matters AS matter
  JOIN public.clients AS client ON client.id = matter.client_id AND client.org_id = matter.org_id
  WHERE matter.id = v_assoc.matter_id AND matter.org_id = v_membership.org_id
    AND matter.record_state = 'active' AND matter.deleted_at IS NULL
    AND client.record_state = 'active' AND client.deleted_at IS NULL;
  IF v_matter.id IS NULL THEN
    RETURN QUERY SELECT 'context_unavailable', NULL::bigint, false; RETURN;
  END IF;
  IF v_matter.work_state = 'closed' THEN
    RETURN QUERY SELECT 'matter_read_only', NULL::bigint, false; RETURN;
  END IF;

  -- Check endpoint availability before UPDATE (so trashed endpoints return
  -- deterministic error code instead of trigger exception).
  IF NOT EXISTS (
    SELECT 1 FROM public.documents AS supp
    JOIN public.documents AS proc ON proc.id = v_assoc.proceeding_document_id
      AND proc.org_id = supp.org_id AND proc.matter_id = supp.matter_id
    WHERE supp.id = v_assoc.supporting_document_id
      AND supp.org_id = v_membership.org_id AND supp.matter_id = v_assoc.matter_id
      AND supp.record_state = 'active' AND supp.deleted_at IS NULL
      AND proc.record_state = 'active' AND proc.deleted_at IS NULL
  ) THEN
    RETURN QUERY SELECT 'endpoint_unavailable', NULL::bigint, false; RETURN;
  END IF;

  UPDATE public.document_evidence_associations SET
    record_state = 'archived',
    archived_at = now(), archived_by = v_actor,
    archive_reason = v_reason
  WHERE id = p_association_id
  RETURNING * INTO v_assoc;

  INSERT INTO public.document_evidence_association_command_receipts (
    org_id, actor_user_id, idempotency_key, command, request_fingerprint,
    association_id, result_revision, result_code
  ) VALUES (
    v_membership.org_id, v_actor, p_idempotency_key, 'archive', v_fingerprint,
    v_assoc.id, v_assoc.revision, 'ok'
  );
  INSERT INTO public.document_evidence_association_decisions (
    org_id, matter_id, supporting_document_id, proceeding_document_id,
    association_id, actor_user_id, decision_type, reason, idempotency_key
  ) VALUES (
    v_membership.org_id, v_assoc.matter_id, v_assoc.supporting_document_id,
    v_assoc.proceeding_document_id,
    v_assoc.id, v_actor, 'archive', v_reason, p_idempotency_key
  );
  PERFORM public.append_activity_event(
    v_membership.org_id, 'document.evidence_association_changed', 1::smallint,
    'user', v_actor, 'Member',
    'document', v_assoc.supporting_document_id, v_matter.client_id, v_assoc.matter_id, 'Document',
    'Evidence association archived',
    jsonb_build_object('association_action', 'archive.' || v_assoc.kind::text),
    'document', v_assoc.proceeding_document_id, NULL, p_idempotency_key, NULL,
    'evidence.archive.' || p_idempotency_key::text, now()
  );
  INSERT INTO public.outbox_events (
    org_id, aggregate_type, aggregate_id, event_kind, payload, idempotency_key
  ) VALUES (
    v_membership.org_id, 'document', v_assoc.supporting_document_id,
    'document.evidence_association_changed.v1',
    jsonb_build_object(
      'document_id', v_assoc.supporting_document_id::text,
      'matter_id', v_assoc.matter_id::text,
      'association_id', v_assoc.id::text,
      'revision', v_assoc.revision::text
    ),
    p_idempotency_key
  );
  RETURN QUERY SELECT 'ok', v_assoc.revision, false;
END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11. Outbox allowlist: surgical copy of 00088 + 2 new rows
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.document_lifecycle_outbox_envelope_is_safe(
  p_event_kind text,
  p_aggregate_type text,
  p_aggregate_id uuid,
  p_payload jsonb
) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, public AS $$
  WITH contract(event_kind, aggregate_type, identifier_key, expected_keys) AS (
    VALUES
      ('document.upload_reserved.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id','asset_id']::text[]),
      ('document.upload_validation_requested.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id','asset_id']::text[]),
      ('document.upload_duplicate.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id']::text[]),
      ('document.upload_failed.v1', 'document_upload', 'session_id', ARRAY['session_id','intake_id','error_code']::text[]),
      ('document.upload_expired.v1', 'document_upload', 'session_id', ARRAY['session_id']::text[]),
      ('document.intake_validated.v1', 'document', 'intake_id', ARRAY['intake_id','asset_id','result_code']::text[]),
      ('document.intake_validation_failed.v1', 'document', 'intake_id', ARRAY['intake_id','asset_id','result_code']::text[]),
      ('document.metadata_created.v1', 'document', 'document_id', ARRAY['document_id','matter_id']::text[]),
      ('document.processing_requested.v1', 'document', 'document_id', ARRAY['document_id','version_id','intake_id']::text[]),
      ('document.reprocess_requested.v1', 'document', 'document_id', ARRAY['document_id','version_id','scope']::text[]),
      ('intake.assigned.v1', 'document', 'intake_id', ARRAY['intake_id','document_id','document_version_id']::text[]),
      ('intake.discarded.v1', 'document', 'intake_id', ARRAY['intake_id','result_code']::text[]),
      ('trash.operation_created.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      ('trash.operation_restored.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      ('trash.search_reindex_requested.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      ('trash.schedule_reevaluation_requested.v1', 'trash_operation', 'operation_id', ARRAY['operation_id','root_resource_id','root_resource_type']::text[]),
      -- Exactly the two new Matter Files rows:
      ('document.supporting_category_changed.v1', 'document', 'document_id', ARRAY['document_id','matter_id','category_id','revision']::text[]),
      ('document.evidence_association_changed.v1', 'document', 'document_id', ARRAY['document_id','matter_id','association_id','revision']::text[])
  )
  SELECT coalesce((SELECT p_event_kind IS NOT NULL AND p_aggregate_type=c.aggregate_type
    AND p_aggregate_id IS NOT NULL AND jsonb_typeof(p_payload)='object'
    AND p_aggregate_id::text=p_payload->>c.identifier_key
    AND NOT EXISTS (SELECT 1 FROM jsonb_object_keys(p_payload) key WHERE NOT key=ANY(c.expected_keys))
    AND NOT EXISTS (SELECT 1 FROM unnest(c.expected_keys) key WHERE NOT p_payload?key
      OR jsonb_typeof(p_payload->key)<>'string' OR char_length(p_payload->>key) NOT BETWEEN 1 AND 128)
    AND NOT EXISTS (SELECT 1 FROM unnest(ARRAY['session_id','intake_id','asset_id','document_id','matter_id','version_id','document_version_id','operation_id','root_resource_id','category_id','association_id']::text[]) key
      WHERE p_payload?key AND p_payload->>key !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
    AND (NOT p_payload?'revision' OR p_payload->>'revision' ~ '^[1-9][0-9]{0,18}$')
    AND (NOT p_payload?'scope' OR p_payload->>'scope' IN ('extract','ocr','relationships','search_index','full'))
    AND (NOT p_payload?'root_resource_type' OR p_payload->>'root_resource_type' IN ('client','matter','document'))
    AND (NOT p_payload?'error_code' OR p_payload->>'error_code' IN ('upload_failed','invalid_pdf','malware_suspect','storage_missing','validation_failed','upload_rejected'))
    AND (NOT p_payload?'result_code' OR p_payload->>'result_code' IN ('ok','already_ready','not_available','invalid_pdf','encrypted_pdf','malware_suspect','storage_missing','validation_failed','discarded'))
    FROM contract c WHERE c.event_kind=p_event_kind),false)
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12. Revoke/Grant — all new tables and functions
-- ═══════════════════════════════════════════════════════════════════════════
REVOKE ALL ON TABLE
  public.supporting_file_categories,
  public.supporting_category_command_receipts,
  public.document_supporting_category_command_receipts,
  public.document_supporting_category_decisions,
  public.document_evidence_associations,
  public.document_evidence_association_command_receipts,
  public.document_evidence_association_decisions
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.supporting_categories_system_immutable(),
  public.supporting_category_receipts_prevent_mutation(),
  public.documents_enforce_supporting_category(),
  public.enforce_document_supporting_category_decision(),
  public.doc_category_decisions_prevent_mutation(),
  public.enforce_document_evidence_association(),
  public.enforce_evidence_association_decision(),
  public.evidence_association_decisions_prevent_mutation()
  FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION
  public.get_active_supporting_categories(uuid),
  public.get_document_supporting_category(uuid),
  public.get_active_evidence_associations(uuid, uuid, uuid),
  public.supersede_supporting_file_category(uuid, text, text, smallint, bigint, uuid),
  public.change_document_supporting_category(uuid, uuid, uuid, bigint, uuid),
  public.activate_document_evidence_association(uuid, uuid, uuid, public.document_evidence_association_kind, text, bigint, bigint, uuid),
  public.archive_document_evidence_association(uuid, uuid, bigint, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION
  public.get_active_supporting_categories(uuid),
  public.get_document_supporting_category(uuid),
  public.get_active_evidence_associations(uuid, uuid, uuid),
  public.supersede_supporting_file_category(uuid, text, text, smallint, bigint, uuid),
  public.change_document_supporting_category(uuid, uuid, uuid, bigint, uuid),
  public.activate_document_evidence_association(uuid, uuid, uuid, public.document_evidence_association_kind, text, bigint, bigint, uuid),
  public.archive_document_evidence_association(uuid, uuid, bigint, text, uuid)
  TO authenticated;

COMMIT;
