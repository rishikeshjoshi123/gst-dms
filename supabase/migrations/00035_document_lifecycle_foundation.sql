-- Document Record and File Lifecycle foundation.
-- Expand-only: legacy upload/storage paths remain authoritative until a later,
-- verified backfill and command cut-over.  This migration deliberately creates
-- no browser command RPCs or storage.object policies.
BEGIN;

CREATE TYPE public.document_origin_kind AS ENUM ('upload', 'spreadsheet_import', 'manual_record', 'email_intake', 'api_intake', 'legacy_migration');
CREATE TYPE public.document_record_state AS ENUM ('active', 'trashed');
CREATE TYPE public.document_content_availability AS ENUM ('metadata_only', 'source_attached', 'source_indexed', 'source_unreadable');
CREATE TYPE public.file_asset_availability AS ENUM ('reserved', 'uploaded', 'validating', 'available', 'quarantined', 'failed', 'expired');
CREATE TYPE public.upload_session_state AS ENUM ('reserved', 'uploading', 'uploaded', 'finalized', 'failed', 'expired', 'cancelled');
CREATE TYPE public.intake_item_state AS ENUM ('awaiting_upload', 'uploaded', 'validating', 'processing', 'ready', 'assigned', 'duplicate', 'failed', 'discarded', 'expired');
CREATE TYPE public.document_version_validation_state AS ENUM ('pending', 'valid', 'invalid');
CREATE TYPE public.document_version_state AS ENUM ('pending', 'current', 'superseded', 'failed');
CREATE TYPE public.source_analysis_run_state AS ENUM ('queued', 'running', 'succeeded', 'failed');
CREATE TYPE public.document_processing_scope AS ENUM ('validate', 'extract', 'ocr', 'relationships', 'search_index', 'full');
CREATE TYPE public.document_processing_stage AS ENUM ('queued', 'validating', 'extracting', 'matching', 'ready', 'review', 'failed');
CREATE TYPE public.document_processing_state AS ENUM ('queued', 'running', 'completed', 'failed', 'cancelled');
CREATE TYPE public.outbox_delivery_state AS ENUM ('pending', 'leased', 'delivered', 'failed', 'dead_letter');
CREATE TYPE public.storage_reservation_state AS ENUM ('active', 'consumed', 'released', 'expired');

-- These composite keys make tenant ownership available to every child FK.
ALTER TABLE public.organisations ADD CONSTRAINT organisations_id_org_unique UNIQUE (id);
ALTER TABLE public.matters ADD CONSTRAINT matters_org_id_id_unique UNIQUE (org_id, id);
ALTER TABLE public.documents ADD CONSTRAINT documents_org_id_id_unique UNIQUE (org_id, id);

CREATE TABLE public.organisation_storage_policies (
  org_id uuid PRIMARY KEY REFERENCES public.organisations(id) ON DELETE RESTRICT,
  max_pdf_bytes bigint NOT NULL DEFAULT 26214400 CHECK (max_pdf_bytes > 0),
  unique_asset_entitlement_bytes bigint NOT NULL DEFAULT 104857600 CHECK (unique_asset_entitlement_bytes > 0),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT organisation_storage_policies_pdf_ceiling CHECK (max_pdf_bytes <= 104857600)
);
CREATE TABLE public.platform_storage_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  unique_asset_guard_bytes bigint NOT NULL DEFAULT 786432000 CHECK (unique_asset_guard_bytes > 0),
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.platform_storage_policy (singleton) VALUES (true) ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE public.file_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  bucket_id text NOT NULL, object_key text NOT NULL,
  sha256 text, byte_size bigint NOT NULL CHECK (byte_size > 0), detected_mime_type text,
  availability public.file_asset_availability NOT NULL DEFAULT 'reserved',
  created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT, created_at timestamptz NOT NULL DEFAULT now(),
  validated_at timestamptz, failed_at timestamptz, expired_at timestamptz,
  CONSTRAINT file_assets_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT file_assets_object_unique UNIQUE (bucket_id, object_key),
  CONSTRAINT file_assets_private_namespace CHECK (bucket_id = 'documents' AND object_key = 'orgs/' || org_id::text || '/assets/' || id::text || '/original.pdf'),
  CONSTRAINT file_assets_sha256_format CHECK (sha256 IS NULL OR sha256 ~ '^[0-9a-f]{64}$'),
  CONSTRAINT file_assets_availability_timestamps CHECK ((availability = 'available' AND validated_at IS NOT NULL AND failed_at IS NULL AND expired_at IS NULL) OR (availability = 'failed' AND validated_at IS NULL AND failed_at IS NOT NULL AND expired_at IS NULL) OR (availability = 'expired' AND validated_at IS NULL AND failed_at IS NULL AND expired_at IS NOT NULL) OR (availability IN ('reserved','uploaded','validating','quarantined') AND validated_at IS NULL AND failed_at IS NULL AND expired_at IS NULL))
);
CREATE UNIQUE INDEX file_assets_org_sha256_unique ON public.file_assets(org_id, sha256) WHERE sha256 IS NOT NULL;

CREATE TABLE public.upload_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  asset_id uuid NOT NULL, declared_filename text NOT NULL, declared_mime_type text, declared_byte_size bigint NOT NULL CHECK (declared_byte_size > 0),
  state public.upload_session_state NOT NULL DEFAULT 'reserved', created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'), uploaded_at timestamptz, finalized_at timestamptz, failed_at timestamptz, expired_at timestamptz,
  CONSTRAINT upload_sessions_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT upload_sessions_asset_org_fkey FOREIGN KEY (org_id, asset_id) REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT upload_sessions_expiry_bound CHECK (expires_at > created_at AND expires_at <= created_at + interval '24 hours'),
  CONSTRAINT upload_sessions_state_timestamps CHECK ((state = 'uploaded' AND uploaded_at IS NOT NULL AND finalized_at IS NULL AND failed_at IS NULL AND expired_at IS NULL) OR (state = 'finalized' AND uploaded_at IS NOT NULL AND finalized_at IS NOT NULL AND failed_at IS NULL AND expired_at IS NULL) OR (state = 'failed' AND finalized_at IS NULL AND failed_at IS NOT NULL AND expired_at IS NULL) OR (state = 'expired' AND finalized_at IS NULL AND failed_at IS NULL AND expired_at IS NOT NULL) OR (state IN ('reserved','uploading','cancelled') AND uploaded_at IS NULL AND finalized_at IS NULL AND failed_at IS NULL AND expired_at IS NULL))
);

CREATE TABLE public.storage_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  upload_session_id uuid NOT NULL, reserved_bytes bigint NOT NULL CHECK (reserved_bytes > 0), state public.storage_reservation_state NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'), consumed_at timestamptz, released_at timestamptz, expired_at timestamptz,
  CONSTRAINT storage_reservations_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT storage_reservations_session_org_fkey FOREIGN KEY (org_id, upload_session_id) REFERENCES public.upload_sessions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT storage_reservations_one_active_session UNIQUE (upload_session_id),
  CONSTRAINT storage_reservations_expiry_bound CHECK (expires_at > created_at AND expires_at <= created_at + interval '24 hours'),
  CONSTRAINT storage_reservations_state_timestamps CHECK ((state = 'consumed' AND consumed_at IS NOT NULL AND released_at IS NULL AND expired_at IS NULL) OR (state = 'released' AND consumed_at IS NULL AND released_at IS NOT NULL AND expired_at IS NULL) OR (state = 'expired' AND consumed_at IS NULL AND released_at IS NULL AND expired_at IS NOT NULL) OR (state = 'active' AND consumed_at IS NULL AND released_at IS NULL AND expired_at IS NULL))
);

CREATE TABLE public.intake_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  asset_id uuid NOT NULL, upload_session_id uuid, intended_matter_id uuid, state public.intake_item_state NOT NULL DEFAULT 'awaiting_upload',
  uploaded_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  assigned_at timestamptz, failed_at timestamptz, discarded_at timestamptz, expired_at timestamptz,
  CONSTRAINT intake_items_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT intake_items_asset_org_fkey FOREIGN KEY (org_id, asset_id) REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT intake_items_session_org_fkey FOREIGN KEY (org_id, upload_session_id) REFERENCES public.upload_sessions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT intake_items_matter_org_fkey FOREIGN KEY (org_id, intended_matter_id) REFERENCES public.matters(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT intake_items_state_timestamps CHECK ((state = 'assigned' AND assigned_at IS NOT NULL AND failed_at IS NULL AND discarded_at IS NULL AND expired_at IS NULL) OR (state = 'failed' AND assigned_at IS NULL AND failed_at IS NOT NULL AND discarded_at IS NULL AND expired_at IS NULL) OR (state = 'discarded' AND assigned_at IS NULL AND failed_at IS NULL AND discarded_at IS NOT NULL AND expired_at IS NULL) OR (state = 'expired' AND assigned_at IS NULL AND failed_at IS NULL AND discarded_at IS NULL AND expired_at IS NOT NULL) OR (state IN ('awaiting_upload','uploaded','validating','processing','ready','duplicate') AND assigned_at IS NULL AND failed_at IS NULL AND discarded_at IS NULL AND expired_at IS NULL))
);

CREATE TABLE public.source_analysis_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  asset_id uuid NOT NULL, state public.source_analysis_run_state NOT NULL DEFAULT 'queued', request_key text NOT NULL,
  page_content_version integer NOT NULL DEFAULT 1 CHECK (page_content_version > 0), safe_error_code text, created_at timestamptz NOT NULL DEFAULT now(), started_at timestamptz, completed_at timestamptz, failed_at timestamptz,
  CONSTRAINT source_analysis_runs_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT source_analysis_runs_asset_org_fkey FOREIGN KEY (org_id, asset_id) REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT source_analysis_runs_request_unique UNIQUE (org_id, request_key),
  CONSTRAINT source_analysis_runs_timestamps CHECK ((state = 'running' AND started_at IS NOT NULL AND completed_at IS NULL AND failed_at IS NULL) OR (state = 'succeeded' AND started_at IS NOT NULL AND completed_at IS NOT NULL AND failed_at IS NULL) OR (state = 'failed' AND failed_at IS NOT NULL AND completed_at IS NULL) OR (state = 'queued' AND started_at IS NULL AND completed_at IS NULL AND failed_at IS NULL))
);

CREATE TABLE public.document_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL, asset_id uuid NOT NULL, version_number integer NOT NULL CHECK (version_number > 0), original_filename text NOT NULL,
  page_count integer CHECK (page_count IS NULL OR page_count > 0), validation_state public.document_version_validation_state NOT NULL DEFAULT 'pending', state public.document_version_state NOT NULL DEFAULT 'pending',
  replacement_reason text, created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT, created_at timestamptz NOT NULL DEFAULT now(), validated_at timestamptz, promoted_at timestamptz, superseded_at timestamptz, failed_at timestamptz,
  CONSTRAINT document_versions_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_versions_document_org_fkey FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_versions_asset_org_fkey FOREIGN KEY (org_id, asset_id) REFERENCES public.file_assets(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_versions_document_number_unique UNIQUE (document_id, version_number),
  CONSTRAINT document_versions_document_asset_unique UNIQUE (document_id, asset_id),
  CONSTRAINT document_versions_state_timestamps CHECK ((validation_state = 'valid' AND validated_at IS NOT NULL) OR (validation_state = 'invalid' AND failed_at IS NOT NULL AND validated_at IS NULL) OR (validation_state = 'pending' AND validated_at IS NULL AND failed_at IS NULL)),
  CONSTRAINT document_versions_state_timestamps_consistent CHECK ((state = 'current' AND validation_state = 'valid' AND promoted_at IS NOT NULL AND superseded_at IS NULL) OR (state = 'superseded' AND superseded_at IS NOT NULL) OR (state = 'failed' AND failed_at IS NOT NULL) OR state = 'pending')
);
CREATE UNIQUE INDEX document_versions_one_current_per_document ON public.document_versions(document_id) WHERE state = 'current';

CREATE TABLE public.document_version_analysis_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_version_id uuid NOT NULL, source_analysis_run_id uuid NOT NULL, binding_reason text NOT NULL, created_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT, created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT document_version_analysis_bindings_org_id_id_unique UNIQUE (org_id, id),
  CONSTRAINT document_version_analysis_bindings_version_org_fkey FOREIGN KEY (org_id, document_version_id) REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_version_analysis_bindings_run_org_fkey FOREIGN KEY (org_id, source_analysis_run_id) REFERENCES public.source_analysis_runs(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_version_analysis_bindings_unique UNIQUE (document_version_id, source_analysis_run_id)
);

CREATE TABLE public.intake_item_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  intake_item_id uuid NOT NULL, document_id uuid NOT NULL, document_version_id uuid, assigned_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT, created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT intake_item_assignments_intake_org_fkey FOREIGN KEY (org_id, intake_item_id) REFERENCES public.intake_items(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT intake_item_assignments_document_org_fkey FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT intake_item_assignments_version_org_fkey FOREIGN KEY (org_id, document_version_id) REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT intake_item_assignments_unique UNIQUE (intake_item_id, document_id)
);

CREATE TABLE public.document_processing_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  document_id uuid NOT NULL, document_version_id uuid NOT NULL, source_analysis_run_id uuid, scope public.document_processing_scope NOT NULL, stage public.document_processing_stage NOT NULL DEFAULT 'queued', state public.document_processing_state NOT NULL DEFAULT 'queued', idempotency_key text NOT NULL,
  safe_error_code text, created_at timestamptz NOT NULL DEFAULT now(), started_at timestamptz, completed_at timestamptz, failed_at timestamptz,
  CONSTRAINT document_processing_runs_document_org_fkey FOREIGN KEY (org_id, document_id) REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_processing_runs_version_org_fkey FOREIGN KEY (org_id, document_version_id) REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_processing_runs_source_org_fkey FOREIGN KEY (org_id, source_analysis_run_id) REFERENCES public.source_analysis_runs(org_id, id) ON DELETE RESTRICT,
  CONSTRAINT document_processing_runs_idempotency_unique UNIQUE (org_id, idempotency_key),
  CONSTRAINT document_processing_runs_state_timestamps CHECK ((state = 'running' AND started_at IS NOT NULL AND completed_at IS NULL AND failed_at IS NULL) OR (state = 'completed' AND started_at IS NOT NULL AND completed_at IS NOT NULL AND failed_at IS NULL) OR (state = 'failed' AND failed_at IS NOT NULL AND completed_at IS NULL) OR (state IN ('queued','cancelled') AND started_at IS NULL AND completed_at IS NULL AND failed_at IS NULL))
);

CREATE OR REPLACE FUNCTION public.document_lifecycle_payload_is_safe(payload jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE item jsonb; key_name text;
BEGIN
  IF jsonb_typeof(payload) = 'object' THEN
    FOR key_name, item IN SELECT key, value FROM jsonb_each(payload) LOOP
      IF lower(key_name) ~ '(signed.?url|credential|secret|token|raw|content|ocr|pdf|embedding|storage|object|path)' OR NOT public.document_lifecycle_payload_is_safe(item) THEN RETURN false; END IF;
    END LOOP;
  ELSIF jsonb_typeof(payload) = 'array' THEN
    FOR item IN SELECT value FROM jsonb_array_elements(payload) LOOP IF NOT public.document_lifecycle_payload_is_safe(item) THEN RETURN false; END IF; END LOOP;
  END IF;
  RETURN true;
END $$;
CREATE TABLE public.outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), org_id uuid NOT NULL REFERENCES public.organisations(id) ON DELETE RESTRICT,
  aggregate_type text NOT NULL, aggregate_id uuid NOT NULL, event_kind text NOT NULL CHECK (event_kind ~ '^[a-z][a-z0-9_.]*\.v[1-9][0-9]*$'), payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key text NOT NULL, delivery_state public.outbox_delivery_state NOT NULL DEFAULT 'pending', attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0), lease_expires_at timestamptz, delivered_at timestamptz, failed_at timestamptz, last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT outbox_events_org_id_id_unique UNIQUE (org_id, id), CONSTRAINT outbox_events_idempotency_unique UNIQUE (org_id, idempotency_key),
  CONSTRAINT outbox_events_safe_payload CHECK (public.document_lifecycle_payload_is_safe(payload)),
  CONSTRAINT outbox_events_state_timestamps CHECK ((delivery_state = 'leased' AND lease_expires_at IS NOT NULL AND delivered_at IS NULL AND failed_at IS NULL) OR (delivery_state = 'delivered' AND lease_expires_at IS NULL AND delivered_at IS NOT NULL AND failed_at IS NULL) OR (delivery_state IN ('failed','dead_letter') AND lease_expires_at IS NULL AND delivered_at IS NULL AND failed_at IS NOT NULL) OR (delivery_state = 'pending' AND lease_expires_at IS NULL AND delivered_at IS NULL AND failed_at IS NULL))
);

ALTER TABLE public.documents
  ADD COLUMN origin_kind public.document_origin_kind NOT NULL DEFAULT 'legacy_migration',
  ADD COLUMN origin_external_key text,
  ADD COLUMN record_state public.document_record_state NOT NULL DEFAULT 'active',
  ADD COLUMN content_availability public.document_content_availability NOT NULL DEFAULT 'source_attached',
  ADD COLUMN current_version_id uuid,
  ADD COLUMN copied_from_document_id uuid,
  ADD COLUMN effective_filename text,
  ADD COLUMN effective_size_bytes bigint CHECK (effective_size_bytes IS NULL OR effective_size_bytes > 0),
  ADD COLUMN trashed_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  ADD COLUMN trashed_at timestamptz,
  ADD COLUMN trashed_reason text,
  ADD COLUMN restored_at timestamptz,
  ADD COLUMN lifecycle_revision bigint NOT NULL DEFAULT 1 CHECK (lifecycle_revision >= 1),
  ADD COLUMN lifecycle_updated_at timestamptz NOT NULL DEFAULT now(),
  ADD CONSTRAINT documents_copied_from_org_fkey FOREIGN KEY (org_id, copied_from_document_id) REFERENCES public.documents(org_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT documents_current_version_org_fkey FOREIGN KEY (org_id, current_version_id) REFERENCES public.document_versions(org_id, id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT documents_record_state_timestamps CHECK ((record_state = 'trashed' AND trashed_at IS NOT NULL) OR (record_state = 'active' AND trashed_at IS NULL));
UPDATE public.documents SET record_state = CASE WHEN deleted_at IS NULL THEN 'active'::public.document_record_state ELSE 'trashed'::public.document_record_state END, trashed_at = deleted_at WHERE deleted_at IS NOT NULL;

CREATE OR REPLACE FUNCTION public.document_lifecycle_enforce_integrity()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE version_document uuid; version_org uuid; document_org uuid; version_state public.document_version_state; run_asset uuid; version_asset uuid; actual_pointer uuid;
BEGIN
  IF TG_TABLE_NAME = 'documents' THEN
    SELECT current_version_id, org_id INTO actual_pointer, document_org FROM public.documents WHERE id = NEW.id;
    IF actual_pointer IS NOT NULL THEN
      SELECT document_id, org_id, state INTO version_document, version_org, version_state FROM public.document_versions WHERE id = actual_pointer;
      IF version_document IS DISTINCT FROM NEW.id OR version_org IS DISTINCT FROM document_org OR version_state <> 'current' THEN RAISE EXCEPTION 'current version must be the current version of its document and organisation'; END IF;
    END IF;
  ELSIF TG_TABLE_NAME = 'document_versions' THEN
    SELECT document_id, org_id, state INTO version_document, version_org, version_state FROM public.document_versions WHERE id = NEW.id;
    IF version_state = 'current' AND NOT EXISTS (SELECT 1 FROM public.documents WHERE id = version_document AND org_id = version_org AND current_version_id = NEW.id) THEN RAISE EXCEPTION 'current document version must be the document current-version pointer'; END IF;
    IF version_state <> 'current' AND EXISTS (SELECT 1 FROM public.documents WHERE current_version_id = NEW.id) THEN RAISE EXCEPTION 'document current-version pointer must reference a current version'; END IF;
  ELSIF TG_TABLE_NAME = 'document_version_analysis_bindings' THEN
    SELECT asset_id INTO version_asset FROM public.document_versions WHERE id = NEW.document_version_id AND org_id = NEW.org_id;
    SELECT asset_id INTO run_asset FROM public.source_analysis_runs WHERE id = NEW.source_analysis_run_id AND org_id = NEW.org_id;
    IF version_asset IS NULL OR run_asset IS NULL OR version_asset <> run_asset THEN RAISE EXCEPTION 'analysis binding must reference the same organisation asset'; END IF;
  ELSIF TG_TABLE_NAME = 'document_processing_runs' THEN
    SELECT document_id, asset_id INTO version_document, version_asset FROM public.document_versions WHERE id = NEW.document_version_id AND org_id = NEW.org_id;
    IF version_document IS DISTINCT FROM NEW.document_id THEN RAISE EXCEPTION 'processing version must belong to its document'; END IF;
    IF NEW.source_analysis_run_id IS NOT NULL THEN
      SELECT asset_id INTO run_asset FROM public.source_analysis_runs WHERE id = NEW.source_analysis_run_id AND org_id = NEW.org_id;
      IF run_asset IS NULL OR run_asset <> version_asset THEN RAISE EXCEPTION 'processing source analysis must reference the version asset in the same organisation'; END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE CONSTRAINT TRIGGER documents_current_version_consistent AFTER INSERT OR UPDATE OF current_version_id, org_id ON public.documents DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_enforce_integrity();
CREATE CONSTRAINT TRIGGER document_versions_current_pointer_consistent AFTER INSERT OR UPDATE OF state, document_id, org_id ON public.document_versions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_enforce_integrity();
CREATE TRIGGER bindings_asset_consistent BEFORE INSERT OR UPDATE ON public.document_version_analysis_bindings FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_enforce_integrity();
CREATE TRIGGER processing_version_consistent BEFORE INSERT OR UPDATE ON public.document_processing_runs FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_enforce_integrity();
CREATE OR REPLACE FUNCTION public.document_lifecycle_touch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$ BEGIN NEW.lifecycle_revision := OLD.lifecycle_revision + 1; NEW.lifecycle_updated_at := now(); RETURN NEW; END $$;
CREATE TRIGGER documents_lifecycle_touch BEFORE UPDATE ON public.documents FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_touch();

CREATE OR REPLACE FUNCTION public.document_lifecycle_prevent_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$ BEGIN RAISE EXCEPTION 'lifecycle records are retained until the authorised purge boundary'; END $$;
CREATE OR REPLACE FUNCTION public.document_lifecycle_asset_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.org_id IS DISTINCT FROM OLD.org_id OR NEW.bucket_id IS DISTINCT FROM OLD.bucket_id OR NEW.object_key IS DISTINCT FROM OLD.object_key OR (OLD.sha256 IS NOT NULL AND NEW.sha256 IS DISTINCT FROM OLD.sha256) OR NEW.byte_size IS DISTINCT FROM OLD.byte_size OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN RAISE EXCEPTION 'file asset identity is immutable'; END IF; RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.document_lifecycle_version_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.org_id IS DISTINCT FROM OLD.org_id OR NEW.document_id IS DISTINCT FROM OLD.document_id OR NEW.asset_id IS DISTINCT FROM OLD.asset_id OR NEW.version_number IS DISTINCT FROM OLD.version_number OR NEW.original_filename IS DISTINCT FROM OLD.original_filename OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN RAISE EXCEPTION 'document version identity is immutable'; END IF; RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.document_lifecycle_outbox_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 IF NEW.id IS DISTINCT FROM OLD.id OR NEW.org_id IS DISTINCT FROM OLD.org_id OR NEW.aggregate_type IS DISTINCT FROM OLD.aggregate_type OR NEW.aggregate_id IS DISTINCT FROM OLD.aggregate_id OR NEW.event_kind IS DISTINCT FROM OLD.event_kind OR NEW.payload IS DISTINCT FROM OLD.payload OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN RAISE EXCEPTION 'outbox identity and payload are immutable'; END IF;
 NEW.updated_at := now(); RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.document_lifecycle_related_identity_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 IF TG_TABLE_NAME = 'source_analysis_runs' THEN
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.org_id IS DISTINCT FROM OLD.org_id OR NEW.asset_id IS DISTINCT FROM OLD.asset_id OR NEW.request_key IS DISTINCT FROM OLD.request_key OR NEW.page_content_version IS DISTINCT FROM OLD.page_content_version OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN RAISE EXCEPTION 'source analysis identity is immutable'; END IF;
 ELSIF TG_TABLE_NAME = 'document_version_analysis_bindings' THEN
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.org_id IS DISTINCT FROM OLD.org_id OR NEW.document_version_id IS DISTINCT FROM OLD.document_version_id OR NEW.source_analysis_run_id IS DISTINCT FROM OLD.source_analysis_run_id OR NEW.binding_reason IS DISTINCT FROM OLD.binding_reason OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN RAISE EXCEPTION 'analysis binding identity is immutable'; END IF;
 ELSIF TG_TABLE_NAME = 'storage_reservations' THEN
   IF NEW.id IS DISTINCT FROM OLD.id OR NEW.org_id IS DISTINCT FROM OLD.org_id OR NEW.upload_session_id IS DISTINCT FROM OLD.upload_session_id OR NEW.reserved_bytes IS DISTINCT FROM OLD.reserved_bytes OR NEW.created_at IS DISTINCT FROM OLD.created_at OR NEW.expires_at IS DISTINCT FROM OLD.expires_at THEN RAISE EXCEPTION 'storage reservation identity is immutable'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER file_assets_immutable BEFORE UPDATE ON public.file_assets FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_asset_immutable();
CREATE TRIGGER document_versions_immutable BEFORE UPDATE ON public.document_versions FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_version_immutable();
CREATE TRIGGER outbox_events_service_update BEFORE UPDATE ON public.outbox_events FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_outbox_update();
CREATE TRIGGER source_analysis_runs_identity_immutable BEFORE UPDATE ON public.source_analysis_runs FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_related_identity_immutable();
CREATE TRIGGER document_version_analysis_bindings_identity_immutable BEFORE UPDATE ON public.document_version_analysis_bindings FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_related_identity_immutable();
CREATE TRIGGER storage_reservations_identity_immutable BEFORE UPDATE ON public.storage_reservations FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_related_identity_immutable();
CREATE TRIGGER file_assets_no_delete BEFORE DELETE ON public.file_assets FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_prevent_delete();
CREATE TRIGGER document_versions_no_delete BEFORE DELETE ON public.document_versions FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_prevent_delete();
CREATE TRIGGER source_analysis_runs_no_delete BEFORE DELETE ON public.source_analysis_runs FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_prevent_delete();
CREATE TRIGGER document_version_analysis_bindings_no_delete BEFORE DELETE ON public.document_version_analysis_bindings FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_prevent_delete();
CREATE TRIGGER outbox_events_no_delete BEFORE DELETE ON public.outbox_events FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_prevent_delete();
CREATE TRIGGER storage_reservations_no_delete BEFORE DELETE ON public.storage_reservations FOR EACH ROW EXECUTE FUNCTION public.document_lifecycle_prevent_delete();

CREATE VIEW public.document_lifecycle_foundation_diagnostics AS
 SELECT d.org_id, d.id AS document_id, 'current_version_mismatch'::text AS issue FROM public.documents d LEFT JOIN public.document_versions v ON v.id=d.current_version_id WHERE d.current_version_id IS NOT NULL AND (v.id IS NULL OR v.org_id<>d.org_id OR v.document_id<>d.id OR v.state<>'current')
 UNION ALL SELECT dv.org_id, dv.document_id, 'current_pointer_missing' FROM public.document_versions dv LEFT JOIN public.documents d ON d.current_version_id=dv.id WHERE dv.state='current' AND d.id IS NULL;

ALTER TABLE public.organisation_storage_policies ENABLE ROW LEVEL SECURITY; ALTER TABLE public.organisation_storage_policies FORCE ROW LEVEL SECURITY;
ALTER TABLE public.platform_storage_policy ENABLE ROW LEVEL SECURITY; ALTER TABLE public.platform_storage_policy FORCE ROW LEVEL SECURITY;
ALTER TABLE public.file_assets ENABLE ROW LEVEL SECURITY; ALTER TABLE public.file_assets FORCE ROW LEVEL SECURITY;
ALTER TABLE public.upload_sessions ENABLE ROW LEVEL SECURITY; ALTER TABLE public.upload_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.storage_reservations ENABLE ROW LEVEL SECURITY; ALTER TABLE public.storage_reservations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.intake_items ENABLE ROW LEVEL SECURITY; ALTER TABLE public.intake_items FORCE ROW LEVEL SECURITY;
ALTER TABLE public.intake_item_assignments ENABLE ROW LEVEL SECURITY; ALTER TABLE public.intake_item_assignments FORCE ROW LEVEL SECURITY;
ALTER TABLE public.source_analysis_runs ENABLE ROW LEVEL SECURITY; ALTER TABLE public.source_analysis_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_versions ENABLE ROW LEVEL SECURITY; ALTER TABLE public.document_versions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_version_analysis_bindings ENABLE ROW LEVEL SECURITY; ALTER TABLE public.document_version_analysis_bindings FORCE ROW LEVEL SECURITY;
ALTER TABLE public.document_processing_runs ENABLE ROW LEVEL SECURITY; ALTER TABLE public.document_processing_runs FORCE ROW LEVEL SECURITY;
ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY; ALTER TABLE public.outbox_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.organisation_storage_policies, public.platform_storage_policy, public.file_assets, public.upload_sessions, public.storage_reservations, public.intake_items, public.intake_item_assignments, public.source_analysis_runs, public.document_versions, public.document_version_analysis_bindings, public.document_processing_runs, public.outbox_events, public.document_lifecycle_foundation_diagnostics FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.organisation_storage_policies, public.platform_storage_policy, public.file_assets, public.upload_sessions, public.storage_reservations, public.intake_items, public.intake_item_assignments, public.source_analysis_runs, public.document_versions, public.document_version_analysis_bindings, public.document_processing_runs, public.outbox_events, public.document_lifecycle_foundation_diagnostics FROM service_role;
-- UUID lifecycle tables introduce no sequences.  Narrow the historical
-- table-level document grant to the pre-foundation mutable columns instead of
-- disturbing legacy reads or writes during this compatibility window.
REVOKE UPDATE ON public.documents FROM anon, authenticated;
GRANT UPDATE (matter_id, org_id, doc_type, reference_number, doc_date, direction, issued_by, financial_year, status, review_status, reviewed_by, reviewed_at, summary, raw_metadata, ai_prompt_version, embedding, storage_path, file_hash_sha256, content_hash, deleted_at, document_class, document_category, confidence_scores, review_reason, source, embedding_model, embedding_version) ON public.documents TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.file_assets, public.upload_sessions, public.storage_reservations, public.intake_items, public.source_analysis_runs, public.document_versions, public.document_processing_runs, public.outbox_events TO service_role;
GRANT SELECT, INSERT ON TABLE public.intake_item_assignments, public.document_version_analysis_bindings TO service_role;
GRANT SELECT ON TABLE public.organisation_storage_policies, public.platform_storage_policy, public.document_lifecycle_foundation_diagnostics TO service_role;
REVOKE ALL ON FUNCTION public.document_lifecycle_payload_is_safe(jsonb), public.document_lifecycle_enforce_integrity(), public.document_lifecycle_touch(), public.document_lifecycle_prevent_delete(), public.document_lifecycle_asset_immutable(), public.document_lifecycle_version_immutable(), public.document_lifecycle_outbox_update(), public.document_lifecycle_related_identity_immutable() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.document_lifecycle_foundation_diagnostics FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.document_lifecycle_foundation_diagnostics TO service_role, postgres;

DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM public.documents WHERE origin_kind <> 'legacy_migration' OR content_availability <> 'source_attached' OR (deleted_at IS NULL AND record_state <> 'active') OR (deleted_at IS NOT NULL AND record_state <> 'trashed')) THEN RAISE EXCEPTION 'document lifecycle compatibility defaults are not clean'; END IF;
 IF EXISTS (SELECT 1 FROM public.document_lifecycle_foundation_diagnostics) THEN RAISE EXCEPTION 'document lifecycle foundation diagnostics are not clean'; END IF;
END $$;

COMMENT ON VIEW public.document_lifecycle_foundation_diagnostics IS 'Service-only additive-foundation consistency report; no tenant content.';
COMMIT;
