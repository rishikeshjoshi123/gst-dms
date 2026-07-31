-- =============================================================
-- Migration 00019: Fix org_invites RLS policies to use auth.jwt()
-- =============================================================

DROP POLICY IF EXISTS "invites_select_member" ON org_invites;
DROP POLICY IF EXISTS "invites_update" ON org_invites;

CREATE POLICY "invites_select_member" ON org_invites
  FOR SELECT USING (
    is_org_member(org_id)
    OR lower(invited_email) = lower(auth.jwt() ->> 'email')
  );

CREATE POLICY "invites_update" ON org_invites
  FOR UPDATE USING (
    is_org_admin(org_id)
    OR lower(invited_email) = lower(auth.jwt() ->> 'email')
  );
