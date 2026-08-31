# Approval-based blockers

This is the short, human-readable queue for decisions that need review before a
tranche can safely continue. It prevents one approval boundary from stopping
the rest of the approved portfolio.

## How it works

- Add an **Open** entry when a user decision, visual review, external authority,
  or material policy choice blocks a tranche.
- State the plan, the exact decision, why it cannot be safely inferred, the
  recommended option, and the safe next action after approval.
- Continue with the next independent canonical tranche. Do not treat this file
  as approval by itself.
- When the user resolves an entry, move it to **Resolved** with the recorded
  decision. Remove it after the dependent verified tranche is committed, unless
  its history is useful to the canonical plan.

## Open

### 2026-09-01 — Search page-text source for evidence chunks

- **Plan:** Universal Search and Evidence Retrieval.
- **What is waiting:** choose the approved source that supplies retained,
  page-by-page document text (and, for scans, OCR text plus page/word
  coordinates) to the Search chunk writer.
- **What exists today:** the processing pipeline stores validated field
  candidates and their evidence quotations, but it does not retain the full
  extracted/OCR text or page coordinate stream. The only legacy
  `document_text` column belongs to staged intake records and has no live
  producer or version/page binding.
- **Why:** a chunk writer without that source would either invent passages or
  lose the exact version/page citation that Search promises. The approved plan
  requires versioned, page-aware chunks, so the extraction storage contract
  cannot be inferred as a routine implementation detail.
- **Recommended direction:** add a private, version-bound extraction artifact
  owned by the document-processing pipeline. It should keep page text and
  optional word/region anchors only for the current immutable document version,
  be service-writer-only, and be removed with the source version during Trash
  and purge. The Search worker then chunks that artifact and never reads a raw
  storage path.
- **Then:** implement the page-aware changed-chunk writer against that approved
  artifact, with the existing current-version, tenant, Trash, lease, and replay
  fences.

### 2026-09-01 — Dedicated Tasks workspace concept

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today.
- **What is waiting:** visual approval for the fixture-only Tasks workspace at
  `/dev/tasks-workspace-concept` before live Task reader/transition work begins.
- **Proposed direction:** a compact desktop queue/detail workspace with stable
  filters and pane headers; mobile becomes a list-to-detail flow with a clear
  return path. Notes show immutable origins and a live read-only Task summary;
  all Task actions live in the dedicated workspace.
- **Why:** the approved product decision establishes ownership of Task actions,
  but the visual and interaction direction needs human judgement before it is
  applied to the production application.
- **Then:** implement the secured Task reader/transition closure, organisation
  timezone semantics, and Notes summary against the approved visual contract.

## Resolved

### 2026-08-31 — Local browser QA authority for permanent-delete verification

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** local browser login/signup and creating or deleting local test
  resources are authorised whenever needed for QA.
- **Outcome:** authenticated permanent-delete browser verification is execution
  work, not an approval blocker. Continue it without requesting another product
  or local-QA permission; report only genuine verification failures or material
  decisions.

### 2026-09-01 — Task and legacy note action-item compatibility

- **Plan:** Work Orchestration, Review, Activity, Notifications, and Today.
- **Decision:** approve **Task-only current state**. Notes are immutable origins
  and show a live, read-only summary of their linked Task. The dedicated Tasks
  area is the sole place for Task state and actions; stale copied assignee,
  due-date, and resolution fields must not remain in Notes.
- **Outcome:** no dual write or legacy note-state mutation. The approved Task
  reader/transition slice must provide the replacement experience, use the
  organisation timezone, and include an idempotent one-to-one legacy backfill.
- **Next action:** create and obtain visual approval for the dedicated Tasks
  workspace concept, then implement the secured reader/transition closure.

### 2026-08-31 — Trash permanent-delete concept

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** approve the compact root-operation permanent-delete review and
  typed-confirmation direction.
- **Why it needed review:** permanent deletion is irreversible and its impact,
  holds, and confirmation flow need human visual judgement.
- **Outcome:** user reviewed and revised the `/dev/trash-permanent-delete-concept`;
  the revised compact direction is approved for the production implementation
  tranche.
- **Next action:** implement and independently verify the governed permanent-delete
  authority and durable execution workflow.

### 2026-08-31 — Retention for historical soft-deleted records

- **Plan:** Hierarchical Resource Trash, Retention, and Purge.
- **Decision:** no legacy compatibility migration is required before the first
  production deployment.
- **Why:** the local database contains test data only; no real client records
  exist that predate the automatic Trash policy. Production begins with the
  approved automatic retention policy, so it cannot contain pre-policy Trash
  entries.
- **Outcome:** do not invent or maintain a legacy exception for test data. If a
  future import introduces historical records, it must use its own approved
  import/retention contract.
