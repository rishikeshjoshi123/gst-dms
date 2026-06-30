-- Add role column to org_invites
ALTER TABLE public.org_invites 
  ADD COLUMN role org_member_role NOT NULL DEFAULT 'associate';
