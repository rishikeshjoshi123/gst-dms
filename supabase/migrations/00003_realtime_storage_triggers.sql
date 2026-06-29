-- =============================================================
-- Migration 00003: Supabase Realtime + Storage Buckets
-- =============================================================

-- REALTIME: subscribe to live document processing status
ALTER PUBLICATION supabase_realtime ADD TABLE documents;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE deadlines;
ALTER PUBLICATION supabase_realtime ADD TABLE staged_documents;

-- =============================================================
-- STORAGE BUCKETS
-- =============================================================

-- Main documents bucket (private — all access via signed URLs)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documents',
  'documents',
  false,
  52428800,   -- 50 MB per file
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- Staging bucket for global upload flow
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'staging',
  'staging',
  false,
  52428800,
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- =============================================================
-- STORAGE RLS POLICIES
-- =============================================================

-- DOCUMENTS BUCKET --

-- Allow org members to upload to their matter's folder
-- Path format: matters/{matter_id}/documents/{doc_id}/original.pdf
CREATE POLICY "docs_upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'documents'
    AND EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id::text = (string_to_array(name, '/'))[2]
        AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "docs_read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'documents'
    AND EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id::text = (string_to_array(name, '/'))[2]
        AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "docs_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'documents'
    AND EXISTS (
      SELECT 1 FROM matters m
        JOIN organisations o ON o.id = m.org_id
      WHERE m.id::text = (string_to_array(name, '/'))[2]
        AND is_org_admin(o.id)
    )
  );

-- STAGING BUCKET --

-- Path format: staging/{org_id}/{temp_id}/original.pdf
CREATE POLICY "staging_upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'staging'
    AND is_org_member((string_to_array(name, '/'))[2]::uuid)
  );

CREATE POLICY "staging_read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'staging'
    AND is_org_member((string_to_array(name, '/'))[2]::uuid)
  );

CREATE POLICY "staging_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'staging'
    AND is_org_member((string_to_array(name, '/'))[2]::uuid)
  );

-- =============================================================
-- HELPER FUNCTIONS
-- =============================================================

-- Auto-insert org creator as admin member after org creation
CREATE OR REPLACE FUNCTION handle_new_org()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO org_members (org_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'admin');
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_org_created
  AFTER INSERT ON organisations
  FOR EACH ROW EXECUTE FUNCTION handle_new_org();

-- Auto-update updated_at on case_notes
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER case_notes_updated_at
  BEFORE UPDATE ON case_notes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER wiki_sections_updated_at
  BEFORE UPDATE ON wiki_sections
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
