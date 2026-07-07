-- Migration 00011: Add quote and page_number to case_notes
ALTER TABLE case_notes
  ADD COLUMN quote text,
  ADD COLUMN page_number int;
