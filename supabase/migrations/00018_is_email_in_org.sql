-- =============================================================
-- Migration 00018: Helper for Email Org Check
-- =============================================================

CREATE OR REPLACE FUNCTION is_email_in_any_org(search_email text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM auth.users u
    JOIN org_members m ON u.id = m.user_id
    WHERE u.email = search_email
  );
$$;
