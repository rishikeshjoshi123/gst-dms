-- =============================================================
-- Migration 00017: Enforce Single Organization Per User
-- =============================================================

-- Ensure a user can only be part of one organization at a time
ALTER TABLE public.org_members 
ADD CONSTRAINT unique_user_id UNIQUE (user_id);
