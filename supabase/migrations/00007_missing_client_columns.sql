-- =============================================================
-- Migration 00007: Add missing columns
-- =============================================================

ALTER TABLE clients
  ADD COLUMN pan text,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

-- Ensure PAN is uppercase and valid format if provided
ALTER TABLE clients
  ADD CONSTRAINT pan_format CHECK (pan IS NULL OR pan ~ '^[A-Z]{5}[0-9]{4}[A-Z]{1}$');
