-- Foreign keys prove that related rows exist, but not that they belong to the
-- same organisation. Enforce that invariant in the database so it applies to
-- browser clients, Server Actions, and service-role workers alike.

CREATE OR REPLACE FUNCTION ensure_document_matter_org_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  matter_org_id uuid;
BEGIN
  SELECT org_id INTO matter_org_id FROM matters WHERE id = NEW.matter_id;
  IF matter_org_id IS NULL OR matter_org_id <> NEW.org_id THEN
    RAISE EXCEPTION 'document org_id must match its matter org_id';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ensure_note_related_org_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  matter_org_id uuid;
  document_org_id uuid;
  document_matter_id uuid;
BEGIN
  SELECT org_id INTO matter_org_id FROM matters WHERE id = NEW.matter_id;
  IF matter_org_id IS NULL OR matter_org_id <> NEW.org_id THEN
    RAISE EXCEPTION 'case note org_id must match its matter org_id';
  END IF;

  IF NEW.document_id IS NOT NULL THEN
    SELECT org_id, matter_id INTO document_org_id, document_matter_id
    FROM documents WHERE id = NEW.document_id;
    IF document_org_id IS NULL
       OR document_org_id <> NEW.org_id
       OR document_matter_id <> NEW.matter_id THEN
      RAISE EXCEPTION 'case note document must belong to the same matter and organisation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION ensure_document_link_org_match()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  source_org_id uuid;
  target_org_id uuid;
BEGIN
  SELECT org_id INTO source_org_id FROM documents WHERE id = NEW.from_doc_id;
  IF source_org_id IS NULL THEN
    RAISE EXCEPTION 'document link source document does not exist';
  END IF;

  IF NEW.to_doc_id IS NOT NULL THEN
    SELECT org_id INTO target_org_id FROM documents WHERE id = NEW.to_doc_id;
    IF target_org_id IS NULL OR target_org_id <> source_org_id THEN
      RAISE EXCEPTION 'document link endpoints must belong to the same organisation';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS documents_enforce_matter_org ON documents;
CREATE TRIGGER documents_enforce_matter_org
  BEFORE INSERT OR UPDATE OF matter_id, org_id ON documents
  FOR EACH ROW EXECUTE FUNCTION ensure_document_matter_org_match();

DROP TRIGGER IF EXISTS case_notes_enforce_related_org ON case_notes;
CREATE TRIGGER case_notes_enforce_related_org
  BEFORE INSERT OR UPDATE OF matter_id, document_id, org_id ON case_notes
  FOR EACH ROW EXECUTE FUNCTION ensure_note_related_org_match();

DROP TRIGGER IF EXISTS document_links_enforce_endpoint_org ON document_links;
CREATE TRIGGER document_links_enforce_endpoint_org
  BEFORE INSERT OR UPDATE OF from_doc_id, to_doc_id ON document_links
  FOR EACH ROW EXECUTE FUNCTION ensure_document_link_org_match();
