-- =============================================================
-- Migration 00002: Row Level Security
-- =============================================================

-- Helper function: check org membership
CREATE OR REPLACE FUNCTION is_org_member(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM org_members
    WHERE org_id = check_org_id
      AND user_id = auth.uid()
  );
$$;

-- Helper function: check org admin
CREATE OR REPLACE FUNCTION is_org_admin(check_org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM org_members
    WHERE org_id = check_org_id
      AND user_id = auth.uid()
      AND role = 'admin'
  );
$$;

-- Helper function: get user's org IDs
CREATE OR REPLACE FUNCTION my_org_ids()
RETURNS uuid[]
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT array_agg(org_id) FROM org_members WHERE user_id = auth.uid();
$$;

-- =============================================================
-- ENABLE RLS ON ALL TABLES
-- =============================================================
ALTER TABLE organisations ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE org_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE matters ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE supporting_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE supporting_doc_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE staged_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE deadlines ENABLE ROW LEVEL SECURITY;
ALTER TABLE case_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE wiki_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE wiki_section_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_notification_prefs ENABLE ROW LEVEL SECURITY;

-- =============================================================
-- ORGANISATIONS
-- =============================================================
CREATE POLICY "org_select" ON organisations
  FOR SELECT USING (is_org_member(id) OR created_by = auth.uid());

CREATE POLICY "org_insert" ON organisations
  FOR INSERT WITH CHECK (auth.uid() = created_by);

CREATE POLICY "org_update" ON organisations
  FOR UPDATE USING (is_org_admin(id));

-- =============================================================
-- ORG MEMBERS
-- =============================================================
CREATE POLICY "members_select" ON org_members
  FOR SELECT USING (is_org_member(org_id));

CREATE POLICY "members_insert" ON org_members
  FOR INSERT WITH CHECK (is_org_admin(org_id) OR user_id = auth.uid());

CREATE POLICY "members_update" ON org_members
  FOR UPDATE USING (is_org_admin(org_id));

CREATE POLICY "members_delete" ON org_members
  FOR DELETE USING (is_org_admin(org_id) OR user_id = auth.uid());

-- =============================================================
-- ORG INVITES
-- =============================================================
CREATE POLICY "invites_select_member" ON org_invites
  FOR SELECT USING (
    is_org_member(org_id)
    OR invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  );

CREATE POLICY "invites_insert" ON org_invites
  FOR INSERT WITH CHECK (is_org_admin(org_id));

CREATE POLICY "invites_update" ON org_invites
  FOR UPDATE USING (
    is_org_admin(org_id)
    OR invited_email = (SELECT email FROM auth.users WHERE id = auth.uid())
  );

-- =============================================================
-- CLIENTS
-- =============================================================
CREATE POLICY "clients_select" ON clients
  FOR SELECT USING (is_org_member(org_id) AND deleted_at IS NULL);

CREATE POLICY "clients_insert" ON clients
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "clients_update" ON clients
  FOR UPDATE USING (is_org_member(org_id) AND deleted_at IS NULL);

CREATE POLICY "clients_delete" ON clients
  FOR UPDATE USING (is_org_admin(org_id));  -- soft delete via update

-- =============================================================
-- MATTERS
-- =============================================================
CREATE POLICY "matters_select" ON matters
  FOR SELECT USING (is_org_member(org_id) AND deleted_at IS NULL);

CREATE POLICY "matters_insert" ON matters
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "matters_update" ON matters
  FOR UPDATE USING (is_org_member(org_id) AND deleted_at IS NULL);

-- =============================================================
-- DOCUMENTS
-- =============================================================
CREATE POLICY "documents_select" ON documents
  FOR SELECT USING (is_org_member(org_id) AND deleted_at IS NULL);

CREATE POLICY "documents_insert" ON documents
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "documents_update" ON documents
  FOR UPDATE USING (is_org_member(org_id) AND deleted_at IS NULL);

-- =============================================================
-- DOCUMENT LINKS
-- =============================================================
-- Derive org access from the source document
CREATE POLICY "doc_links_select" ON document_links
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM documents d
      WHERE d.id = from_doc_id AND is_org_member(d.org_id)
    )
  );

CREATE POLICY "doc_links_insert" ON document_links
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM documents d
      WHERE d.id = from_doc_id AND is_org_member(d.org_id)
    )
  );

CREATE POLICY "doc_links_update" ON document_links
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM documents d
      WHERE d.id = from_doc_id AND is_org_member(d.org_id)
    )
  );

-- =============================================================
-- SUPPORTING DOCUMENTS
-- =============================================================
CREATE POLICY "supdocs_select" ON supporting_documents
  FOR SELECT USING (is_org_member(org_id) AND deleted_at IS NULL);

CREATE POLICY "supdocs_insert" ON supporting_documents
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "supdocs_update" ON supporting_documents
  FOR UPDATE USING (is_org_member(org_id) AND deleted_at IS NULL);

-- =============================================================
-- SUPPORTING DOC LINKS
-- =============================================================
CREATE POLICY "supdoc_links_select" ON supporting_doc_links
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM supporting_documents sd
      WHERE sd.id = supporting_doc_id AND is_org_member(sd.org_id)
    )
  );

CREATE POLICY "supdoc_links_insert" ON supporting_doc_links
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM supporting_documents sd
      WHERE sd.id = supporting_doc_id AND is_org_member(sd.org_id)
    )
  );

CREATE POLICY "supdoc_links_delete" ON supporting_doc_links
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM supporting_documents sd
      WHERE sd.id = supporting_doc_id AND is_org_member(sd.org_id)
    )
  );

-- =============================================================
-- STAGED DOCUMENTS
-- =============================================================
CREATE POLICY "staged_select" ON staged_documents
  FOR SELECT USING (is_org_member(org_id));

CREATE POLICY "staged_insert" ON staged_documents
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "staged_update" ON staged_documents
  FOR UPDATE USING (is_org_member(org_id));

CREATE POLICY "staged_delete" ON staged_documents
  FOR DELETE USING (is_org_member(org_id));

-- =============================================================
-- DEADLINES
-- =============================================================
CREATE POLICY "deadlines_select" ON deadlines
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "deadlines_insert" ON deadlines
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "deadlines_update" ON deadlines
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );

-- =============================================================
-- CASE NOTES
-- =============================================================
CREATE POLICY "notes_select" ON case_notes
  FOR SELECT USING (is_org_member(org_id) AND deleted_at IS NULL);

CREATE POLICY "notes_insert" ON case_notes
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "notes_update" ON case_notes
  FOR UPDATE USING (
    is_org_member(org_id)
    AND deleted_at IS NULL
    AND (author_id = auth.uid() OR is_org_admin(org_id))
  );

-- =============================================================
-- ACTIVITY LOGS
-- =============================================================
CREATE POLICY "activity_select" ON activity_logs
  FOR SELECT USING (is_org_member(org_id));

CREATE POLICY "activity_insert" ON activity_logs
  FOR INSERT WITH CHECK (is_org_member(org_id));

-- Activity logs are append-only; only allow update for reversals by admins
CREATE POLICY "activity_update_reversal" ON activity_logs
  FOR UPDATE USING (is_org_admin(org_id) AND is_reversible = true AND reversed_at IS NULL);

-- =============================================================
-- WIKI SECTIONS
-- =============================================================
CREATE POLICY "wiki_select" ON wiki_sections
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "wiki_insert" ON wiki_sections
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "wiki_update" ON wiki_sections
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM matters m
      WHERE m.id = matter_id AND is_org_member(m.org_id)
    )
  );

-- =============================================================
-- WIKI SECTION VERSIONS
-- =============================================================
CREATE POLICY "wiki_versions_select" ON wiki_section_versions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM wiki_sections ws
      JOIN matters m ON m.id = ws.matter_id
      WHERE ws.id = wiki_section_id AND is_org_member(m.org_id)
    )
  );

CREATE POLICY "wiki_versions_insert" ON wiki_section_versions
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM wiki_sections ws
      JOIN matters m ON m.id = ws.matter_id
      WHERE ws.id = wiki_section_id AND is_org_member(m.org_id)
    )
  );

-- =============================================================
-- NOTIFICATIONS
-- =============================================================
CREATE POLICY "notifications_select" ON notifications
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "notifications_insert" ON notifications
  FOR INSERT WITH CHECK (is_org_member(org_id));

CREATE POLICY "notifications_update" ON notifications
  FOR UPDATE USING (user_id = auth.uid());  -- mark as read

-- =============================================================
-- USER NOTIFICATION PREFS
-- =============================================================
CREATE POLICY "notif_prefs_select" ON user_notification_prefs
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "notif_prefs_upsert" ON user_notification_prefs
  FOR ALL USING (user_id = auth.uid());

-- =============================================================
-- ROLE PRIVILEGES (Required for local & production)
-- =============================================================
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL ROUTINES IN SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON ROUTINES TO postgres, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres, anon, authenticated, service_role;
