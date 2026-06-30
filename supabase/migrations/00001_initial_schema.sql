-- =============================================================
-- Migration 00001: Extensions + Core Schema
-- Updated: 2026-06-30
-- =============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "vector";

-- =============================================================
-- ORGANISATIONS
-- =============================================================
CREATE TABLE organisations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  created_by  uuid NOT NULL REFERENCES auth.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- ORG MEMBERS
-- =============================================================
CREATE TYPE org_member_role AS ENUM ('admin', 'associate', 'viewer');

CREATE TABLE org_members (
  org_id     uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role       org_member_role NOT NULL DEFAULT 'associate',
  joined_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, user_id)
);

-- =============================================================
-- ORG INVITES
-- =============================================================
CREATE TYPE invite_status AS ENUM ('pending', 'accepted', 'rejected', 'expired');

CREATE TABLE org_invites (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id         uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  invited_email  text NOT NULL,
  invited_by     uuid NOT NULL REFERENCES auth.users(id),
  token          text NOT NULL UNIQUE DEFAULT encode(extensions.gen_random_bytes(32), 'hex'),
  status         invite_status NOT NULL DEFAULT 'pending',
  expires_at     timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- CLIENTS
-- =============================================================
CREATE TABLE clients (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  name          text NOT NULL,
  gstin         text,
  company_name  text,
  contact_info  jsonb DEFAULT '{}',
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gstin_format CHECK (gstin IS NULL OR gstin ~ '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$')
);

-- =============================================================
-- MATTERS
-- =============================================================
CREATE TYPE matter_status AS ENUM (
  'active', 'stayed', 'disposed', 'appeal_pending', 'tribunal', 'high_court', 'supreme_court', 'closed'
);

CREATE TABLE matters (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  client_id       uuid NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  title           text NOT NULL,
  financial_year  text,
  description     text,
  status          matter_status NOT NULL DEFAULT 'active',
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- DOCUMENTS (Proceedings)
-- =============================================================
CREATE TYPE doc_direction AS ENUM ('incoming', 'outgoing');

CREATE TYPE doc_status AS ENUM (
  'uploaded', 'processing', 'analyzed', 'placed',
  'pending_placement', 'failed', 'needs_review'
);

CREATE TYPE doc_review_status AS ENUM ('unreviewed', 'reviewed');

CREATE TABLE documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id           uuid NOT NULL REFERENCES matters(id) ON DELETE CASCADE,
  org_id              uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,

  -- Document identity
  doc_type            text,
  reference_number    text,
  doc_date            date,
  direction           doc_direction,
  issued_by           text,
  financial_year      text,

  -- Processing state
  status              doc_status NOT NULL DEFAULT 'uploaded',
  review_status       doc_review_status NOT NULL DEFAULT 'unreviewed',
  reviewed_by         uuid REFERENCES auth.users(id),
  reviewed_at         timestamptz,

  -- AI output
  summary             text,
  raw_metadata        jsonb DEFAULT '{}',
  ai_prompt_version   text,

  -- Embedding (768-dim for text-embedding-004)
  embedding           vector(768),

  -- Storage
  storage_path        text NOT NULL,
  file_hash_sha256    text,
  content_hash        text,

  -- Full-text search
  search_vector       tsvector GENERATED ALWAYS AS (
    to_tsvector('english',
      coalesce(doc_type, '') || ' ' ||
      coalesce(reference_number, '') || ' ' ||
      coalesce(summary, '') || ' ' ||
      coalesce(issued_by, '')
    )
  ) STORED,

  -- Audit
  created_by          uuid REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz
);

-- =============================================================
-- DOCUMENT LINKS (Chain graph edges)
-- =============================================================
CREATE TYPE link_type AS ENUM (
  'responds_to', 'arises_from', 'challenges', 'summarizes'
);

CREATE TYPE link_status AS ENUM ('confirmed', 'pending', 'rejected');

CREATE TABLE document_links (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_doc_id        uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  to_doc_id          uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  link_type          link_type NOT NULL,
  confidence         numeric(4,3) CHECK (confidence BETWEEN 0 AND 1),
  status             link_status NOT NULL DEFAULT 'pending',
  pending_ref_number text,    -- stored when target doc not yet uploaded
  created_by         uuid REFERENCES auth.users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT no_self_link CHECK (from_doc_id <> to_doc_id),
  CONSTRAINT unique_link UNIQUE (from_doc_id, to_doc_id, link_type)
);

-- =============================================================
-- SUPPORTING DOCUMENTS
-- =============================================================
CREATE TYPE supporting_doc_category AS ENUM (
  'invoices', 'bank_statements', 'contracts', 'correspondence', 'others'
);

CREATE TABLE supporting_documents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id     uuid NOT NULL REFERENCES matters(id) ON DELETE CASCADE,
  org_id        uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  category      supporting_doc_category NOT NULL DEFAULT 'others',
  title         text NOT NULL,
  doc_date      date,
  amount        numeric(18,2),
  parties       text[],
  description   text,
  raw_metadata  jsonb DEFAULT '{}',
  storage_path  text NOT NULL,
  was_promoted  boolean NOT NULL DEFAULT false,  -- audit: was ever in timeline
  created_by    uuid REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

-- =============================================================
-- SUPPORTING DOC LINKS (evidence ↔ proceedings)
-- =============================================================
CREATE TABLE supporting_doc_links (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supporting_doc_id    uuid NOT NULL REFERENCES supporting_documents(id) ON DELETE CASCADE,
  document_id          uuid NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  note                 text,
  created_by           uuid REFERENCES auth.users(id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT unique_support_link UNIQUE (supporting_doc_id, document_id)
);

-- =============================================================
-- STAGED DOCUMENTS (global upload, not yet assigned)
-- =============================================================
CREATE TYPE staged_status AS ENUM (
  'pending_assignment', 'analyzing', 'ready_to_assign', 'assigned'
);

CREATE TABLE staged_documents (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id               uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  uploaded_by          uuid NOT NULL REFERENCES auth.users(id),
  storage_path         text NOT NULL,
  status               staged_status NOT NULL DEFAULT 'pending_assignment',
  suggested_matter_ids jsonb DEFAULT '[]',
  raw_metadata         jsonb DEFAULT '{}',
  created_at           timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- DEADLINES
-- =============================================================
CREATE TYPE deadline_type AS ENUM (
  'appeal_window', 'pre_deposit', 'hearing_date',
  'reply_deadline', 'stay_application', 'other'
);

CREATE TABLE deadlines (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id          uuid NOT NULL REFERENCES matters(id) ON DELETE CASCADE,
  document_id        uuid REFERENCES documents(id) ON DELETE SET NULL,
  type               deadline_type NOT NULL,
  due_date           date NOT NULL,
  description        text,
  reminder_sent_30d  boolean NOT NULL DEFAULT false,
  reminder_sent_7d   boolean NOT NULL DEFAULT false,
  is_resolved        boolean NOT NULL DEFAULT false,
  resolved_by        uuid REFERENCES auth.users(id),
  resolved_at        timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- CASE NOTES
-- =============================================================
CREATE TYPE note_template_type AS ENUM (
  'hearing_note', 'client_instruction', 'research_note', 'general'
);

CREATE TABLE case_notes (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id               uuid NOT NULL REFERENCES matters(id) ON DELETE CASCADE,
  document_id             uuid REFERENCES documents(id) ON DELETE SET NULL,
  org_id                  uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  author_id               uuid NOT NULL REFERENCES auth.users(id),
  content                 text NOT NULL,
  template_type           note_template_type NOT NULL DEFAULT 'general',

  -- Action item fields
  is_action_item          boolean NOT NULL DEFAULT false,
  action_item_assignee    uuid REFERENCES auth.users(id),
  action_item_due_date    date,
  action_item_resolved    boolean NOT NULL DEFAULT false,

  -- Threading
  is_pinned               boolean NOT NULL DEFAULT false,
  parent_note_id          uuid REFERENCES case_notes(id) ON DELETE SET NULL,

  -- Full-text search
  search_vector           tsvector GENERATED ALWAYS AS (
    to_tsvector('english', coalesce(content, ''))
  ) STORED,

  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  deleted_at              timestamptz
);

-- =============================================================
-- ACTIVITY LOGS
-- =============================================================
CREATE TYPE entity_type AS ENUM (
  'document', 'matter', 'client', 'case_note',
  'document_link', 'deadline', 'wiki_section',
  'organisation', 'user', 'staged_document', 'supporting_document'
);

CREATE TABLE activity_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  user_id       uuid REFERENCES auth.users(id),
  action        text NOT NULL,
  entity_type   entity_type NOT NULL,
  entity_id     uuid,
  description   text,
  metadata      jsonb DEFAULT '{}',   -- before/after state for reversible actions
  is_reversible boolean NOT NULL DEFAULT false,
  reversed_by   uuid REFERENCES auth.users(id),
  reversed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- WIKI SECTIONS
-- =============================================================
CREATE TABLE wiki_sections (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  matter_id       uuid NOT NULL REFERENCES matters(id) ON DELETE CASCADE,
  section_key     text NOT NULL,
  title           text NOT NULL,
  content         jsonb DEFAULT '{}',
  is_user_edited  boolean NOT NULL DEFAULT false,
  last_ai_content jsonb,           -- preserved even after user edits
  updated_at      timestamptz NOT NULL DEFAULT now(),
  updated_by      uuid REFERENCES auth.users(id),
  CONSTRAINT unique_section UNIQUE (matter_id, section_key)
);

CREATE TABLE wiki_section_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  wiki_section_id  uuid NOT NULL REFERENCES wiki_sections(id) ON DELETE CASCADE,
  content          jsonb NOT NULL,
  generated_by     text NOT NULL,  -- 'ai' | user_id
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- NOTIFICATIONS
-- =============================================================
CREATE TYPE notification_type AS ENUM (
  'org_invite', 'mention', 'deadline_approaching',
  'document_ready', 'chain_suggestion', 'processing_failed',
  'staged_doc_ready', 'wiki_ai_suggestion'
);

CREATE TABLE notifications (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type         notification_type NOT NULL,
  title        text NOT NULL,
  body         text,
  entity_type  entity_type,
  entity_id    uuid,
  is_read      boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- =============================================================
-- USER NOTIFICATION PREFERENCES
-- =============================================================
CREATE TABLE user_notification_prefs (
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  org_id              uuid NOT NULL REFERENCES organisations(id) ON DELETE CASCADE,
  email_on_mention    boolean NOT NULL DEFAULT true,
  email_on_deadline   boolean NOT NULL DEFAULT true,
  email_on_invite     boolean NOT NULL DEFAULT true,
  email_on_new_doc    boolean NOT NULL DEFAULT false,
  email_on_failure    boolean NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, org_id)
);

-- =============================================================
-- INDEXES
-- =============================================================

-- Documents
CREATE INDEX idx_documents_matter ON documents(matter_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_documents_org ON documents(org_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_documents_status ON documents(status);
CREATE INDEX idx_documents_reference ON documents(reference_number) WHERE reference_number IS NOT NULL;
CREATE INDEX idx_documents_search ON documents USING GIN(search_vector);
CREATE INDEX idx_documents_content_hash ON documents(content_hash) WHERE content_hash IS NOT NULL;
CREATE INDEX idx_documents_file_hash ON documents(file_hash_sha256) WHERE file_hash_sha256 IS NOT NULL;

-- pgvector IVFFlat index for semantic search (requires ~1000+ docs to be effective)
CREATE INDEX idx_documents_embedding ON documents
  USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- Document links
CREATE INDEX idx_doc_links_from ON document_links(from_doc_id);
CREATE INDEX idx_doc_links_to ON document_links(to_doc_id);
CREATE INDEX idx_doc_links_pending_ref ON document_links(pending_ref_number) WHERE pending_ref_number IS NOT NULL;

-- Case notes
CREATE INDEX idx_case_notes_matter ON case_notes(matter_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_case_notes_document ON case_notes(document_id) WHERE document_id IS NOT NULL;
CREATE INDEX idx_case_notes_search ON case_notes USING GIN(search_vector);
CREATE INDEX idx_case_notes_action_items ON case_notes(action_item_assignee) WHERE is_action_item = true;

-- Activity logs
CREATE INDEX idx_activity_org ON activity_logs(org_id, created_at DESC);
CREATE INDEX idx_activity_entity ON activity_logs(entity_type, entity_id);

-- Notifications
CREATE INDEX idx_notifications_user ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_org ON notifications(org_id, created_at DESC);

-- Deadlines
CREATE INDEX idx_deadlines_matter ON deadlines(matter_id);
CREATE INDEX idx_deadlines_due_date ON deadlines(due_date) WHERE is_resolved = false;

-- Staged documents
CREATE INDEX idx_staged_org ON staged_documents(org_id, status, created_at);

-- trgm index for fuzzy reference number matching
CREATE INDEX idx_documents_ref_trgm ON documents USING GIN(reference_number gin_trgm_ops);
