-- =============================================================
-- Migration 00014: Fix Missing Delete RLS Policies
-- =============================================================
-- Issues fixed:
-- 1. document_links had no DELETE policy -> deleteDocumentLink() always failed silently
-- 2. clients_delete policy was mis-typed as FOR UPDATE -> conflicted with clients_update
-- 3. documents UPDATE policy blocked soft-deletes (checked deleted_at IS NULL)
-- 4. matters UPDATE policy blocked soft-deletes (checked deleted_at IS NULL)
-- 5. deadlines had no DELETE policy
-- =============================================================

-- 1. Add missing DELETE policy on document_links
DROP POLICY IF EXISTS "doc_links_delete" ON document_links;
CREATE POLICY "doc_links_delete" ON document_links
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM documents d
      WHERE d.id = from_doc_id AND is_org_member(d.org_id)
    )
  );

-- 2. Fix clients: drop the broken 'clients_delete' policy (was FOR UPDATE, wrong),
--    and broaden clients_update to allow soft-deletes (remove deleted_at IS NULL guard)
DROP POLICY IF EXISTS "clients_delete" ON clients;
DROP POLICY IF EXISTS "clients_update" ON clients;
CREATE POLICY "clients_update" ON clients
  FOR UPDATE USING (is_org_member(org_id));

-- 3. Fix matters: remove the deleted_at IS NULL guard from UPDATE policy
--    so that the soft-delete UPDATE can actually execute
DROP POLICY IF EXISTS "matters_update" ON matters;
CREATE POLICY "matters_update" ON matters
  FOR UPDATE USING (is_org_member(org_id));

-- 4. Fix documents: remove the deleted_at IS NULL guard from UPDATE policy
--    so that soft-delete (setting deleted_at) can actually execute
DROP POLICY IF EXISTS "documents_update" ON documents;
CREATE POLICY "documents_update" ON documents
  FOR UPDATE USING (is_org_member(org_id));

-- 5. Add DELETE policy on deadlines (needed for cascade cleanup)
DROP POLICY IF EXISTS "deadlines_delete" ON deadlines;
CREATE POLICY "deadlines_delete" ON deadlines
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );
