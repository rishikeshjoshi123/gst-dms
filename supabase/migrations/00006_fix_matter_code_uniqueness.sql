-- Fix matter_code uniqueness constraint
-- The matter_code was defined as globally UNIQUE, which causes insertion failures 
-- when auto-generating sequences for new organizations.
-- This migration scopes the uniqueness to the organization.

BEGIN;

-- Drop the global unique constraint
ALTER TABLE matters
DROP CONSTRAINT IF EXISTS matters_matter_code_key;

-- Add a composite unique constraint
ALTER TABLE matters
ADD CONSTRAINT matters_org_id_matter_code_key UNIQUE (org_id, matter_code);

COMMIT;
